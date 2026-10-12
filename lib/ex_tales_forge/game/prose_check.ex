defmodule TalesForge.Game.ProseCheck do
  @moduledoc """
  The prose post-check of the turn pipeline (design §5): it compares the GM
  prose with the outcome record (`TalesForge.Game.OutcomeRecord`). Each
  mismatch counts as 1 bug. The check only logs; there is no GM re-run.

  Four kinds of mismatch, with simple pattern rules:

    * `:coins` — the prose names a coin amount, and the record has no coin
      change of that size;
    * `:item` — the prose hands the character an item ("hands you a loaf"),
      and the record has no item gain with that name;
    * `:location` — the prose moves the character to a named place
      ("you step out into Market Square"), and the record has no move;
    * `:clock` — the prose skips time ("the next morning", "hours later"),
      and the record clock moved less than 4 hours.

  Pure: no Repo, no LLM.
  """

  alias TalesForge.Game.WorldClock

  @type mismatch :: %{kind: :coins | :item | :location | :clock, detail: String.t()}

  @numbers %{
    "a" => 1,
    "an" => 1,
    "one" => 1,
    "two" => 2,
    "three" => 3,
    "four" => 4,
    "five" => 5,
    "six" => 6,
    "seven" => 7,
    "eight" => 8,
    "nine" => 9,
    "ten" => 10,
    "twelve" => 12,
    "fifteen" => 15,
    "twenty" => 20,
    "fifty" => 50,
    "hundred" => 100
  }

  @copper %{"copper" => 1, "coppers" => 1, "silver" => 10, "silvers" => 10, "gold" => 500}

  @number_words @numbers |> Map.keys() |> Enum.sort_by(&(-byte_size(&1))) |> Enum.join("|")

  @coin_re ~r/\b(\d+|#{@number_words})\s+(copper|coppers|silver|silvers|gold)\b/

  @give_re ~r/\b(?:hands|gives|passes|tosses|slides|offers)\s+you\s+(?:a|an|the|some|your)?\s*([a-z' -]+?)(?:[.,;!]|\s+for\b|\s+and\b|$)/

  @move_re ~r/\b[Yy]ou\s+(?:step|walk|head|go|move|arrive|stride|wander)\s+(?:out\s+|back\s+)?(?:into|to|at|in|onto)\s+(?:the\s+)?([A-Z][A-Za-z']+(?:\s+[A-Z][A-Za-z']+)*)/

  @skip_re ~r/\b(?:next morning|the next day|morning dawns|dawn breaks|hours later|overnight|by morning|you sleep|you wake)\b/i

  @night_ticks 4 * 60

  @doc """
  The mismatches between `prose` and the outcome `record`.

      iex> record = %{"coins" => %{"delta_copper" => 0}, "items" => %{"gained" => [], "lost" => []},
      ...>   "location" => %{"from" => "valley_inn", "to" => "valley_inn"},
      ...>   "clock" => %{"tick_before" => 72, "tick_after" => 73}}
      iex> TalesForge.Game.ProseCheck.check("Brenna slides you three copper.", record) |> Enum.map(& &1.kind)
      [:coins]
      iex> TalesForge.Game.ProseCheck.check("Brenna nods.", record)
      []
  """
  @spec check(String.t() | nil, map() | nil) :: [mismatch()]
  def check(prose, record) when is_binary(prose) and is_map(record) do
    coins(prose, record) ++
      items(prose, record) ++ location(prose, record) ++ clock(prose, record)
  end

  def check(_prose, _record), do: []

  @doc "The session event that stores the mismatches (kind `turn.prose_mismatch`), or nil."
  @spec event([mismatch()], map()) :: map() | nil
  def event([], _record), do: nil

  def event(mismatches, record) do
    %{
      "kind" => "turn.prose_mismatch",
      "actor" => "server",
      "player_aware" => false,
      "tick" => get_in(record, ["clock", "tick_after"]) || 0,
      "location_id" => get_in(record, ["location", "to"]),
      "payload" => %{
        "count" => length(mismatches),
        "mismatches" =>
          Enum.map(mismatches, &%{"kind" => Atom.to_string(&1.kind), "detail" => &1.detail})
      }
    }
  end

  defp coins(prose, record) do
    delta = abs(get_in(record, ["coins", "delta_copper"]) || 0)

    @coin_re
    |> Regex.scan(String.downcase(prose))
    |> Enum.reject(fn [_, n, denom] -> amount(n) * Map.fetch!(@copper, denom) == delta end)
    |> Enum.map(fn [text | _] -> %{kind: :coins, detail: text} end)
  end

  defp amount(n), do: Map.get(@numbers, n) || String.to_integer(n)

  defp items(prose, record) do
    gained = record |> get_in(["items", "gained"]) |> List.wrap() |> Enum.map(&item_words/1)

    @give_re
    |> Regex.scan(String.downcase(prose))
    |> Enum.map(fn [_, phrase] -> String.trim(phrase) end)
    |> Enum.reject(&(&1 == "" or Regex.match?(@coin_re, &1) or coin_word?(&1)))
    |> Enum.reject(fn phrase -> Enum.any?(gained, &named?(phrase, &1)) end)
    |> Enum.map(&%{kind: :item, detail: &1})
  end

  defp coin_word?(phrase), do: Regex.match?(~r/\b(coins?|copper|silver|gold)\b/, phrase)

  defp item_words(item), do: String.downcase("#{item["name"]} #{item["id"]}")

  defp named?(phrase, words) do
    phrase
    |> String.split()
    |> Enum.any?(&(String.length(&1) > 2 and String.contains?(words, &1)))
  end

  defp location(prose, %{"location" => %{"from" => same, "to" => same}}) do
    @move_re
    |> Regex.scan(prose)
    |> Enum.map(fn [_, place] -> %{kind: :location, detail: place} end)
  end

  defp location(_prose, _record), do: []

  defp clock(prose, record) do
    before = get_in(record, ["clock", "tick_before"]) || 0
    after_turn = get_in(record, ["clock", "tick_after"]) || before
    minutes = (after_turn - before) * WorldClock.minutes_per_tick()

    case Regex.run(@skip_re, prose) do
      [words] when minutes < @night_ticks -> [%{kind: :clock, detail: words}]
      _ -> []
    end
  end
end
