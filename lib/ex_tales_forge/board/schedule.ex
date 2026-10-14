defmodule TalesForge.Board.Schedule do
  @moduledoc """
  The runs of the scheduled jobs and the rows of the Upcoming panel on the
  team page (`TalesForgeWeb.TeamUpcoming`).

  The jobs are in the team config (`Workflow.Team` `jobs`, cron lines in UTC).
  The Workflow Oban instance runs them (`TalesForge.Workflow.Jobs.config/0`).
  A code job calls `track/2` around its work: the run gets a row in
  `scheduled_runs` (`TalesForge.Board.ScheduledRun`), `"open"` at the start,
  then `"ok"` or `"failed"`. A code job starts no bot.

  All times are in UTC. The browser shows them in the viewer's local time
  zone. Changes are broadcast on `topic/0` as `{:schedule, :changed}`.
  """

  import Ecto.Query

  alias TalesForge.Board.ScheduledRun
  alias TalesForge.Workflow.Repo

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
