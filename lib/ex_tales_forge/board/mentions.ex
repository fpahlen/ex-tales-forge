defmodule TalesForge.Board.Mentions do
  @moduledoc """
  The one mention parser of the idea board. Pure: each function gets the team
  config (`Workflow.Team`) as its first argument.

  A comment can name bots (`@<bot id>`: a webhook wakes the bot) and founders
  (`@<handle>`: the founder gets a ping on `/team`). `@founders` pings every
  founder except the author. `@devops` names all bots of the team, as if the
  comment named each one.

  A founder's handle is their name from the team config, in lower case and
  without accents (`Workflow.Team.handles/1`). A handle with an accent also
  works with the accent. Founders sign in with GitHub, so `handle_for/2` finds
  the handle of a GitHub login in the team config (case-insensitive).
  """

  require Logger

  alias Workflow.Team

  @everyone "founders"
  @devops "devops"

  @typedoc "What a comment mentions."
  @type t :: %{bots: [atom()], founders: [String.t()]}

  @doc """
  The bots and founder handles that `body` mentions, in order, once each.
  `@founders` gives every handle. `@devops` gives every bot, and a bot that
  the body also names directly is still there only once. An email address is
  not a mention. Give `handles` to parse with other founder handles.

      iex> alias TalesForge.Board.Mentions
      iex> team = Workflow.Team.example()
      iex> Mentions.parse(team, "@Rita look? cc @quill and @Örjan, not @bramx or a@ada.se")
      %{bots: [:rita, :quill], founders: ["orjan"]}
      iex> Mentions.parse(team, "@founders and @ada", ~w(ada orjan))
      %{bots: [], founders: ["ada", "orjan"]}
      iex> Mentions.parse(team, "nothing here")
      %{bots: [], founders: []}
      iex> Mentions.parse(team, "@quill and @DevOps, please", [])
      %{bots: [:quill, :rita, :bram], founders: []}
  """
  @spec parse(Team.t(), String.t() | nil, [String.t()] | nil) :: t()
  def parse(team, body, handles \\ nil)

  def parse(%Team{} = team, body, handles) when is_binary(body) do
    handles = handles || Team.handles(team)
    names = body |> words() |> Enum.uniq()

    founders =
      if @everyone in names, do: handles, else: Enum.filter(names, &(&1 in handles))

    %{
      bots: names |> Enum.flat_map(&bot_names(team, &1)) |> Enum.uniq(),
      founders: Enum.uniq(founders)
    }
  end

  def parse(_team, _body, _handles), do: %{bots: [], founders: []}

  defp bot_names(team, @devops), do: Team.bot_ids(team)

  defp bot_names(team, name) do
    case Team.bot_id(team, name) do
      nil -> []
      id -> [id]
    end
  end

  @doc """
  The bots that `body` wakes, in order, once each: every bot that `body`
  names directly, and every bot of `@devops` that has a webhook. `@devops`
  skips a bot without a webhook URL and key (`TalesForge.BoardApi.bot_config/1`)
  and logs this at debug level only. A direct mention keeps its wake-up job
  in all cases (`TalesForge.Board.Workers.Notify` cancels it when there is no
  webhook).

      iex> alias TalesForge.Board.Mentions
      iex> team = Workflow.Team.example()
      iex> Mentions.wakes(team, "@devops and @rita", &(&1 == :bram))
      [:rita, :bram]
      iex> Mentions.wakes(team, "@devops @quill", fn _ -> false end)
      [:quill]
      iex> Mentions.wakes(team, "no bots", fn _ -> true end)
      []
  """
  @spec wakes(Team.t(), String.t() | nil, (atom() -> boolean())) :: [atom()]
  def wakes(team, body, webhook? \\ &webhook?/1)

  def wakes(%Team{} = team, body, webhook?) when is_binary(body) do
    direct = body |> words() |> Enum.filter(&(&1 in Team.bot_handles(team)))

    team
    |> parse(body, [])
    |> Map.fetch!(:bots)
    |> Enum.filter(fn bot ->
      cond do
        Atom.to_string(bot) in direct ->
          true

        webhook?.(bot) ->
          true

        true ->
          Logger.debug("@devops: #{bot} has no webhook, not woken")
          false
      end
    end)
  end

  def wakes(_team, _body, _webhook?), do: []

  defp webhook?(bot) do
    config = TalesForge.BoardApi.bot_config(bot)
    is_binary(config[:webhook_url]) and is_binary(config[:webhook_key])
  end

  @doc """
  The body split into text and mentions, to highlight the mentions.

      iex> TalesForge.Board.Mentions.segments(Workflow.Team.example(), "Hi @Lin and @nobody")
      [{:text, "Hi "}, {:mention, "@Lin"}, {:text, " and @nobody"}]
  """
  @spec segments(Team.t(), String.t()) :: [{:text | :mention, String.t()}]
  def segments(%Team{} = team, body) when is_binary(body) do
    known = Team.handles(team) ++ Team.bot_handles(team) ++ [@everyone, @devops]

    ~r/(?<![\w@.])@\p{L}+(?!\p{L})/u
    |> Regex.split(body, include_captures: true, trim: true)
    |> Enum.map(fn
      "@" <> name = s -> if Team.plain(name) in known, do: {:mention, s}, else: {:text, s}
      s -> {:text, s}
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      [{:text, _} | _] = parts -> [{:text, Enum.map_join(parts, &elem(&1, 1))}]
      mentions -> mentions
    end)
  end

  @doc """
  The handles that the comment box suggests: founders, `founders`, `devops`,
  then the bots.

      iex> TalesForge.Board.Mentions.suggestions(Workflow.Team.example())
      ["ada", "orjan", "lin", "founders", "devops", "rita", "bram", "quill"]
  """
  @spec suggestions(Team.t()) :: [String.t()]
  def suggestions(%Team{} = team),
    do: Team.handles(team) ++ [@everyone, @devops] ++ Team.bot_handles(team)

  @doc """
  The founder handles, from the team config.

      iex> TalesForge.Board.Mentions.handles(Workflow.Team.example())
      ["ada", "orjan", "lin"]
  """
  @spec handles(Team.t()) :: [String.t()]
  def handles(%Team{} = team), do: Team.handles(team)

  @doc """
  The handle of a founder's GitHub login (case-insensitive), or nil.

      iex> alias TalesForge.Board.Mentions
      iex> team = Workflow.Team.example()
      iex> Mentions.handle_for(team, "Orjan-GH")
      "orjan"
      iex> Mentions.handle_for(team, "someone")
      nil
      iex> Mentions.handle_for(team, nil)
      nil
  """
  @spec handle_for(Team.t(), String.t() | nil) :: String.t() | nil
  def handle_for(%Team{} = team, login) when is_binary(login),
    do: Map.get(Team.github_handles(team), login |> String.trim() |> String.downcase())

  def handle_for(_team, _login), do: nil

  defp words(body) do
    ~r/(?<![\w@.])@(\p{L}+)(?!\p{L})/u
    |> Regex.scan(body)
    |> Enum.map(fn [_, name] -> Team.plain(name) end)
  end
end
