defmodule TalesForge.Online do
  @moduledoc """
  Who is online right now, for "Online now" on `/team` (board card "Who's
  online right now", decision 2026-10-10).

  - **Founders** are tracked with Phoenix Presence (`TalesForge.Presence`)
    on the PubSub this app already runs. `TalesForgeWeb.LiveAuth` calls
    `track/2` when a signed-in LiveView connects, so every admin and team page
    counts, with the page name from `page_label/1`. Presence removes the entry
    when the page closes.
  - **Both apps, one list.** Production and playtest are separate Fly apps
    that do not share PubSub. Production reads playtest's founders from
    playtest's `GET /internal/online` (`TalesForgeWeb.OnlinePeerController`,
    shared `COSTS_PEER_TOKEN`), the same pull model as the costs page. The
    reader is `TalesForge.Online.Peer`, which keeps the last answer for
    `TalesForge.Online.Peer.ttl_ms/0`; an older answer counts as empty.
  - **Bots** do not keep a page open. The Workflow app (whyse-ab/workflow)
    shows them; this app shows the founders only.
  """

  alias TalesForge.AppRole
  alias TalesForge.Online.{Founders, Peer}
  alias TalesForge.Presence

  @topic "online"

  @typedoc "One founder on one app (`t:TalesForge.Online.Founders.t/0`)."
  @type founder :: Founders.t()

  # Module names as strings, so this shared module does not depend on the
  # admin LiveViews (`mix deploy.check_boundaries`).
  @pages %{
    "TalesForgeWeb.TeamLive" => "Team page",
    "TalesForgeWeb.TeamPresentationLive" => "Presentation",
    "TalesForgeWeb.HomeLive" => "Game",
    "TalesForgeWeb.CreateCharacterLive" => "Game",
    "TalesForgeWeb.PlayLive" => "Game",
    "TalesForgeWeb.AdminLive.DashboardLive" => "Admin",
    "TalesForgeWeb.AdminLive.SessionLive.Index" => "Sessions",
    "TalesForgeWeb.AdminLive.SessionLive.Show" => "Sessions",
    "TalesForgeWeb.AdminLive.CharacterLive.Index" => "Characters",
    "TalesForgeWeb.AdminLive.CharacterLive.Show" => "Characters",
    "TalesForgeWeb.AdminLive.TurnLive.Index" => "Turns",
    "TalesForgeWeb.AdminLive.CostsLive" => "Costs",
    "TalesForgeWeb.AdminLive.PlaytestLive.Index" => "Playtest runs",
    "TalesForgeWeb.AdminLive.PlaytestLive.Show" => "Playtest runs",
    "TalesForgeWeb.AdminLive.DecisionLive.Index" => "Decisions",
    "TalesForgeWeb.AdminLive.DecisionLive.Show" => "Decisions",
    "TalesForgeWeb.AdminLive.DocLive.Index" => "Docs",
    "TalesForgeWeb.AdminLive.SurveyLive.Show" => "Survey",
    "TalesForgeWeb.AdminLive.SurveyLive.Index" => "Surveys",
    "TalesForgeWeb.AdminLive.SurveyLive.Results" => "Survey results",
    "Phoenix.LiveDashboard.PageLive" => "Telemetry"
  }

  @doc """
  The page name shown for a LiveView module; "Admin" for a module not in the
  list.

      iex> TalesForge.Online.page_label(TalesForgeWeb.TeamLive)
      "Team page"
      iex> TalesForge.Online.page_label(SomeNewLive)
      "Admin"
  """
  @spec page_label(module()) :: String.t()
  def page_label(view) when is_atom(view),
    do: Map.get(@pages, view |> Atom.to_string() |> String.replace_prefix("Elixir.", ""), "Admin")

  def page_label(_view), do: "Admin"

  @doc "The Presence topic."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc """
  Subscribes the caller to changes: Presence diffs on this app
  (`%Phoenix.Socket.Broadcast{event: "presence_diff"}`) and `{:online, :changed}`
  when the other app's list changes.
  """
  @spec subscribe() :: :ok
  def subscribe do
    :ok = Phoenix.PubSub.subscribe(TalesForge.PubSub, @topic)
    Phoenix.PubSub.subscribe(TalesForge.PubSub, Founders.changed_topic())
  end

  @doc """
  Tracks the LiveView process of `socket` for the founder `email`, once it is
  connected. Nested LiveViews are not tracked (their parent page is).
  Never raises: Presence is a nice-to-have, never a reason to fail a mount.
  """
  @spec track(Phoenix.LiveView.Socket.t(), String.t(), String.t() | nil) :: :ok
  def track(socket, email, login \\ nil)

  def track(%Phoenix.LiveView.Socket{} = socket, email, login) when is_binary(email) do
    if Phoenix.LiveView.connected?(socket) and is_nil(socket.parent_pid) do
      meta = %{
        login: if(is_binary(login), do: String.downcase(login)),
        page: page_label(socket.view),
        app: Atom.to_string(AppRole.role()),
        since: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      _ = Presence.track(self(), @topic, String.downcase(email), meta)
    end

    :ok
  rescue
    _ -> :ok
  end

  def track(_socket, _email, _login), do: :ok

  @doc """
  The founders online on this app, one entry per founder and page (two tabs
  on the same page are one entry, with the newest time), as plain maps with
  string keys (the JSON shape of `/internal/online`).
  """
  @spec local() :: [map()]
  def local do
    @topic
    |> Presence.list()
    |> Enum.flat_map(fn {email, %{metas: metas}} ->
      metas
      |> Enum.sort_by(&(&1[:since] || ""), :desc)
      |> Enum.uniq_by(& &1[:page])
      |> Enum.map(fn meta ->
        %{
          "email" => email,
          "login" => meta[:login],
          "page" => meta[:page],
          "app" => meta[:app],
          "since" => meta[:since]
        }
      end)
    end)
  end

  @doc """
  Every founder online on both apps: this app's Presence plus the other app's
  last answer while it is fresh (`TalesForge.Online.Peer`): one entry per
  founder, app and page. `people/1` groups them by person.
  """
  @spec founders() :: [founder()]
  def founders do
    (Founders.normalize(local()) ++ Peer.founders())
    |> Enum.uniq_by(&{&1.email, &1.app, &1.page})
    |> Enum.sort_by(&{&1.email, &1.app, &1.page})
  end

  @typedoc "One founder with every place they have a page open."
  @type person :: %{
          key: String.t(),
          email: String.t(),
          login: String.t() | nil,
          locations: [String.t()],
          since: DateTime.t()
        }

  @doc """
  Groups `founders/0` entries by person (the GitHub login, else the email):
  one entry per founder with each place once ("Docs on playtest"), however
  many tabs or apps. Sorted by key.

      iex> t = ~U[2026-10-10 12:00:00Z]
      iex> TalesForge.Online.people([
      ...>   %{email: "f@x.se", login: "fpahlen", page: "Docs", app: "production", since: t},
      ...>   %{email: "f@x.se", login: "fpahlen", page: "Playtest runs", app: "playtest", since: t},
      ...>   %{email: "f@x.se", login: "fpahlen", page: "Docs", app: "production", since: t},
      ...>   %{email: "m@x.se", login: nil, page: "Admin", app: "production", since: t}])
      [%{key: "fpahlen", email: "f@x.se", login: "fpahlen", since: ~U[2026-10-10 12:00:00Z],
         locations: ["Docs on production", "Playtest runs on playtest"]},
       %{key: "m@x.se", email: "m@x.se", login: nil, since: ~U[2026-10-10 12:00:00Z],
         locations: ["Admin on production"]}]
  """
  @spec people([founder()]) :: [person()]
  def people(founders \\ founders()) do
    founders
    |> Enum.group_by(&(Map.get(&1, :login) || &1.email))
    |> Enum.map(fn {key, entries} ->
      first = Enum.find(entries, hd(entries), &Map.get(&1, :login))

      %{
        key: key,
        email: first.email,
        login: Map.get(first, :login),
        locations: entries |> Enum.map(&"#{&1.page} on #{&1.app}") |> Enum.uniq() |> Enum.sort(),
        since: entries |> Enum.map(& &1.since) |> Enum.max(DateTime)
      }
    end)
    |> Enum.sort_by(& &1.key)
  end

  @doc """
  Everyone online for the header counter (`TalesForgeWeb.OnlineHeaderLive`):
  `%{founders: [person + name + handle], bots: [...]}` from the module in config
  `:online_snapshot`, when one is set. Without that module (the default since
  Workflow moved to its own app): the founders only, and no bots.
  """
  @spec snapshot(DateTime.t()) :: %{founders: [map()], bots: [map()]}
  def snapshot(now \\ DateTime.utc_now()) do
    case Application.get_env(:ex_tales_forge, :online_snapshot) do
      mod when is_atom(mod) and not is_nil(mod) ->
        if Code.ensure_loaded?(mod) and function_exported?(mod, :snapshot, 1),
          do: mod.snapshot(now),
          else: fallback()

      _ ->
        fallback()
    end
  end

  defp fallback,
    do: %{founders: Enum.map(people(), &Map.merge(&1, %{name: &1.email, handle: nil})), bots: []}

  @doc """
  True when the "Chat" button shows (a disabled placeholder until team chat
  exists). Config `:team_chat_placeholder`, default true.
  """
  @spec chat_placeholder?() :: boolean()
  def chat_placeholder?,
    do: Application.get_env(:ex_tales_forge, :team_chat_placeholder, true) == true
end
