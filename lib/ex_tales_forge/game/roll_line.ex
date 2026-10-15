defmodule TalesForge.Game.RollLine do
  @moduledoc """
  The one-line text of a turn's roll, shown under the GM text on the play
  page (QA 2026-10-14 21:15: the non-combat checks showed no roll, and a skill
  grew with no marker).

  It reads the stored `mechanical_resolution` (string keys,
  `MechanicalResolution.encode/1`): the combat exchange when there is one
  (`TalesForge.Game.Combat.summary/1`), otherwise the skill check with its
  d100 band. An improvement of a skill on this turn adds a marker. A turn
  with no roll and no improvement has no line (nil).
  """

  alias TalesForge.Game.Combat

  @doc """
  The roll line of `mechanical`, or nil.

      iex> TalesForge.Game.RollLine.text(%{"skill" => "climbing", "roll" => 85, "effective_skill" => 20, "outcome" => "failure"})
      "Climbing: d100 85 vs 20: failure."
      iex> TalesForge.Game.RollLine.text(%{"skill" => "stealth", "roll" => 2, "effective_skill" => 40, "outcome" => "critical_success"})
      "Stealth: d100 2 vs 40: critical success."
      iex> TalesForge.Game.RollLine.text(%{"skill" => "insight", "roll" => 50, "effective_skill" => 40, "outcome" => "partial_success"})
      "Insight: d100 50 vs 40: near miss."
      iex> TalesForge.Game.RollLine.text(%{"skill" => "melee_combat", "roll" => 90, "effective_skill" => 10, "outcome" => "failure",
      ...>   "improvements" => [%{"skill" => "melee_combat", "roll" => 70, "raw_skill" => 5, "improved" => true, "gain" => 6}]})
      "Melee combat: d100 90 vs 10: failure. Skill improved: melee combat +6 (5 to 11)."
      iex> TalesForge.Game.RollLine.text(%{"skill" => "melee_combat", "roll" => 4, "outcome" => "success",
      ...>   "parts" => [%{"level" => 20, "roll" => 4, "outcome" => "success"}, %{"level" => 20, "roll" => 60, "outcome" => "failure"}]})
      "Melee combat in 2 parts: d100 4 vs 20: success, d100 60 vs 20: failure."
      iex> TalesForge.Game.RollLine.text(%{"outcome" => "none", "improvements" => []})
      nil
  """
  @spec text(map() | nil) :: String.t() | nil
  def text(mechanical) when is_map(mechanical) do
    [roll_text(mechanical), improvement_text(mechanical["improvements"])]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  def text(_mechanical), do: nil

  defp roll_text(%{"combat" => %{"attack" => _} = exchange}), do: Combat.summary(exchange)

  defp roll_text(%{"skill" => skill, "parts" => [_ | _] = parts}) when is_binary(skill) do
    rolls =
      Enum.map_join(parts, ", ", fn part ->
        "d100 #{part["roll"]} vs #{part["level"]}: #{outcome_word(part["outcome"])}"
      end)

    "#{String.capitalize(skill_name(skill))} in #{length(parts)} parts: #{rolls}."
  end

  defp roll_text(%{"skill" => skill, "roll" => roll, "outcome" => outcome} = m)
       when is_binary(skill) and is_integer(roll) do
    "#{String.capitalize(skill_name(skill))}: d100 #{roll} vs #{m["effective_skill"]}: #{outcome_word(outcome)}."
  end

  defp roll_text(_mechanical), do: nil

  defp improvement_text(improvements) when is_list(improvements) do
    improvements
    |> Enum.filter(&(is_map(&1) and &1["improved"] == true))
    |> Enum.map(&improved/1)
    |> case do
      [] -> nil
      parts -> "Skill improved: " <> Enum.join(parts, ", ") <> "."
    end
  end

  defp improvement_text(_improvements), do: nil

  # The sheet numbers: the effective level before and after (QA 2026-10-15).
  defp improved(%{"skill" => skill, "effective_before" => before, "effective_after" => later})
       when is_integer(before) and is_integer(later) and later > before,
       do: "#{skill_name(skill)} +#{later - before} (#{before} to #{later})"

  defp improved(%{"skill" => skill, "raw_skill" => before, "gain" => gain})
       when is_integer(before) and is_integer(gain),
       do: "#{skill_name(skill)} +#{gain} (#{before} to #{before + gain})"

  defp improved(%{"skill" => skill}), do: skill_name(skill)

  @doc """
  The player word for a check outcome.

      iex> Enum.map(~w(critical_success success partial_success failure critical_failure), &TalesForge.Game.RollLine.outcome_word/1)
      ["critical success", "success", "near miss", "failure", "critical failure"]
  """
  @spec outcome_word(String.t() | nil) :: String.t()
  def outcome_word("critical_success"), do: "critical success"
  def outcome_word("success"), do: "success"
  def outcome_word("partial_success"), do: "near miss"
  def outcome_word("critical_failure"), do: "critical failure"
  def outcome_word(_), do: "failure"

  defp skill_name(skill), do: skill |> to_string() |> String.replace("_", " ")
end
