defmodule TalesForge.Board.Mentions do
  @moduledoc """
  The one mention parser of the idea board. A comment can name bots
  (`@case`, `@bobby`, `@gentry`: a webhook wakes the bot) and founders
  (`@fredrik`, `@hakan`, ...: the founder gets a ping on `/team`).
  `@founders` pings every founder except the author. `@devops` names all
  three bots (Case, Bobby and Gentry), as if the comment named each one.

  A founder's handle is their first name from the team data
  (`priv/team/data.json`), in lower case and without accents, so "Håkan" is
  `@hakan` (`@håkan` also works). Founders sign in with GitHub, so
  `handle_for/1` finds the handle of a GitHub login in the
  `:board_founder_handles` config (login to handle, case-insensitive).
  """

  require Logger

  @bots ~w(case bobby gentry)
  @everyone "founders"
  @devops "devops"

  @typedoc "What a comment mentions."
  @type t :: %{bots: [:case | :bobby | :gentry], founders: [String.t()]}

  @doc """
  The bots and founder handles that `body` mentions, in order, once each.
  `@founders` gives every handle. `@devops` gives every bot, and a bot that
  the body also names directly is still there only once. An email address is
  not a mention.

      iex> alias TalesForge.Board.Mentions
      iex> Mentions.parse("@Case look? cc @gentry and @Håkan, not @bobbyx or a@fredrik.se", ~w(fredrik hakan))
      %{bots: [:case, :gentry], founders: ["hakan"]}
      iex> Mentions.parse("@founders and @fredrik", ~w(fredrik hakan))
      %{bots: [], founders: ["fredrik", "hakan"]}
      iex> Mentions.parse("nothing here", ~w(fredrik))
      %{bots: [], founders: []}
      iex> Mentions.parse("@gentry and @DevOps, please", ~w(fredrik))
      %{bots: [:gentry, :case, :bobby], founders: []}
  """
  @spec parse(String.t() | nil, [String.t()]) :: t()
  def parse(body, handles \\ handles())

  def parse(body, handles) when is_binary(body) do
    names = body |> words() |> Enum.uniq()

    founders =
      if @everyone in names, do: handles, else: Enum.filter(names, &(&1 in handles))

    %{
      bots:
        names
        |> Enum.flat_map(&bot_names/1)
        |> Enum.uniq()
        |> Enum.map(&String.to_existing_atom/1),
      founders: Enum.uniq(founders)
    }
  end

  def parse(_body, _handles), do: %{bots: [], founders: []}

  defp bot_names(@devops), do: @bots
  defp bot_names(name) when name in @bots, do: [name]
  defp bot_names(_name), do: []

  @doc """
  The bots that `body` wakes, in order, once each: every bot that `body`
  names directly, and every bot of `@devops` that has a webhook. `@devops`
  skips a bot without a webhook URL and key (`TalesForge.BoardApi.bot_config/1`)
  and logs this at debug level only. A direct mention keeps its wake-up job
  in all cases (`TalesForge.Board.Workers.Notify` cancels it when there is no
  webhook).

      iex> alias TalesForge.Board.Mentions
      iex> Mentions.wakes("@devops and @case", &(&1 == :bobby))
      [:case, :bobby]
      iex> Mentions.wakes("@devops @gentry", fn _ -> false end)
      [:gentry]
      iex> Mentions.wakes("no bots", fn _ -> true end)
      []
  """
  @spec wakes(String.t() | nil, (atom() -> boolean())) :: [:case | :bobby | :gentry]
  def wakes(body, webhook? \\ &webhook?/1)

  def wakes(body, webhook?) when is_binary(body) do
    direct = body |> words() |> Enum.filter(&(&1 in @bots))

    body
    |> parse([])
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

  def wakes(_body, _webhook?), do: []

  defp webhook?(bot) do
    config = TalesForge.BoardApi.bot_config(bot)
    is_binary(config[:webhook_url]) and is_binary(config[:webhook_key])
  end

  @doc """
  The body split into text and mentions, to highlight the mentions.

      iex> TalesForge.Board.Mentions.segments("Hi @Max and @nobody", ~w(max))
      [{:text, "Hi "}, {:mention, "@Max"}, {:text, " and @nobody"}]
  """
  @spec segments(String.t(), [String.t()]) :: [{:text | :mention, String.t()}]
  def segments(body, handles \\ handles()) when is_binary(body) do
    known = handles ++ @bots ++ [@everyone, @devops]

    ~r/(?<![\w@.])@\p{L}+(?!\p{L})/u
    |> Regex.split(body, include_captures: true, trim: true)
    |> Enum.map(fn
      "@" <> name = s -> if plain(name) in known, do: {:mention, s}, else: {:text, s}
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
  """
  @spec suggestions() :: [String.t()]
  def suggestions, do: handles() ++ [@everyone, @devops] ++ @bots

  @doc "The founder handles, from the team data."
  @spec handles() :: [String.t()]
  def handles do
    TalesForge.TeamPage.data()
    |> TalesForge.TeamPage.members()
    |> Enum.find_value([], fn m -> m["kind"] == "humans" && get_in(m, ["people", "names"]) end)
    |> List.wrap()
    |> Enum.map(&plain/1)
  end

  @doc """
  The handle of a founder's GitHub login (case-insensitive), or nil.

      iex> alias TalesForge.Board.Mentions
      iex> Mentions.handle_for("Hawkan-Fredriksson", %{"hawkan-fredriksson" => "hakan"})
      "hakan"
      iex> Mentions.handle_for("someone", %{"fpahlen" => "fredrik"})
      nil
      iex> Mentions.handle_for(nil, %{})
      nil
  """
  @spec handle_for(String.t() | nil, map()) :: String.t() | nil
  def handle_for(login, overrides \\ overrides())

  def handle_for(login, overrides) when is_binary(login),
    do: Map.get(overrides, login |> String.trim() |> String.downcase())

  def handle_for(_login, _overrides), do: nil

  defp overrides, do: Application.get_env(:ex_tales_forge, :board_founder_handles, %{})

  defp words(body) do
    ~r/(?<![\w@.])@(\p{L}+)(?!\p{L})/u
    |> Regex.scan(body)
    |> Enum.map(fn [_, name] -> plain(name) end)
  end

  defp plain(name) do
    name
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z]/u, "")
  end
end
