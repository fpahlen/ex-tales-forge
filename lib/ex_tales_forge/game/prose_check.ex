defmodule TalesForge.Game.ProseCheck do
  @moduledoc """
  The prose post-check of the turn pipeline (design §5): it compares the GM
  prose with the outcome record (`TalesForge.Game.OutcomeRecord`). Each
  mismatch counts as 1 bug. The check only logs; there is no GM re-run.

  Five kinds of mismatch, with simple pattern rules:

    * `:coins` — the prose names a coin amount, and the record has no coin
      change of that size;
    * `:item` — the prose hands the character an item ("hands you a loaf",
      "slides a token across to you"), and the record has no item gain with
      that name. A turn that paid coins serves the food or drink it paid
      for, so the placing pattern counts only on a turn with no payment;
    * `:location` — the prose moves the character to a named place
      ("you step out into Market Square"), and the record has no move;
    * `:clock` — the prose skips time ("the next morning", "hours later"),
      and the record clock moved less than 4 hours;
    * `:wound` — only when the record has a combat exchange
      (`COMBAT_OPPOSED=on`, `TalesForge.Game.Combat`): the prose tells blood
      or a wound on the foe, and the attack missed; or the prose tells a
      strike on the character, and no counterattack hit.

  Pure: no Repo, no LLM.
  """

  alias TalesForge.Game.WorldClock

  @type mismatch :: %{kind: :coins | :item | :location | :clock | :wound, detail: String.t()}

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
  # A phrase that names money: a coin word, or @coin_re's "two coppers".
  @coin_word_re ~r/\b(?:coins?|copper|silver|gold)\b|\b(?:\d+|#{@number_words})\s+(?:coppers|silvers)\b/

  @give_re ~r/\b(?:hands|gives|passes|tosses|slides|offers)\s+you\s+(?:(?:a|an|the|some|your)\s+)?(?!(?:any|no|some|every)(?:thing|one|body)\b)([a-z' -]+?)(?:[.,;!]|\s+for\b|\s+and\b|$)/

  # "sliding a small wooden token across to you", "sets a fresh mug of ale
  # in front of you". Gentry's playtest session ead76238 on 2026-10-14.
  @place_re ~r/\b(?:slides?|sliding|sets?|setting|places?|placing|puts?|putting|pushes|pushing)\s+(?:a|an|the|some)\s+([a-z' -]+?)\s+(?:across\s+to|in\s+front\s+of|toward|towards)\s+you\b/

  @move_re ~r/\b[Yy]ou\s+(?:step|walk|head|go|move|arrive|stride|wander)\s+(?:out\s+|back\s+)?(?:into|to|at|in|onto)\s+(?:the\s+)?([A-Z][A-Za-z']+(?:\s+[A-Z][A-Za-z']+)*)/

  @skip_re ~r/\b(?:next morning|the next day|morning dawns|dawn breaks|hours later|overnight|by morning|you sleep|you wake)\b/i

  @night_ticks 4 * 60

  @foe_wound_re ~r/\b(?:blood|bloody|bleeds?|bleeding|bled|gash(?:es)?|wound(?:s|ed)?|cut along|draws? blood)\b/i

  @player_hit_re ~r/\b(?:hits?|strikes?|drives?|slams?|smashes?|cuts?|stabs?|slashes?|punch(?:es)?|kicks?|clubs?)\b[^.!?;]{0,40}\b(?:you|your)\b/i

  @you_re ~r/\b(?:you|your)\b/i

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
      items(prose, record) ++
      location(prose, record) ++ clock(prose, record) ++ wound(prose, record)
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
    paid? = (get_in(record, ["coins", "delta_copper"]) || 0) < 0

    prose
    |> String.downcase()
    |> handed(paid?)
    |> Enum.map(&String.trim(List.last(&1)))
    |> Enum.reject(&(&1 == "" or coin_word?(&1) or Enum.any?(gained, fn g -> named?(&1, g) end)))
    |> Enum.map(&%{kind: :item, detail: &1})
  end

  # What the prose hands over. A paid turn's "slides the ale across to you"
  # is the purchase, so placing counts only when unpaid.
  defp handed(lower, true), do: Regex.scan(@give_re, lower)
  defp handed(lower, false), do: Regex.scan(@give_re, lower) ++ Regex.scan(@place_re, lower)

  defp coin_word?(phrase), do: Regex.match?(@coin_word_re, phrase)

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

  # A sentence with a wound word and no "you" tells a wound on the foe. A
  # strike verb with "you" or "your" close after it tells a hit on the
  # character. A dead or down foe already in the record is a booked hit.
  defp wound(prose, %{"combat" => %{"attack" => attack} = combat}) do
    sentences = String.split(prose, ~r/(?<=[.!?])\s+/)
    foe_hit? = attack["hit"] == true
    player_hit? = get_in(combat, ["counter", "hit"]) == true

    foe =
      if foe_hit?,
        do: [],
        else:
          sentences
          |> Enum.reject(&Regex.match?(@you_re, &1))
          |> Enum.flat_map(&(Regex.run(@foe_wound_re, &1) || []))
          |> Enum.take(1)
          |> Enum.map(&%{kind: :wound, detail: "foe: " <> &1})

    player =
      if player_hit?,
        do: [],
        else:
          @player_hit_re
          |> Regex.run(prose)
          |> List.wrap()
          |> Enum.take(1)
          |> Enum.map(&%{kind: :wound, detail: "character: " <> &1})

    foe ++ player
  end

  defp wound(_prose, _record), do: []

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
