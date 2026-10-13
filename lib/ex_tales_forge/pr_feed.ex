defmodule TalesForge.PrFeed do
  @moduledoc """
  The live pull-request feed on the founders' page (`/team`): the latest pull
  requests of the game's repo, their CI status while open, where each merged
  one is deployed (playtest, production) and how many were merged today and
  this week.

  - `TalesForge.PrFeed.Poller` holds the feed. GitHub webhooks
    (`TalesForge.GitEvents`, topic `"github"`) update it event by event
    (`TalesForge.PrFeed.Live`). A full read of GitHub (with `If-None-Match`,
    so an unchanged answer costs no rate limit) builds it at boot and every
    30 min (`TalesForge.PrFeed.Reconcile`). Each new snapshot is stored
    (`snapshot/0`) and broadcast on PubSub (`subscribe/0`). Browsers never
    call GitHub.
  - The token is the Fly secret `GITHUB_FEED_TOKEN` (config `:pr_feed_token`):
    a fine-grained, read-only token for the repo. Unset or blank: nothing is
    fetched and the snapshot's status is `:not_configured`.
  - When GitHub can't be reached the status is `:unavailable`; the page says
    "Live feed unavailable" and renders the rest as usual.

  The snapshot also carries the repo's pace (`:pace`, `TalesForge.PrFeed.Pace`):
  how many pull requests there are, merged and open, per day, and the commits
  on main, counted from GitHub's full lists. It is nil until those lists have
  been read in full; the pages read it through `TalesForge.TeamPace.current/0`,
  never directly.

  Where a merged pull request is deployed comes from `TalesForge.PrFeed.Deploys`
  (its merge commit against the commit each app runs,
  `TalesForge.PrFeed.Versions`).
  """

  alias TalesForge.PrFeed.Deploys
  alias TalesForge.PrFeed.Pace

  @topic "pr_feed"
  @table TalesForge.PrFeed.Poller
  @zone "Europe/Stockholm"
  @shown 15
  @pace_ttl_ms 24 * 60 * 60 * 1000

  @typedoc "Where a pull request stands."
  @type state :: :open | :merged | :closed

  @typedoc "CI of an open pull request's head commit (the CI workflow); nil when no run was found."
  @type ci :: :passed | :failed | :running | :cancelled | nil

  @typedoc "One pull request, as parsed by `TalesForge.PrFeed.Parse.pulls/1`."
  @type pr :: %{
          number: pos_integer(),
          title: String.t(),
          author: String.t() | nil,
          url: String.t() | nil,
          state: state(),
          draft: boolean(),
          head_sha: String.t() | nil,
          merge_sha: String.t() | nil,
          created_at: DateTime.t() | nil,
          merged_at: DateTime.t() | nil,
          closed_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @typedoc "A pull request as shown: `pr/0` plus the time it is listed by, CI and deployments."
  @type item :: %{
          number: pos_integer(),
          title: String.t(),
          author: String.t() | nil,
          url: String.t() | nil,
          state: state(),
          draft: boolean(),
          at: DateTime.t() | nil,
          opened_at: DateTime.t() | nil,
          merged_at: DateTime.t() | nil,
          ci: ci(),
          deployed: %{playtest: Deploys.status(), production: Deploys.status()}
        }

  @typedoc "Why there is no feed."
  @type status :: :ok | :loading | :not_configured | :unavailable

  @typedoc "What the page shows."
  @type snapshot :: %{
          status: status(),
          items: [item()],
          merged_today: non_neg_integer(),
          merged_week: non_neg_integer(),
          fetched_at: DateTime.t() | nil,
          pace: Pace.t() | nil
        }

  @typedoc "Everything `build/2` needs, as fetched and parsed by the poller."
  @type inputs :: %{
          required(:pulls) => [pr()],
          optional(:ci) => %{optional(String.t()) => ci()} | nil,
          optional(:main) => [String.t()] | nil,
          optional(:commits) => [Pace.commit()] | nil,
          optional(:running) => %{
            optional(:playtest) => String.t() | nil,
            optional(:production) => String.t() | nil
          }
        }

  @doc "How many pull requests the feed shows."
  @spec shown() :: pos_integer()
  def shown, do: @shown

  @doc "The PubSub topic the poller broadcasts `{:pr_feed, snapshot}` on."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Subscribes the caller to `{:pr_feed, snapshot}` messages."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(TalesForge.PubSub, @topic)

  @doc "The repo the feed follows, `owner/name` (config `TalesForge.PrFeed`, `:repo`)."
  @spec repo() :: String.t()
  def repo, do: config(:repo, Workflow.Team.repo(Workflow.Team.Source.team()))

  @doc "The GitHub token (`GITHUB_FEED_TOKEN`), or nil when unset or blank."
  @spec token() :: String.t() | nil
  def token do
    case Application.get_env(:ex_tales_forge, :pr_feed_token) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: nil, else: String.trim(value)

      _ ->
        nil
    end
  end

  @doc "True when a token is set, so the poller asks GitHub."
  @spec configured?() :: boolean()
  def configured?, do: token() != nil

  @doc "A config value of `config :ex_tales_forge, TalesForge.PrFeed`."
  @spec config(atom(), term()) :: term()
  def config(key, default) do
    :ex_tales_forge |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
  end

  @doc """
  The latest snapshot. Before the first poll (or when the poller isn't
  running) it is empty, with status `:loading` when a token is set and
  `:not_configured` otherwise.
  """
  @spec snapshot() :: snapshot()
  def snapshot do
    case :ets.lookup(@table, :snapshot) do
      [{:snapshot, snapshot}] -> snapshot
      [] -> empty(initial_status())
    end
  rescue
    ArgumentError -> empty(initial_status())
  end

  @doc "Stores `snapshot` as the latest and broadcasts it to subscribers."
  @spec publish(snapshot()) :: :ok
  def publish(snapshot) do
    try do
      :ets.insert(@table, {:snapshot, snapshot})
      remember_pace(snapshot)
    rescue
      ArgumentError -> :ok
    end

    Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, {:pr_feed, snapshot})
  end

  # The last full count, kept apart from the snapshot: a poll that can't read
  # every page (a timeout, a rate limit, GitHub down) replaces the snapshot
  # but must not wipe the live numbers.
  defp remember_pace(%{pace: %{prs_total: _} = pace}),
    do: :ets.insert(@table, {:last_pace, pace})

  defp remember_pace(_snapshot), do: true

  @doc """
  The pace of the latest snapshot, or else the last full count (`:pace`)
  this machine read from GitHub, while it is younger than `:pace_ttl_ms`
  (config `TalesForge.PrFeed`, default 24 h, measured from its `fetched_at`).
  nil only when there is none: a cold start before the first full poll.

  One poll that can't read every page (a timeout, a rate limit, GitHub down)
  thus doesn't flip the pages to the bundled `data.json`; the poller keeps
  refreshing the count in each reconcile.
  """
  @spec pace(DateTime.t()) :: Pace.t() | nil
  def pace(now \\ DateTime.utc_now()) do
    case snapshot() do
      %{pace: %{prs_total: _} = pace} -> pace
      _no_full_count -> last_pace(now)
    end
  end

  defp last_pace(now) do
    case :ets.lookup(@table, :last_pace) do
      [{:last_pace, %{fetched_at: %DateTime{} = at} = pace}] ->
        if DateTime.diff(now, at, :millisecond) <= config(:pace_ttl_ms, @pace_ttl_ms),
          do: pace

      _none ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "A snapshot without pull requests, with `status`."
  @spec empty(status(), DateTime.t() | nil) :: snapshot()
  def empty(status, fetched_at \\ nil) do
    %{
      status: status,
      items: [],
      merged_today: 0,
      merged_week: 0,
      fetched_at: fetched_at,
      pace: nil
    }
  end

  defp initial_status, do: if(configured?(), do: :loading, else: :not_configured)

  @doc """
  Builds the snapshot from parsed pull requests, CI by head commit, the
  commits of main (newest first) and the commit each app runs.

  Pull requests are listed by their latest event (merged, closed or opened),
  newest first, at most #{@shown}. The counters count every given pull request
  merged since midnight and since Monday 00:00, Europe/Stockholm time.

  `:pace` is counted (`TalesForge.PrFeed.Pace.build/3`) only when `inputs`
  has `:commits`, which the poller gives only when both the pull requests and
  the commits of main were read in full; otherwise it is nil.

      iex> pr = %{number: 7, title: "Add the inn", author: "bram", url: nil, state: :merged,
      ...>   draft: false, head_sha: "h7", merge_sha: "m7", created_at: ~U[2026-10-08 08:00:00Z],
      ...>   merged_at: ~U[2026-10-09 09:00:00Z], closed_at: ~U[2026-10-09 09:00:00Z],
      ...>   updated_at: ~U[2026-10-09 09:00:00Z]}
      iex> snap = TalesForge.PrFeed.build(%{pulls: [pr], main: ["m8", "m7", "m6"],
      ...>   running: %{playtest: "m8", production: "m6"}}, ~U[2026-10-09 12:00:00Z])
      iex> {snap.merged_today, snap.merged_week}
      {1, 1}
      iex> [item] = snap.items
      iex> item.deployed
      %{playtest: :deployed, production: :pending}
      iex> snap.pace
      nil
  """
  @spec build(inputs(), DateTime.t()) :: snapshot()
  def build(%{pulls: pulls} = inputs, %DateTime{} = now) do
    ci = Map.get(inputs, :ci) || %{}
    main = if is_list(inputs[:main]), do: Deploys.index(inputs[:main])
    running = Map.get(inputs, :running) || %{}
    {today, week} = day_and_week_start(now)

    items =
      pulls
      |> Enum.sort_by(&event_unix/1, :desc)
      |> Enum.take(@shown)
      |> Enum.map(&item(&1, ci, main, running))

    merged = Enum.filter(pulls, &(&1.state == :merged and &1.merged_at != nil))

    %{
      status: :ok,
      items: items,
      merged_today: Enum.count(merged, &(DateTime.compare(&1.merged_at, today) != :lt)),
      merged_week: Enum.count(merged, &(DateTime.compare(&1.merged_at, week) != :lt)),
      fetched_at: now,
      pace: pace(pulls, Map.get(inputs, :commits), now)
    }
  end

  defp pace(pulls, commits, now) when is_list(commits), do: Pace.build(pulls, commits, now)
  defp pace(_pulls, _commits, _now), do: nil

  @doc """
  One shown item from a pull request, CI by head commit, main (a list or a
  `TalesForge.PrFeed.Deploys.index/1`) and the commit each app runs.
  """
  @spec item(pr(), map(), [String.t()] | Deploys.index() | nil, map()) :: item()
  def item(pr, ci, main, running) do
    %{
      number: pr.number,
      title: pr.title,
      author: pr.author,
      url: pr.url,
      state: pr.state,
      draft: pr.draft,
      at: event_at(pr),
      opened_at: pr.created_at,
      merged_at: pr.merged_at,
      ci: if(pr.state == :open, do: Map.get(ci, pr.head_sha)),
      deployed: %{
        playtest: deploy_status(pr, main, running[:playtest]),
        production: deploy_status(pr, main, running[:production])
      }
    }
  end

  defp deploy_status(%{state: :merged, merge_sha: sha}, main, running),
    do: Deploys.status(sha, main, running)

  defp deploy_status(_pr, _main, _running), do: :not_merged

  defp event_at(%{state: :merged, merged_at: at}) when not is_nil(at), do: at
  defp event_at(%{state: :closed, closed_at: at}) when not is_nil(at), do: at
  defp event_at(pr), do: pr.created_at || pr.updated_at

  @doc "The Unix time a pull request is listed by (0 when unknown)."
  @spec event_unix(pr() | item()) :: integer()
  def event_unix(%{at: at}), do: if(at, do: DateTime.to_unix(at), else: 0)

  def event_unix(pr) do
    case event_at(pr) do
      nil -> 0
      at -> DateTime.to_unix(at)
    end
  end

  @doc """
  Midnight today and Monday 00:00 of this week in Europe/Stockholm, as UTC.

      iex> TalesForge.PrFeed.day_and_week_start(~U[2026-10-09 12:00:00Z])
      {~U[2026-10-08 22:00:00Z], ~U[2026-10-04 22:00:00Z]}
  """
  @spec day_and_week_start(DateTime.t()) :: {DateTime.t(), DateTime.t()}
  def day_and_week_start(%DateTime{} = now) do
    date = now |> DateTime.shift_zone!(@zone, TimeZoneInfo.TimeZoneDatabase) |> DateTime.to_date()
    monday = Date.add(date, 1 - Date.day_of_week(date))
    {midnight_utc(date), midnight_utc(monday)}
  end

  defp midnight_utc(date) do
    date
    |> DateTime.new!(~T[00:00:00], @zone, TimeZoneInfo.TimeZoneDatabase)
    |> DateTime.shift_zone!("Etc/UTC", TimeZoneInfo.TimeZoneDatabase)
  end
end
