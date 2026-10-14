defmodule TalesForge.Game.RollLineTest do
  @moduledoc "The roll line under the GM text (QA 2026-10-14 21:15)."
  use ExUnit.Case, async: true

  alias TalesForge.Game.RollLine

  doctest RollLine
  doctest TalesForge.Game.Inventory, only: [normalize_coins: 1]
  doctest TalesForge.Game.JevIntent, only: [text_skill: 2]

  test "a combat turn shows the exchange with its band and the improvement" do
    mechanical = %{
      "skill" => "melee_combat",
      "roll" => 14,
      "outcome" => "partial_success",
      "combat" => %{
        "attacker" => "Elara Voss",
        "defender" => "Marta Kellen",
        "attack" => %{
          "skill" => "melee_combat",
          "level" => 10,
          "parry" => 52,
          "target" => 8,
          "roll" => 14,
          "hit" => false,
          "result" => "partial_success"
        },
        "defender_wounds" => 0,
        "defender_wound_max" => 3,
        "defender_vitality" => "ok",
        "counter" => nil
      },
      "improvements" => [
        %{
          "skill" => "melee_combat",
          "roll" => 77,
          "raw_skill" => 5,
          "improved" => true,
          "gain" => 6
        }
      ]
    }

    assert RollLine.text(mechanical) ==
             "Attack: d100 14 vs 8 (melee_combat 10, Marta Kellen's Parry 52): near miss. " <>
               "Marta Kellen: 0/3 wounds. No counterattack. Skill improved: melee combat +6 (5 to 11)."
  end

  test "a failed improvement roll adds no marker" do
    mechanical = %{
      "skill" => "climbing",
      "roll" => 85,
      "effective_skill" => 20,
      "outcome" => "failure",
      "improvements" => [
        %{"skill" => "climbing", "roll" => 47, "raw_skill" => 0, "improved" => false}
      ]
    }

    assert RollLine.text(mechanical) == "Climbing: d100 85 vs 20: failure."
  end
end
