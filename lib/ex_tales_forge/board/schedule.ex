defmodule TalesForge.Board.Schedule do
  @moduledoc """
  The runs of the scheduled jobs and the rows of the Upcoming panel on the
  team page (`TalesForgeWeb.TeamUpcoming`).

  The jobs are in the team config (`Workflow.Team` `jobs`, cron lines in UTC).
  The Workflow Oban instance runs them (`TalesForge.Workflow.Jobs.config/0`).
  A code job calls `track/2` around its work: the run gets a row in
  `scheduled_runs` (`TalesForge.Board.ScheduledRun`), `"open"` at the start,
  then `"ok"` or `"failed"`. A code job starts no bot.

  A bot job (the owner is a bot) runs `start_bot_run/3`: one transaction
  opens the run, adds the card-less `schedule.run` wake for the bot
  (`TalesForge.Board.Workers.Notify.run_job/3`) and adds the time limit
  check at `deadline_at` (`TalesForge.Board.Workers.NoReport`). The bot sends
  its result with `POST /internal/board/runs/:id/finish` (`finish_by_bot/3`).
  A run with no report at `deadline_at` gets `"no_report"`.

  All times are in UTC. The browser shows them in the viewer's local time
  zone. Changes are broadcast on `topic/0` as `{:schedule, :changed}`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias TalesForge.Board.ScheduledRun
  alias TalesForge.Board.Workers.{NoReport, Notify}
  alias TalesForge.Workflow.{Jobs, Repo}

  @detail_max 2000

  @topic "board:schedule"

  @typedoc "One row of the Upcoming panel."
  @type row :: %{
          id: String.t(),
          name: String.t(),
          owner: String.t(),
          code?: boolean(),
          next_at: DateTime.t(),
          last: ScheduledRun.t() | nil
        }

  @doc "The PubSub topic of the run changes."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Subscribes the caller to `topic/0`."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(TalesForge.PubSub, @topic)

  @doc """
  Runs `fun` as a run of the code job `job_id` and records the run. A
  result of `:ok` or `{:ok, _}` gives `"ok"`. Each other result and each
  exception gives `"failed"`. Returns the result of `fun`; an exception is
  raised again after the run is recorded, so Oban sees it.
  """
  @spec track(String.t(), (-> term())) :: term()
  def track(job_id, fun) when is_binary(job_id) and is_function(fun, 0) do
    {:ok, run} = start(job_id, "code")

    try do
      result = fun.()
      finish(run, status(result), detail(result))
      result
    rescue
      e ->
        finish(run, "failed", Exception.message(e))
        reraise e, __STACKTRACE__
    end
  end

  defp status(:ok), do: "ok"
  defp status({:ok, _}), do: "ok"
  defp status(_), do: "failed"

  defp detail({:error, reason}), do: inspect(reason)
  defp detail(_), do: nil

  @doc "Records the start of a run of `job_id` by `owner` (an open run)."
  @spec start(String.t(), String.t(), DateTime.t()) ::
          {:ok, ScheduledRun.t()} | {:error, Ecto.Changeset.t()}
  def start(job_id, owner, now \\ DateTime.utc_now()) do
    %ScheduledRun{}
    |> ScheduledRun.changeset(%{job_id: job_id, owner: owner, status: "open", started_at: now})
    |> Repo.insert()
    |> tap(&broadcast/1)
  end

  @doc ~s|Records the end of `run` with `status` ("ok" or "failed").|
  @spec finish(ScheduledRun.t(), String.t(), String.t() | nil, DateTime.t()) ::
          {:ok, ScheduledRun.t()} | {:error, Ecto.Changeset.t()}
  def finish(%ScheduledRun{} = run, status, detail \\ nil, now \\ DateTime.utc_now()) do
    run
    |> ScheduledRun.changeset(%{status: status, detail: detail, finished_at: now})
    |> Repo.update()
    |> tap(&broadcast/1)
  end

  @doc """
  Opens a run of the bot job `job` (owner: the bot id) and, in the same
  transaction, adds the `schedule.run` wake for the bot and the time limit
  check at `now` + `limit_min`. Returns the run.
  """
  @spec start_bot_run(Workflow.Team.t(), Workflow.Team.job(), DateTime.t()) ::
          {:ok, ScheduledRun.t()} | {:error, term()}
  def start_bot_run(%Workflow.Team{} = team, %{owner: owner} = job, now \\ DateTime.utc_now()) do
    bot = Workflow.Team.bot_id(team, owner) || raise ArgumentError, "#{owner} is not a bot"
    deadline = DateTime.add(now, job.limit_min * 60)

    attrs = %{
      job_id: job.id,
      owner: Atom.to_string(bot),
      status: "open",
      started_at: now,
      deadline_at: deadline
    }

    Multi.new()
    |> Multi.insert(:run, ScheduledRun.changeset(%ScheduledRun{}, attrs))
    |> Jobs.insert(:wake, fn %{run: run} -> Notify.run_job(bot, job, run) end)
    |> Jobs.insert(:limit, fn %{run: run} -> NoReport.job(run) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{run: run}} ->
        broadcast({:ok, run})
        {:ok, Repo.get!(ScheduledRun, run.id)}

      {:error, _step, reason, _done} ->
        {:error, reason}
    end
  end

  @doc """
  The report of `bot` for the run `run_id`: `params` has `status` (`"ok"` or
  `"failed"`) and an optional `detail`. Only the bot that owns the run can
  finish it. A late report after "no_report" is kept: it replaces
  "no_report".
  """
  @spec finish_by_bot(String.t(), atom(), map()) ::
          {:ok, ScheduledRun.t()}
          | {:error, :not_found | :forbidden | :closed | :bad_status | Ecto.Changeset.t()}
  def finish_by_bot(run_id, bot, params) do
    with {:ok, run} <- fetch(run_id),
         :ok <- owner?(run, bot),
         :ok <- reportable?(run),
         {:ok, status} <- report_status(params["status"]) do
      finish(run, status, report_detail(params["detail"]))
    end
  end

  defp fetch(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %ScheduledRun{} = run <- Repo.get(ScheduledRun, uuid) do
      {:ok, run}
    else
      _ -> {:error, :not_found}
    end
  end

  defp owner?(%ScheduledRun{owner: owner}, bot),
    do: if(owner == to_string(bot), do: :ok, else: {:error, :forbidden})

  defp reportable?(%ScheduledRun{status: s}) when s in ~w(open no_report), do: :ok
  defp reportable?(_run), do: {:error, :closed}

  defp report_status(s) when s in ~w(ok failed), do: {:ok, s}
  defp report_status(_), do: {:error, :bad_status}

  defp report_detail(d) when is_binary(d), do: String.slice(d, 0, @detail_max)
  defp report_detail(_), do: nil

  @doc """
  How many seconds other wakes to `bot` must still wait at `now`: an open
  run of an exclusive job of `bot` (a job with `hold_min`) holds them until
  the bot reports or `hold_min` minutes pass after the start. 0 when nothing
  holds.
  """
  @spec hold_seconds(Workflow.Team.t(), atom() | String.t(), DateTime.t()) :: non_neg_integer()
  def hold_seconds(%Workflow.Team{} = team, bot, %DateTime{} = now) do
    holds = for %{hold_min: h, id: id} <- team.jobs, is_integer(h), into: %{}, do: {id, h}

    if holds == %{} do
      0
    else
      owner = to_string(bot)
      ids = Map.keys(holds)

      from(r in ScheduledRun,
        where: r.owner == ^owner and r.status == "open" and r.job_id in ^ids,
        select: {r.job_id, r.started_at}
      )
      |> Repo.all()
      |> Enum.map(fn {id, started} ->
        DateTime.diff(DateTime.add(started, holds[id] * 60), now)
      end)
      |> Enum.max(fn -> 0 end)
      |> max(0)
    end
  end

  @doc """
  Closes `run` with "no_report" when it is still open at `now` and its
  deadline has come. Returns `:no_report`, `:closed` (the bot reported) or
  `{:wait, seconds}` (the deadline is later).
  """
  @spec close_if_no_report(String.t(), DateTime.t()) ::
          :no_report | :closed | {:wait, pos_integer()}
  def close_if_no_report(run_id, now \\ DateTime.utc_now()) do
    case fetch(run_id) do
      {:ok, %ScheduledRun{status: "open", deadline_at: %DateTime{} = deadline} = run} ->
        case DateTime.diff(deadline, now) do
          wait when wait > 0 ->
            {:wait, wait}

          _ ->
            minutes = div(DateTime.diff(deadline, run.started_at), 60)
            {:ok, _} = finish(run, "no_report", "No report in #{minutes} min.", now)
            :no_report
        end

      _ ->
        :closed
    end
  end

  defp broadcast({:ok, _}),
    do: Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, {:schedule, :changed})

  defp broadcast(_), do: :ok

  @doc "The last run of each job id, by job id. A job with no run has no key."
  @spec last_runs() :: %{String.t() => ScheduledRun.t()}
  def last_runs do
    from(r in ScheduledRun,
      distinct: r.job_id,
      order_by: [asc: r.job_id, desc: r.started_at]
    )
    |> Repo.all()
    |> Map.new(&{&1.job_id, &1})
  end

  @doc """
  The rows of the Upcoming panel: each job of `team` with its next time
  after `now` (UTC), its owner and its last run. Pure.

  The rows keep the order of the job list in the team config, so the order
  does not change with the clock (a sort by the next time moves the rows
  each few minutes).

      iex> team = Workflow.Team.example()
      iex> [first, second] = TalesForge.Board.Schedule.rows(team, ~U[2026-10-16 07:10:00Z], %{})
      iex> {first.id, first.owner, first.code?, first.next_at, first.last}
      {"sweep", "Code", true, ~U[2026-10-16 07:15:00Z], nil}
      iex> {second.id, second.owner, second.code?}
      {"check", "Quill", false}
  """
  @spec rows(Workflow.Team.t(), DateTime.t(), %{String.t() => ScheduledRun.t()}) :: [row()]
  def rows(%Workflow.Team{} = team, %DateTime{} = now, last_runs) do
    for job <- team.jobs do
      at = Workflow.Team.next_at(job, now)

      %{
        id: job.id,
        name: job.name,
        owner: owner_name(team, job.owner),
        code?: Workflow.Team.code_job?(job),
        next_at: at,
        last: Map.get(last_runs, job.id)
      }
    end
  end

  @doc """
  The display name of a job owner: "Code" for a code job, else the name of
  the bot or the founder.

      iex> team = Workflow.Team.example()
      iex> Enum.map(~w(code quill orjan), &TalesForge.Board.Schedule.owner_name(team, &1))
      ["Code", "Quill", "Örjan"]
  """
  @spec owner_name(Workflow.Team.t(), String.t()) :: String.t()
  def owner_name(_team, "code"), do: "Code"

  def owner_name(%Workflow.Team{} = team, owner) do
    case Workflow.Team.bot_id(team, owner) do
      nil -> Enum.find_value(team.founders, owner, &(&1.handle == owner && &1.name))
      id -> Workflow.Team.bot_name(team, id)
    end
  end
end
