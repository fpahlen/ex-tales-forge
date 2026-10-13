defmodule TalesForge.PrFeed.Live do
  @moduledoc """
  The live PR feed as a model that each GitHub event updates in place
  (`TalesForge.GitEvents.GitEvent`). Pure: `TalesForge.PrFeed.Poller` holds
  the model, applies each event and publishes the snapshot.

  `new/2` builds the model once from a full read of GitHub (at boot and in
  each reconcile, `TalesForge.PrFeed.Reconcile`). Then each event changes
  only what it touches:

  - `pull_request`: that pull request: its item, the merged counters and the
    pace counts.
  - `push` to main: main's new commits go in front of the sha lookup
    (`TalesForge.PrFeed.Deploys.prepend/2`), then the deploy status of the
    shown merged items and the commit pace.
  - `workflow_run` of the `CI` workflow: the CI badge of the open items with
    that head commit.
  - `workflow_run` of a deploy workflow, completed: `apply/3` gives
    `{:refresh_running, model}`, so the poller reads the commit each app runs
    again (`put_running/2`).
  - `check_suite` and other workflows: no change (the CI workflow runs give
    the badges).

  The merged-today and this-week counters start again in each reconcile.
  """

  alias TalesForge.GitEvents.GitEvent
  alias TalesForge.PrFeed
  alias TalesForge.PrFeed.Deploys
  alias TalesForge.PrFeed.Pace

  @ci_workflow "CI"
  @deploy_workflows ["Deploy to playtest", "Deploy to production"]

  @typedoc "The feed's state between events."
  @type t :: %{
          pulls: %{optional(pos_integer()) => PrFeed.pr()},
          ci: %{optional(String.t()) => PrFeed.ci()},
          index: Deploys.index() | nil,
          running: map(),
          snapshot: PrFeed.snapshot()
        }

  @doc "The model from a full read (`t:TalesForge.PrFeed.inputs/0`), at `now`."
  @spec new(PrFeed.inputs(), DateTime.t()) :: t()
  def new(%{pulls: pulls} = inputs, %DateTime{} = now) do
    %{
      pulls: Map.new(pulls, &{&1.number, &1}),
      ci: Map.get(inputs, :ci) || %{},
      index: if(is_list(inputs[:main]), do: Deploys.index(inputs[:main])),
      running: Map.get(inputs, :running) || %{},
      snapshot: PrFeed.build(inputs, now)
    }
  end

  @doc """
  Applies one event at `now`. `{:changed, model}` when the snapshot
  changed, `{:refresh_running, model}` when the running commits need a new
  read, `:unchanged` otherwise.
  """
  @spec apply(t(), GitEvent.t(), DateTime.t()) ::
          {:changed, t()} | {:refresh_running, t()} | :unchanged
  def apply(model, %GitEvent{type: :pull_request, pull: %{number: _} = pr}, now),
    do: {:changed, put_pr(model, pr, now)}

  def apply(model, %GitEvent{type: :push, branch: "main", commits: [_ | _] = commits}, now)
      when model.index != nil,
      do: {:changed, add_commits(model, commits, now)}

  def apply(model, %GitEvent{type: :workflow_run, workflow: @ci_workflow, sha: sha, ci: ci}, now)
      when is_binary(sha),
      do: {:changed, put_ci(model, sha, ci, now)}

  def apply(model, %GitEvent{type: :workflow_run, workflow: w, action: "completed"}, _now)
      when w in @deploy_workflows,
      do: {:refresh_running, model}

  def apply(_model, %GitEvent{}, _now), do: :unchanged

  @doc "Sets the commit each app runs and updates the deploy status of the shown items."
  @spec put_running(t(), map(), DateTime.t()) :: t()
  def put_running(model, running, now) do
    model = %{model | running: running}
    update_items(model, now, fn item -> item.state == :merged end)
  end

  defp put_pr(model, pr, now) do
    old = model.pulls[pr.number]
    model = %{model | pulls: Map.put(model.pulls, pr.number, pr)}
    snap = model.snapshot
    item = PrFeed.item(pr, model.ci, model.index, model.running)
    {today, week} = PrFeed.day_and_week_start(now)

    items =
      [item | Enum.reject(snap.items, &(&1.number == pr.number))]
      |> Enum.sort_by(&PrFeed.event_unix/1, :desc)
      |> Enum.take(PrFeed.shown())

    new_snap = %{
      snap
      | items: items,
        merged_today: snap.merged_today + merged_since(pr, today) - merged_since(old, today),
        merged_week: snap.merged_week + merged_since(pr, week) - merged_since(old, week),
        fetched_at: now,
        pace: snap.pace && Pace.put_pr(snap.pace, old, pr, now)
    }

    %{model | snapshot: new_snap}
  end

  defp merged_since(%{state: :merged, merged_at: %DateTime{} = at}, since),
    do: if(DateTime.compare(at, since) != :lt, do: 1, else: 0)

  defp merged_since(_pr, _since), do: 0

  defp add_commits(model, commits, now) do
    model = %{model | index: Deploys.prepend(model.index, Enum.map(commits, & &1.sha))}
    snap = model.snapshot
    pace = snap.pace && Pace.add_commits(snap.pace, commits, now)

    update_items(%{model | snapshot: %{snap | pace: pace}}, now, fn item ->
      item.state == :merged
    end)
  end

  defp put_ci(model, sha, ci, now) do
    model = %{model | ci: Map.put(model.ci, sha, ci)}

    update_items(model, now, fn item ->
      item.state == :open and model.pulls[item.number][:head_sha] == sha
    end)
  end

  # Builds again only the shown items that `touched?` picks.
  defp update_items(model, now, touched?) do
    items =
      Enum.map(model.snapshot.items, fn item ->
        case {touched?.(item), model.pulls[item.number]} do
          {true, %{} = pr} -> PrFeed.item(pr, model.ci, model.index, model.running)
          _ -> item
        end
      end)

    %{model | snapshot: %{model.snapshot | items: items, fetched_at: now}}
  end
end
