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
  - A pull request merged: wake Bobby (`pr.merged`) for each card in
    Building or Founder check with that PR.
  - The `CI` workflow failed on a commit: wake Bobby (`ci.failed`) for each
    card whose waiting PR has that head commit.
  - `Deploy to production` passed: queue `TalesForge.Board.Workers.AutoDone`,
    so cards whose PR is now on prod move to Done.

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
  alias TalesForge.Repo

  @typedoc "One thing the board does for an event."
  @type step ::
          {:backfill, pos_integer()}
          | {:wake_pr, :pr_merged, pos_integer()}
          | {:wake_sha, :ci_failed, String.t()}
          | :auto_done

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
      iex> GitHubEvents.plan(%GitEvent{type: :workflow_run, repo: "o/r", action: "completed",
      ...>   workflow: "Deploy to production", ci: :passed})
      [:auto_done]
      iex> GitHubEvents.plan(%GitEvent{type: :push, repo: "o/r"})
      []
  """
  @spec plan(GitEvent.t()) :: [step()]
  def plan(%GitEvent{type: :pull_request, action: action, pr: n})
      when action in ["opened", "reopened", "ready_for_review"] and is_integer(n),
      do: [{:backfill, n}]

  def plan(%GitEvent{type: :pull_request, action: "closed", pr: n, pull: %{state: :merged}})
      when is_integer(n),
      do: [{:wake_pr, :pr_merged, n}]

  def plan(%GitEvent{type: :workflow_run, action: "completed", workflow: "CI", ci: :failed} = e)
      when is_binary(e.sha),
      do: [{:wake_sha, :ci_failed, e.sha}]

  def plan(%GitEvent{
        type: :workflow_run,
        action: "completed",
        workflow: "Deploy to production",
        ci: :passed
      }),
      do: [:auto_done]

  def plan(%GitEvent{}), do: []

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

  defp wake(%Idea{} = idea, event) do
    pr = %{"number" => idea.pr_number, "url" => idea.pr_url, "head_sha" => idea.pr_head_sha}
    extra = %{actor: "bot:board", from: idea.column, to: idea.column, pr: pr}
    {:ok, _job} = :bobby |> Notify.job(event, idea, extra) |> Oban.insert()
    :ok
  end
end
