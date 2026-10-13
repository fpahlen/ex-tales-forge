defmodule TalesForge.TeamOnline do
  @moduledoc """
  The data of the "who is online" counter in the admin and /team header
  (`TalesForgeWeb.OnlineHeaderLive`, board card "Who's online right now"):

  - **Founders**: everyone with a page open on production or playtest right
    now (`TalesForge.Online.people/1`, Phoenix Presence plus playtest's
    list), one entry per person with each page and app once.
  - **Bots** (the bots of the team config, `Workflow.Team`) do not keep a
    page open. Each shows their latest activity and when it was: a board API
    call (each wake-up reads the board), a comment, a card move or a link on
    the board, and for the builder the latest pull request in the live PR
    feed (the builder writes the pull requests).
    A bot counts as online when that was less than `online_minutes/0` ago.

  `snapshot/1` is the edge: it reads the team config and the activity. `bots/3`
  and `name/3` are pure and get the team config as an argument.
  """

  import Ecto.Query

  alias TalesForge.AppRole
  alias TalesForge.Board.{Comment, Link, Transition}
  alias TalesForge.Board.Mentions
  alias TalesForge.Online
  alias TalesForge.PrFeed
  alias TalesForge.Workflow.Repo
  alias Workflow.Team

  @online_minutes 10

  @typedoc "A founder as shown: `t:TalesForge.Online.person/0` plus the display name and @handle."
  @type founder :: %{
          key: String.t(),
          name: String.t(),
          handle: String.t() | nil,
          email: String.t(),
          login: String.t() | nil,
          locations: [String.t()],
          since: DateTime.t()
        }

  @typedoc "A bot as shown; `at` and `doing` are nil when nothing was seen yet."
  @type bot :: %{
          id: String.t(),
          name: String.t(),
          at: DateTime.t() | nil,
          doing: String.t() | nil,
          online: boolean()
        }

  @typedoc "Everything the section shows."
  @type t :: %{founders: [founder()], bots: [bot()]}

  @doc "A bot is online when its latest activity is this many minutes old or less."
  @spec online_minutes() :: pos_integer()
  def online_minutes, do: @online_minutes

  @doc "Founders and bots now."
  @spec snapshot(DateTime.t()) :: t()
  def snapshot(now \\ DateTime.utc_now()) do
    team = Workflow.Team.Source.team()

    %{
      founders:
        Enum.map(Online.people(), fn p ->
          Map.merge(p, %{
            name: name(team, p.email, p.login),
            handle: Mentions.handle_for(team, p.login)
          })
        end),
      bots: bots(team, activity(team), now)
    }
  end

  @doc """
  Each bot with its newest activity from `events` (`{bot, at, doing}` tuples),
  and whether that is recent enough to count as online. The most recently
  active bot comes first; bots with no activity come last, in their usual
  order.

      iex> team = Workflow.Team.example()
      iex> now = ~U[2026-10-10 12:00:00Z]
      iex> [r, b, q] = TalesForge.TeamOnline.bots(team, [{:rita, ~U[2026-10-10 11:55:00Z], "Read the board"},
      ...>   {:rita, ~U[2026-10-10 10:00:00Z], "Commented on a card"},
      ...>   {:bram, ~U[2026-10-10 09:00:00Z], "Pull request #7"}], now)
      iex> {r.name, r.doing, r.online, b.online, q.at}
      {"Rita", "Read the board", true, false, nil}

      iex> team = Workflow.Team.example()
      iex> now = ~U[2026-10-10 23:00:00Z]
      iex> TalesForge.TeamOnline.bots(team, [{:rita, ~U[2026-10-10 20:33:00Z], "Read the board"},
      ...>   {:bram, ~U[2026-10-10 22:19:00Z], "Pull request #7"}], now) |> Enum.map(& &1.id)
      ["bram", "rita", "quill"]
  """
  @spec bots(Team.t(), [{atom(), DateTime.t(), String.t()}], DateTime.t()) :: [bot()]
  def bots(%Team{} = team, events, %DateTime{} = now) do
    for %{id: id, name: name} <- team.bots do
      latest =
        events
        |> Enum.filter(&(elem(&1, 0) == id and match?(%DateTime{}, elem(&1, 1))))
        |> Enum.max_by(&DateTime.to_unix(elem(&1, 1), :microsecond), fn -> nil end)

      case latest do
        {_, at, doing} ->
          %{
            id: Atom.to_string(id),
            name: name,
            at: at,
            doing: doing,
            online: DateTime.diff(now, at, :second) <= @online_minutes * 60
          }

        nil ->
          %{id: Atom.to_string(id), name: name, at: nil, doing: nil, online: false}
      end
    end
    |> Enum.sort_by(&if(&1.at, do: -DateTime.to_unix(&1.at, :microsecond), else: :never))
  end

  @doc """
  A founder's display name from the team config (accents kept). First the
  handle of their GitHub login (`TalesForge.Board.Mentions.handle_for/2`), so
  "Orjan-GH" is "Örjan"; then the login that the whole email local part
  spells (letters only, so "orjan.gh@…" is the login "orjan-gh", "Örjan");
  then the first part of the email; else that first part, capitalised.

      iex> team = Workflow.Team.example()
      iex> TalesForge.TeamOnline.name(team, "orjan.gh@example.com", "Orjan-GH")
      "Örjan"
      iex> TalesForge.TeamOnline.name(team, "ada@example.com")
      "Ada"
      iex> TalesForge.TeamOnline.name(team, "orjan.x@example.com", "unknown-login")
      "Örjan"
      iex> TalesForge.TeamOnline.name(team, "sam@example.com")
      "Sam"
  """
  @spec name(Team.t(), String.t(), String.t() | nil) :: String.t()
  def name(%Team{} = team, email, login \\ nil) do
    first = email |> String.split(["@", ".", "+"]) |> hd() |> String.downcase()

    handle =
      Mentions.handle_for(team, login) || handle_of_email(team, email) || Team.plain(first)

    names = Team.founder_names(team)

    Enum.find(names, &(Team.plain(&1) == handle)) ||
      Enum.find(names, String.capitalize(first), &(Team.plain(&1) == Team.plain(first)))
  end

  # The founder handle whose GitHub login spells the email local part.
  defp handle_of_email(team, email) do
    local = email |> String.split("@") |> hd() |> Team.plain()

    team
    |> Team.github_handles()
    |> Enum.find_value(fn {login, handle} -> Team.plain(login) == local && handle end)
  end

  # Every bot activity we know of, as {bot, at, doing}.
  defp activity(team) do
    calls = for {bot, at} <- Online.bot_calls(), do: {bot, at, "Read the board"}
    calls ++ board_activity(team) ++ pr_activity(team)
  end

  defp board_activity(team) do
    if AppRole.here?(:board) do
      latest(team, Comment, :author, "Commented on a card") ++
        latest(team, Transition, :actor, "Moved a card") ++
        latest(team, Link, :added_by, "Linked a card")
    else
      []
    end
  rescue
    _ -> []
  end

  defp latest(team, schema, field, doing) do
    from(r in schema,
      where: like(field(r, ^field), "bot:%"),
      group_by: field(r, ^field),
      select: {field(r, ^field), max(r.inserted_at)}
    )
    |> Repo.all()
    |> Enum.flat_map(&bot_activity(team, &1, doing))
  end

  defp bot_activity(team, {actor, at}, doing) do
    case Team.bot_id(team, actor) do
      nil -> []
      id -> [{id, to_utc(at), doing}]
    end
  end

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  # The builder writes the pull requests: the newest one in the feed.
  defp pr_activity(team) do
    case PrFeed.snapshot() do
      %{items: [_ | _] = items} ->
        items
        |> Enum.filter(&match?(%DateTime{}, &1.at))
        |> Enum.map(fn i -> {Team.bot(team, :builder), i.at, "Pull request ##{i.number}"} end)

      _ ->
        []
    end
  rescue
    _ -> []
  end
end
