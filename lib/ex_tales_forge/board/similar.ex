defmodule TalesForge.Board.Similar do
  @moduledoc """
  The similar-card check for a new idea on the board (card 'Refine ideation
  process', decision 2026-10-12). The founder writes the idea in the board's
  chat box; before the board creates a card, an AI check
  (`TalesForge.LLM.complete_board_similar/3`) compares the text with every
  card on the board: open, Done and Parked cards (archived cards are left
  out). A match on a Done card means the work is already built.

  The founders chose the AI check over a text match: an unneeded card costs
  more (refinement, building) than one short call per idea. The prompt names
  each card by a short ref (`c1`, `c2`, ...), not its id, so the reply stays
  small and an unknown ref is dropped.
  """

  import Ecto.Query

  alias TalesForge.Board.Idea
  alias TalesForge.{LLM, Repo}

  @max_candidates 300
  @max_matches 3
  @body_chars 240
  @title_chars 120

  @system """
  You check a new idea for a game team's idea board against the cards that are already on the board.
  A card matches when it asks for the same feature or change, a close variant of it, or when it already covers the idea.
  A card on a similar topic that asks for something else is not a match.
  Reply with JSON: "title" is a short title for the new idea (at most 10 words, in the language of the idea);
  "matches" lists at most 3 matching cards, best first, each with its "ref" and a one-sentence "reason".
  Give an empty "matches" list when no card matches.
  """

  @typedoc "A matching card, with the AI's reason and whether the work is done."
  @type match :: %{idea: Idea.t(), reason: String.t(), done: boolean()}

  @typedoc "The result of a check: a title for the new card and the matches."
  @type result :: %{title: String.t(), matches: [match()]}

  @doc """
  Checks `text` against the board. Options: `:candidates` (the cards to
  compare with; default `candidates/0`) and `:llm` (a 3-arity function like
  `TalesForge.LLM.complete_board_similar/3`; default from the
  `:board_similar_llm` app env). With no cards on the board there is no AI
  call.
  """
  @spec check(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def check(text, opts \\ []) do
    text = String.trim(to_string(text))

    if text == "" do
      {:error, :empty}
    else
      cards = Keyword.get_lazy(opts, :candidates, &candidates/0)
      do_check(text, cards, Keyword.get_lazy(opts, :llm, &llm/0))
    end
  end

  defp do_check(text, [], _llm), do: {:ok, %{title: fallback_title(text), matches: []}}

  defp do_check(text, cards, llm) do
    refs = cards |> Enum.with_index(1) |> Map.new(fn {card, n} -> {"c#{n}", card} end)

    case llm.(@system, prompt(text, cards), []) do
      {:ok, %{} = reply} -> {:ok, decode(reply, refs, text)}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected, other}}
    end
  end

  defp llm,
    do: Application.get_env(:ex_tales_forge, :board_similar_llm, &LLM.complete_board_similar/3)

  @doc "The cards a new idea is compared with: every card but the archived ones, newest first."
  @spec candidates() :: [Idea.t()]
  def candidates do
    Idea
    |> where([i], i.column != "archived")
    |> order_by([i], desc: i.inserted_at)
    |> limit(@max_candidates)
    |> Repo.all()
  end

  @doc false
  @spec prompt(String.t(), [Idea.t()]) :: String.t()
  def prompt(text, cards) do
    lines =
      cards
      |> Enum.with_index(1)
      |> Enum.map(fn {card, n} ->
        body = card.body |> to_string() |> squish() |> String.slice(0, @body_chars)

        "c#{n} [#{card.column}] #{squish(card.title)}" <>
          if(body == "", do: "", else: " — " <> body)
      end)

    "New idea:\n#{text}\n\nCards on the board (ref [column] title — description):\n" <>
      Enum.join(lines, "\n")
  end

  defp decode(reply, refs, text) do
    matches =
      reply
      |> Map.get("matches", [])
      |> List.wrap()
      |> Enum.flat_map(fn
        %{"ref" => ref} = m ->
          case Map.get(refs, String.trim(to_string(ref))) do
            nil -> []
            card -> [%{idea: card, reason: to_string(m["reason"]), done: card.column == "done"}]
          end

        _ ->
          []
      end)
      |> Enum.uniq_by(& &1.idea.id)
      |> Enum.take(@max_matches)

    title =
      case reply |> Map.get("title") |> to_string() |> squish() do
        "" -> fallback_title(text)
        t -> String.slice(t, 0, @title_chars)
      end

    %{title: title, matches: matches}
  end

  @doc """
  A title from the idea text when the AI gives none: the first line, cut at
  a word to at most #{@title_chars} characters.

      iex> TalesForge.Board.Similar.fallback_title("Brenna remembers regulars\\nBy name.")
      "Brenna remembers regulars"
  """
  @spec fallback_title(String.t()) :: String.t()
  def fallback_title(text) do
    first = text |> String.trim() |> String.split("\n", parts: 2) |> hd() |> squish()

    if String.length(first) <= @title_chars do
      first
    else
      cut = String.slice(first, 0, @title_chars)

      case String.split(cut, " ") do
        [_one] -> cut
        words -> words |> Enum.drop(-1) |> Enum.join(" ")
      end
      |> Kernel.<>("…")
    end
  end

  @doc """
  The new card's title and body from the chat text: the body is the full
  text, unless it is the same as the title.
  """
  @spec card_attrs(String.t(), String.t()) :: map()
  def card_attrs(title, text) do
    text = String.trim(text)
    %{"title" => title, "body" => if(squish(text) == title, do: "", else: text)}
  end

  defp squish(s), do: s |> to_string() |> String.split() |> Enum.join(" ")
end
