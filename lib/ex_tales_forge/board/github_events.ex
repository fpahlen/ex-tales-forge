defmodule TalesForge.Board.GitHubEvents do
  @moduledoc """
  The board follows GitHub webhooks (`TalesForge.GitEvents`, topic
  `"github"`).

  A pure plan (`plan/1`) says what one event means for the board. This
  process does it, for the cards with that PR or head commit only:

  - A pull request opened, reopened or ready for review: queue
    `TalesForge.Board.Workers.PrBackfill`. It marks the PR of each Building
    card that links a PR with no PR waiting yet, so the card gets its
    Approve button.
  - A pull request merged: wake the builder bot (`pr.merged`) for each card in
    Building or Founder check with that PR.
  - The `CI` workflow failed on a commit: wake the builder (`ci.failed`) for each
    card whose waiting PR has that head commit.
  - `Deploy to production` passed: queue `TalesForge.Board.Workers.AutoDone`,
    so cards whose PR is now on prod move to Done.
  - A workflow run on main ended: give it to the inbox (`Workflow.Inbox`,
    rules `ci_failed` and `deploy_failed`) as an event with no tag. A failed
    run makes items; a passed run of the same workflow closes them.

  Production only (`TalesForge.AppRole`), as the board, or with
  `:board_github_events_anywhere`.
  """

  use GenServer

  import Ecto.Query

  alias TalesForge.AppRole
  alias TalesForge.Board.Idea
  alias TalesForge.Board.Workers.{AutoDone, Notify, PrBackfill}
  alias TalesForge.GitEvents
  alias TalesForge.GitEvents.GitEvent
  alias TalesForge.Workflow.Repo

  @typedoc "One thing the board does for an event."
  @type step ::
          {:backfill, pos_integer()}
          | {:wake_pr, :pr_merged, pos_integer()}
          | {:wake_sha, :ci_failed, String.t()}
          | :auto_done
          | {:inbox, Workflow.Inbox.Event.t()}

  @doc "Starts the subscriber (named `#{inspect(__MODULE__)}`)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    GitEvents.subscribe()
    {:ok, nil}
  end

  @impl true
  def handle_info({:git_event, %GitEvent{} = event}, state) do
    if enabled?(), do: event |> plan() |> Enum.each(&run/1)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp enabled? do
    AppRole.role() == :production or
      Application.get_env(:ex_tales_forge, :board_github_events_anywhere, false)
  end

  @doc """
  What one event means for the board.

      iex> alias TalesForge.GitEvents.GitEvent
      iex> alias TalesForge.Board.GitHubEvents
      iex> GitHubEvents.plan(%GitEvent{type: :pull_request, repo: "o/r", action: "opened", pr: 7})
      [{:backfill, 7}]
      iex> GitHubEvents.plan(%GitEvent{type: :pull_request, repo: "o/r", action: "closed", pr: 7,
      ...>   pull: %{state: :merged}})
      [{:wake_pr, :pr_merged, 7}]
      iex> GitHubEvents.plan(%GitEvent{type: :workflow_run, repo: "o/r", action: "completed",
      ...>   workflow: "CI", ci: :failed, sha: "abc"})
      [{:wake_sha, :ci_failed, "abc"}]
      iex> [{:inbox, event}] = GitHubEvents.plan(%GitEvent{type: :workflow_run, repo: "o/r",
      ...>   action: "completed", workflow: "CI", ci: :failed, sha: "abc", branch: "main"}) |> Enum.drop(1)
      iex> {event.type, event.workflow, event.url}
      {:workflow_failed, "CI", "https://github.com/o/r/commit/abc"}
      iex> GitHubEvents.plan(%GitEvent{type: :workflow_run, repo: "o/r", action: "completed",
      ...>   workflow: "Deploy to production", ci: :passed})
      [:auto_done]
      iex> GitHubEvents.plan(%GitEvent{type: :workflow_run, repo: "o/r", action: "completed",
      ...>   workflow: "Deploy to production", ci: :passed, sha: "abc", branch: "main"}) |> Enum.drop(1)
      ...> |> Enum.map(fn {:inbox, e} -> e.type end)
      [:workflow_passed]
      iex> GitHubEvents.plan(%GitEvent{type: :push, repo: "o/r"})
      []
  """
  @spec plan(GitEvent.t()) :: [step()]
  def plan(%GitEvent{} = event), do: board_plan(event) ++ inbox_plan(event)

  defp board_plan(%GitEvent{type: :pull_request, action: action, pr: n})
       when action in ["opened", "reopened", "ready_for_review"] and is_integer(n),
       do: [{:backfill, n}]

  defp board_plan(%GitEvent{
         type: :pull_request,
         action: "closed",
         pr: n,
         pull: %{state: :merged}
       })
       when is_integer(n),
       do: [{:wake_pr, :pr_merged, n}]

  defp board_plan(
         %GitEvent{type: :workflow_run, action: "completed", workflow: "CI", ci: :failed} = e
       )
       when is_binary(e.sha),
       do: [{:wake_sha, :ci_failed, e.sha}]

  defp board_plan(%GitEvent{
         type: :workflow_run,
         action: "completed",
         workflow: "Deploy to production",
         ci: :passed
       }),
       do: [:auto_done]

  defp board_plan(%GitEvent{}), do: []

  # A run on main names no card and no person: the inbox gets it with no tag.
  defp inbox_plan(%GitEvent{type: :workflow_run, action: "completed", branch: "main", ci: ci} = e)
       when ci in [:failed, :passed] and is_binary(e.workflow) and is_binary(e.sha) do
    url = "https://github.com/#{e.repo}/commit/#{e.sha}"

    [
      {:inbox,
       %Workflow.Inbox.Event{
         type: if(ci == :failed, do: :workflow_failed, else: :workflow_passed),
         source_id: "run-#{e.workflow}-#{e.sha}",
         workflow: e.workflow,
         sha: e.sha,
         url: url,
         author: e.actor,
         body:
           "#{e.workflow} #{if ci == :failed, do: "failed", else: "passed"} on main at #{String.slice(e.sha, 0, 7)}."
       }}
    ]
  end

  defp inbox_plan(%GitEvent{}), do: []

  # The job reads the Building cards with a PR link and no PR waiting.
  defp run({:backfill, _number}), do: PrBackfill.schedule()

  defp run({:wake_pr, event, n}) do
    from(i in Idea, where: i.pr_number == ^n and i.column in ["building", "check"])
    |> Repo.all()
    |> Enum.each(&wake(&1, event))
  end

  defp run({:wake_sha, event, sha}) do
    from(i in Idea, where: i.pr_head_sha == ^sha and i.column in ["building", "check"])
    |> Repo.all()
    |> Enum.each(&wake(&1, event))
  end

  defp run(:auto_done), do: AutoDone.schedule()

  defp run({:inbox, event}) do
    {:ok, _count} = Workflow.Inbox.Store.record(Workflow.Team.Source.team(), event)
    :ok
  end

  defp wake(%Idea{} = idea, event) do
    pr = %{"number" => idea.pr_number, "url" => idea.pr_url, "head_sha" => idea.pr_head_sha}
    extra = %{actor: "bot:board", from: idea.column, to: idea.column, pr: pr}
    builder = Workflow.Team.bot(Workflow.Team.Source.team(), :builder)
    {:ok, _job} = builder |> Notify.job(event, idea, extra) |> TalesForge.Workflow.Jobs.insert()
    :ok
  end
end
