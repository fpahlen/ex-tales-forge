defmodule TalesForge.Game.SkillSplit do
  @moduledoc """
  Skill split (`SKILL_SPLIT=on`, default off; rules text in
  `priv/rules/core_mechanics.md`, "Skill split").

  A player splits one skill action into two or three parts in one turn. The
  server rolls each part at its part level (`TalesForge.Game.Mechanics.split_levels/2`
  and `TalesForge.Game.Mechanics.perform_part/4`). The GM narrates each part
  and invents no parts.

  All functions here are pure. The injected rolls come from the turn options
  (`:rolls`), so a test sets each part roll.

  A split action banks one learning chance at most. The first part that
  earns a learning chance banks it, and the other parts bank nothing.
  """

  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction}

  @split_on ~r/<!-- skill_split:on -->\n(.*?)<!-- \/skill_split:on -->\n/s
  @split_off ~r/<!-- skill_split:off -->\n(.*?)<!-- \/skill_split:off -->\n/s

  @two_words ~r/\b(twice|two (?:attacks|strikes|blows|cuts|swings|shots|attempts|tries|times)|double (?:attack|strike)|split (?:it |my \w+ )?(?:in|into) (?:two|2))\b/i
  @three_words ~r/\b(thrice|three (?:attacks|strikes|blows|cuts|swings|shots|attempts|tries|times)|triple (?:attack|strike)|split (?:it |my \w+ )?(?:in|into) (?:three|3))\b/i
  @uneven ~r/\b(\d{1,3})\s*(?:and|\/|\+|,)\s*(\d{1,3})\b/

  @doc """
  The rules text for the flag. Flag on: the text keeps the `skill_split:on`
  blocks and drops the `skill_split:off` blocks. Flag off: the reverse. The
  block markers never reach the prompt, so the text with the flag off is
  byte-identical to the text before the split rules.

      iex> text = "a\\n<!-- skill_split:on -->\\nnew\\n<!-- /skill_split:on -->\\n<!-- skill_split:off -->\\nold\\n<!-- /skill_split:off -->\\nb"
      iex> TalesForge.Game.SkillSplit.rules_text(text, false)
      "a\\nold\\nb"
      iex> TalesForge.Game.SkillSplit.rules_text(text, true)
      "a\\nnew\\nb"
  """
  @spec rules_text(String.t() | nil, boolean()) :: String.t() | nil
  def rules_text(nil, _on), do: nil

  def rules_text(text, true),
    do: text |> String.replace(@split_off, "") |> String.replace(@split_on, "\\1")

  def rules_text(text, false),
    do: text |> String.replace(@split_on, "") |> String.replace(@split_off, "\\1")

  @doc """
  The split count that the player text asks for (the Elixir backup of the
  Jev `split` field): 2 for "twice" or "two attacks", 3 for "three attacks",
  else 1.

      iex> TalesForge.Game.SkillSplit.count_from_text("I attack him twice")
      2
      iex> TalesForge.Game.SkillSplit.count_from_text("I make two attacks with my sword")
      2
      iex> TalesForge.Game.SkillSplit.count_from_text("three strikes, fast")
      3
      iex> TalesForge.Game.SkillSplit.count_from_text("I attack")
      1
  """
  @spec count_from_text(String.t() | nil) :: 1..3
  def count_from_text(text) when is_binary(text) do
    cond do
      Regex.match?(@three_words, text) -> 3
      Regex.match?(@two_words, text) -> 2
      true -> 1
    end
  end

  def count_from_text(_text), do: 1

  @doc """
  The two uneven parts in the player text, for example "at 95 and 55", or nil.

      iex> TalesForge.Game.SkillSplit.uneven_from_text("a strong cut at 95 and a quick jab at 55")
      [95, 55]
      iex> TalesForge.Game.SkillSplit.uneven_from_text("two attacks, 95 and 55")
      [95, 55]
      iex> TalesForge.Game.SkillSplit.uneven_from_text("I attack")
      nil
  """
  @spec uneven_from_text(String.t() | nil) :: [pos_integer()] | nil
  def uneven_from_text(text) when is_binary(text) do
    case Regex.run(@uneven, text) do
      [_, a, b] -> [String.to_integer(a), String.to_integer(b)]
      nil -> uneven_at_pairs(text)
    end
  end

  def uneven_from_text(_text), do: nil

  # "a strong cut at 95 and a quick jab at 55": two "at <n>" numbers.
  defp uneven_at_pairs(text) do
    case Regex.scan(~r/\bat (\d{1,3})\b/i, text) do
      [[_, a], [_, b]] -> [String.to_integer(a), String.to_integer(b)]
      _other -> nil
    end
  end

  @doc """
  The split request of the action: the uneven parts in the text, else the
  `"split"` parameter (Jev or the heuristic), else the count in the text.
  Returns 1 when the player asks for no split.

      iex> alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}
      iex> action = %PlayerAction{action: %SingleAction{action_type: :combat, parameters: %{"split" => 2}}}
      iex> TalesForge.Game.SkillSplit.request(action, "I strike")
      2
      iex> TalesForge.Game.SkillSplit.request(action, "two cuts at 95 and 55")
      [95, 55]
  """
  @spec request(PlayerAction.t(), String.t() | nil) :: 1..3 | [pos_integer()]
  def request(%PlayerAction{action: action}, text) do
    param = split_param(action && action.parameters)
    count = if param > 1, do: param, else: count_from_text(text)

    parts = uneven_from_text(text)

    cond do
      is_list(parts) and count == 2 -> parts
      is_list(parts) and count == 1 and split_word?(text) -> parts
      true -> count
    end
  end

  defp split_word?(text) when is_binary(text), do: Regex.match?(~r/\bsplit\b/i, text)
  defp split_word?(_text), do: false

  defp split_param(%{"split" => n}) when n in [2, 3], do: n
  defp split_param(_params), do: 1

  @doc """
  The server check of a turn with the split. A turn with no split request
  plays as `Mechanics.apply_server_mechanics/3`. A refused split plays one
  normal attempt, and the resolution carries the refusal for the story.

  `opts`: `:rolls`, a list of injected d20 rolls (one for each part).
  """
  @spec apply(map(), PlayerAction.t(), HandlerResult.t(), String.t() | nil, keyword()) ::
          {map(), MechanicalResolution.t()}
  def apply(character, player_action, handler, text, opts \\ []) do
    skill = check_skill(player_action, handler)
    rolls = Keyword.get(opts, :rolls, [])

    case {skill, request(player_action, text)} do
      {nil, _request} ->
        Mechanics.apply_server_mechanics(character, player_action, handler)

      {_skill, 1} ->
        single(character, skill, handler, rolls, nil)

      {skill, request} ->
        level = {Mechanics.raw_level(character, skill), effective(character, skill, handler)}

        case Mechanics.split_levels(level, request) do
          {:ok, parts} ->
            split(character, skill, parts, rolls)

          {:error, reason} ->
            single(character, skill, handler, rolls, %{
              "requested" => requested(request),
              "refused" => Atom.to_string(reason)
            })
        end
    end
  end

  defp check_skill(player_action, handler) do
    action_skill =
      player_action.action.parameters
      |> Map.get("skill")
      |> Mechanics.normalize_skill_name()

    Mechanics.resolve_check_skill(handler.handler, handler.skill, action_skill)
  end

  defp modifier(handler), do: (handler.state_hints || %{})["roll_modifier"] || 0

  defp effective(character, skill, handler),
    do: max(0, Mechanics.effective_level(character, skill) + modifier(handler))

  defp requested(parts) when is_list(parts), do: parts
  defp requested(count), do: count

  defp single(character, skill, handler, rolls, split) do
    {updated, resolution} =
      Mechanics.perform_and_apply(character, skill, List.first(rolls), modifier(handler))

    {updated, %{resolution | split: split}}
  end

  # Each part rolls against the character before the turn. The first part
  # that earns a learning chance gives the character after the turn; the
  # other parts bank nothing (one learning chance for each split action).
  defp split(character, skill, parts, rolls) do
    results =
      parts
      |> Enum.with_index()
      |> Enum.map(fn {level, i} ->
        Mechanics.perform_part(character, skill, level, Enum.at(rolls, i))
      end)

    learned = Enum.find(results, fn {_char, res} -> (res.lp_awarded || 0) > 0 end)

    {updated, lp} =
      if learned, do: {elem(learned, 0), elem(learned, 1).lp_awarded}, else: {character, 0.0}

    {_char, best} = Enum.max_by(results, fn {_char, res} -> rank(res.outcome) end, fn -> nil end)

    part_rows =
      Enum.map(results, fn {_char, res} ->
        %{"level" => res.effective_skill, "roll" => res.roll, "outcome" => res.outcome}
      end)

    resolution = %{
      best
      | lp_awarded: lp,
        parts: part_rows,
        split: %{"requested" => length(parts), "parts" => parts},
        notes:
          "Split into #{length(parts)} parts: " <>
            Enum.map_join(
              part_rows,
              ", ",
              &"#{&1["level"]} rolled #{&1["roll"]} (#{&1["outcome"]})"
            ) <>
            ". One learning chance at most."
    }

    {updated, resolution}
  end

  defp rank("success"), do: 2
  defp rank("partial_success"), do: 1
  defp rank(_outcome), do: 0

  @doc """
  The GM prompt section for a split, or nil when the turn has no split.

      iex> alias TalesForge.Game.Schemas.MechanicalResolution, as: M
      iex> TalesForge.Game.SkillSplit.prompt_section(%M{})
      nil
  """
  @spec prompt_section(MechanicalResolution.t() | term()) :: String.t() | nil
  def prompt_section(%MechanicalResolution{parts: parts, skill: skill}) when is_list(parts) do
    lines =
      parts
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {part, i} ->
        "- Part #{i}: level #{part["level"]}, roll #{part["roll"]}, result #{part["outcome"]}"
      end)

    """
    ## Skill split (rolled by the server)
    The player split one #{skill} action into #{length(parts)} parts. Narrate each part and its result in this order. Narrate only these parts, with these results.
    #{lines}
    """
  end

  def prompt_section(%MechanicalResolution{split: %{"refused" => reason} = split, skill: skill}) do
    """
    ## Skill split (refused by the server)
    The player asked to split one #{skill} action (#{inspect(split["requested"])}). The server refused the split: #{reason_text(reason)} The server rolled one normal attempt. In the story, show that this split needs more skill. Then narrate the one attempt.
    """
  end

  def prompt_section(_mechanical), do: nil

  defp reason_text("below_start"),
    do: "the raw skill level is below the split start (#{settings().start})."

  defp reason_text("below_triple"),
    do: "three parts or uneven parts need a raw skill level of #{settings().triple} or more."

  defp reason_text("part_below_minimum"),
    do: "each uneven part must be #{settings().min_uneven_part} or more."

  defp reason_text("parts_do_not_sum"), do: "the parts must sum to the skill level."
  defp reason_text(_reason), do: "the request is not a valid split."

  defp settings, do: TalesForge.Config.skill_split_settings()
end
