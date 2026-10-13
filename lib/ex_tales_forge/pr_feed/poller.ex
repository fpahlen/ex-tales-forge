defmodule TalesForge.PrFeed.Poller do
  @moduledoc """
  Holds the live PR feed (`TalesForge.PrFeed`) and publishes each new
  snapshot: stored in a public ETS table it owns (read by
  `TalesForge.PrFeed.snapshot/0` without a call to this process) and
  broadcast on PubSub.

  - GitHub webhooks drive the feed: the process subscribes to `"github"`
    (`TalesForge.GitEvents`) and applies each event of the feed's repo to
    its model (`TalesForge.PrFeed.Live.apply/3`). No full rebuild per event.
  - A full read of GitHub (`poll/2`) builds the model: once right after
    start, and on each reconcile signal (`TalesForge.PrFeed.Reconcile`,
    every 30 min), the backup for missed webhooks. `:poll` false (tests)
    starts the table but reads nothing.
  - Per resource (and per page) it keeps the last `ETag` and the parsed
    answer, so an unchanged answer (304) is reused and costs no rate limit.
  - The pull requests and main's commits are read in full, page by page
    (at most `:max_pages` pages each, config `TalesForge.PrFeed`, default
    30), and counted into the snapshot's `:pace` (`TalesForge.PrFeed.Pace`).
    If either list is cut short (a page fails, or there are more pages), the
    snapshot gets no `:pace` and the pages fall back to `data.json`.
  - No token: nothing is fetched, the snapshot is `:not_configured`.
  - The pull requests can't be fetched: `:unavailable`. CI or main's commits
    missing only blank out the CI badges or the deploy status.
  - After each full read, `TalesForge.PrFeed.Extras.refresh/2` (at most every
    10 min): the test counts of main's latest CI run and the decision log.
  - A crash restarts it under the application supervisor with an empty feed.
  """

  use GenServer

  require Logger

  alias TalesForge.GitEvents
  alias TalesForge.PrFeed
  alias TalesForge.PrFeed.Extras
  alias TalesForge.PrFeed.GitHub
  alias TalesForge.PrFeed.Live
  alias TalesForge.PrFeed.Parse
  alias TalesForge.PrFeed.Reconcile
  alias TalesForge.PrFeed.Versions

  @default_max_pages 30

  @typedoc "The last ETag and parsed answer per resource, or per page of a paged one."
  @type cache :: %{
          optional(GitHub.resource() | {GitHub.resource(), pos_integer()}) =>
            {String.t() | nil, term()}
        }

  @doc "Starts the poller (named `#{inspect(__MODULE__)}`)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @typedoc "The ETag cache and the feed model (nil before the first full read)."
  @type state :: %{cache: cache(), model: Live.t() | nil}

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    :ets.new(__MODULE__, [:named_table, :public, :set, read_concurrency: true])
    GitEvents.subscribe()
    Phoenix.PubSub.subscribe(TalesForge.PubSub, Reconcile.topic())
    if PrFeed.config(:poll, true), do: send(self(), :reconcile)
    {:ok, %{cache: %{}, model: nil}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    now = DateTime.utc_now()
    {snapshot, cache, inputs} = read(state.cache, now)
    # The presentation's other GitHub numbers (tests, decisions): at most every
    # 10 min, stored before the snapshot goes out so subscribers see both.
    if PrFeed.configured?() do
      Extras.current() |> Extras.refresh(now) |> Extras.store()
    end

    PrFeed.publish(snapshot)
    {:noreply, %{cache: cache, model: inputs && Live.new(inputs, now)}}
  end

  def handle_info({:git_event, event}, state) do
    {:noreply, handle_event(state, event, DateTime.utc_now())}
  end

  @doc """
  Applies one GitHub event to the state and publishes the new snapshot when
  it changed. Events of another repo, and events before the first full
  read, change nothing.
  """
  @spec handle_event(state(), GitEvents.GitEvent.t(), DateTime.t()) :: state()
  def handle_event(%{model: nil} = state, _event, _now), do: state

  def handle_event(state, event, now) do
    if event.repo == PrFeed.repo() do
      case Live.apply(state.model, event, now) do
        {:changed, model} ->
          PrFeed.publish(model.snapshot)
          %{state | model: model}

        {:refresh_running, model} ->
          model = Live.put_running(model, Versions.running(), now)
          PrFeed.publish(model.snapshot)
          %{state | model: model}

        :unchanged ->
          state
      end
    else
      state
    end
  end

  @doc """
  One poll: fetches what changed (sending the cached ETags), builds the
  snapshot at `now` and returns it with the updated cache. Doesn't publish.
  """
  @spec poll(cache(), DateTime.t()) :: {PrFeed.snapshot(), cache()}
  def poll(cache, %DateTime{} = now) do
    {snapshot, cache, _inputs} = read(cache, now)
    {snapshot, cache}
  end

  # The snapshot, the cache and the inputs it was built from (nil when there
  # are no pull requests to build from).
  defp read(cache, now) do
    if PrFeed.configured?() do
      fetch_all(cache, now)
    else
      {PrFeed.empty(:not_configured, now), %{}, nil}
    end
  end

  defp fetch_all(cache, now) do
    case fetch_pages(:pulls, cache, &Parse.pulls/1) do
      {:ok, pulls, pulls_complete?, cache} ->
        {ci, cache} = optional(:ci, cache, &Parse.ci_runs/1)
        {commits, commits_complete?, cache} = optional_pages(:main, cache, &Parse.commits/1)

        inputs = %{
          pulls: pulls,
          ci: ci,
          main: commits && Enum.map(commits, & &1.sha),
          commits: if(pulls_complete? and commits_complete?, do: commits),
          running: Versions.running()
        }

        {PrFeed.build(inputs, now), cache, inputs}

      {:error, reason} ->
        Logger.warning("PR feed: GitHub pull requests unavailable (#{inspect(reason)})")
        {PrFeed.empty(:unavailable, now), cache, nil}
    end
  end

  defp optional_pages(resource, cache, parse) do
    case fetch_pages(resource, cache, parse) do
      {:ok, items, complete?, cache} -> {items, complete?, cache}
      {:error, _reason} -> {nil, false, drop_pages(cache, resource)}
    end
  end

  # Pages 1, 2, ... of a list until a page isn't full. `{:ok, items,
  # complete?, cache}` once page 1 is in; complete? is false when a later page
  # failed or `:max_pages` was reached with more to come.
  defp fetch_pages(resource, cache, parse) do
    case fetch({resource, 1}, cache, parse) do
      {:ok, items, cache} -> more_pages(resource, 1, items, items, cache, parse)
      {:error, reason} -> {:error, reason}
    end
  end

  defp more_pages(resource, page, last, acc, cache, parse) do
    cond do
      length(last) < GitHub.per_page() ->
        {:ok, acc, true, drop_pages(cache, resource, page + 1)}

      page >= PrFeed.config(:max_pages, @default_max_pages) ->
        {:ok, acc, false, cache}

      true ->
        case fetch({resource, page + 1}, cache, parse) do
          {:ok, items, cache} -> more_pages(resource, page + 1, items, acc ++ items, cache, parse)
          {:error, _reason} -> {:ok, acc, false, drop_pages(cache, resource, page + 1)}
        end
    end
  end

  # Forgets the cached pages of `resource` from page `from` on.
  defp drop_pages(cache, resource, from \\ 1) do
    Map.reject(cache, fn
      {{^resource, page}, _value} -> page >= from
      _other -> false
    end)
  end

  defp optional(resource, cache, parse) do
    case fetch(resource, cache, parse) do
      {:ok, value, cache} -> {value, cache}
      {:error, _reason} -> {nil, Map.delete(cache, resource)}
    end
  end

  defp fetch(key, cache, parse) do
    {etag, kept} = Map.get(cache, key, {nil, nil})
    {resource, page} = resource_page(key)

    case GitHub.fetch(resource, etag, page) do
      {:ok, body, new_etag} ->
        value = parse.(body)
        {:ok, value, Map.put(cache, key, {new_etag, value})}

      :not_modified when kept != nil ->
        {:ok, kept, cache}

      :not_modified ->
        {:error, :not_modified_without_copy}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resource_page({resource, page}), do: {resource, page}
  defp resource_page(resource), do: {resource, 1}
end
