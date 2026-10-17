defmodule TalesForge.Game.MechanicsTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction, SingleAction}

  doctest Mechanics,
    only: [
      growth_lp: 1,
      normalize_skill_name: 1,
      resolve_check_skill: 3,
      split_levels: 3
    ]

  @character %{
    "stats" => %{"STR" => 10, "DEX" => 10, "WIS" => 12, "CHA" => 14},
    "skills" => %{
      "insight" => 10,
      "persuasion" => 15,
      "climbing" => 15,
      "melee_combat" => 5
    },
    "learning_points" => %{},
    "learning_failures" => %{}
  }

  test "wound_max is 3 plus half CON above 10, minimum 1" do
    assert Mechanics.wound_max(%{"stats" => %{"CON" => 18}}) == 7
    assert Mechanics.wound_max(%{"stats" => %{"CON" => 10}}) == 3
    assert Mechanics.wound_max(%{"stats" => %{"CON" => 11}}) == 3
    assert Mechanics.wound_max(%{"stats" => %{"CON" => 3}}) == 1
    assert Mechanics.wound_max(%{}) == 3
  end

  describe "the untrained floor" do
    test "is max(stat div 3, the stat bonus)" do
      assert Mechanics.untrained_floor(3) == 5
      assert Mechanics.untrained_floor(10) == 15
      assert Mechanics.untrained_floor(14) == 20
      assert Mechanics.untrained_floor(18) == 30
    end

    test "an untrained skill (level 0) rolls against stat div 3" do
      # stealth is DEX 10: untrained it is 5 × (10 div 3) = 15, not 0
      {_c, r} = Mechanics.perform_and_apply(@character, "stealth", roll: 3)
      assert {r.effective_skill, r.outcome} == {15, "success"}
      assert r.notes =~ "vs stealth 15 (untrained: stat ÷ 3)"
    end

    test "a trained skill uses level + stat bonus, even below the untrained level" do
      # melee_combat 5 with STR 10 is 5 + 0 = 5: every level counts, no floor
      {_c, low} = Mechanics.perform_and_apply(@character, "melee_combat", roll: 10)
      assert low.effective_skill == 5
      assert low.notes =~ "vs melee_combat 5 (base 5)"

      # persuasion 15 with CHA 14 is 15 + 10 = 25
      {_c, high} = Mechanics.perform_and_apply(@character, "persuasion", roll: 10)
      assert high.effective_skill == 25
    end
  end

  test "perform_and_apply returns a resolution and banks LP only on a miss" do
    {updated, resolution} = Mechanics.perform_and_apply(@character, "insight")

    assert resolution.skill == "insight"
    assert resolution.roll in 1..100

    assert resolution.outcome in ~w(critical_success success partial_success failure critical_failure)

    expected = if resolution.outcome in ~w(failure partial_success), do: 1.0, else: 0
    assert Map.get(updated["learning_points"], "insight", 0) == expected
  end

  describe "learn only from failure, only in that skill" do
    test "a failure banks one chance, counted as a failure" do
      {updated, resolution} = Mechanics.perform_and_apply(@character, "insight", roll: 80)

      assert resolution.outcome == "failure"
      assert resolution.lp_awarded == 1.0
      assert updated["learning_points"] == %{"insight" => 1.0}
      assert Map.get(updated["learning_failures"], "insight") == 1
      assert resolution.notes =~ "banked improvement chance"
    end

    test "a partial success banks one chance" do
      {updated, resolution} = Mechanics.perform_and_apply(@character, "insight", roll: 20)

      assert resolution.outcome == "partial_success"
      assert resolution.lp_awarded == 1.0
      assert updated["learning_points"] == %{"insight" => 1.0}
    end

    test "a success earns nothing, critical success included, and leaves the sheet alone" do
      for {roll, outcome} <- [{1, "critical_success"}, {2, "critical_success"}, {10, "success"}] do
        {updated, resolution} = Mechanics.perform_and_apply(@character, "insight", roll: roll)

        assert resolution.outcome == outcome
        assert resolution.lp_awarded == 0.0
        assert updated["learning_points"] == %{}
        assert updated["learning_failures"] == %{}
      end
    end

    test "the linked stat adds no LP" do
      # persuasion is CHA 14, which gave +1 LP per roll before 2026-10-09
      {updated, resolution} = Mechanics.perform_and_apply(@character, "persuasion", roll: 80)

      assert resolution.lp_awarded == 1.0
      assert updated["learning_points"]["persuasion"] == 1.0
    end

    test "a failed check through apply_server_mechanics banks for that skill only" do
      character = put_in(@character, ["learning_points", "melee_combat"], 0.5)

      {updated, resolution} =
        Mechanics.apply_server_mechanics(
          character,
          %PlayerAction{
            overall_intent: "climb",
            action: %SingleAction{action_type: :interact, parameters: %{"skill" => "climbing"}}
          },
          %HandlerResult{handler: "skill_check", skill: "climbing"}
        )

      expected = if resolution.outcome in ~w(failure partial_success), do: 1.0, else: nil
      assert updated["learning_points"]["climbing"] == expected
      assert updated["learning_points"]["melee_combat"] == 0.5
    end
  end

  test "move wait inventory train skip a check even when parameters carry a skill" do
    Enum.each(["wait", "inventory", "train"], fn handler ->
      {_character, result} = apply_with_skill(handler, "climbing")
      assert %MechanicalResolution{outcome: "none"} = result
      assert Mechanics.resolve_check_skill(handler, "climbing", "climbing") == nil
    end)

    # A move rolls only to sneak or to climb (QA 2026-10-14 21:15).
    {_character, result} = apply_with_skill("move", "insight")
    assert %MechanicalResolution{outcome: "none"} = result
    assert Mechanics.resolve_check_skill("move", "climbing", "climbing") == "climbing"

    {character, _result} = apply_with_skill("wait", "climbing")
    assert character["learning_points"] == %{}
    assert character["learning_failures"] == %{}
  end

  test "move handler skips skill check" do
    player_action = %PlayerAction{
      overall_intent: "go outside",
      action: %SingleAction{
        action_type: :move,
        target: "crossroads_square"
      }
    }

    handler = %HandlerResult{handler: "move", target: "crossroads_square"}

    {_character, result} = Mechanics.apply_server_mechanics(@character, player_action, handler)
    assert %MechanicalResolution{outcome: "none"} = result
  end

  test "climbing failure does not increment melee_combat LP or failures" do
    character =
      @character
      |> put_in(["learning_points", "melee_combat"], 1.5)
      |> put_in(["learning_failures", "melee_combat"], 2)

    {updated, resolution} = Mechanics.perform_and_apply(character, "climbing", roll: 80)

    assert resolution.skill == "climbing"
    assert resolution.outcome == "failure"
    assert Map.get(updated["learning_points"], "climbing") == 1.0
    assert Map.get(updated["learning_failures"], "climbing") == 1
    assert Map.get(updated["learning_points"], "melee_combat") == 1.5
    assert Map.get(updated["learning_failures"], "melee_combat") == 2
  end

  defp apply_with_skill(handler, skill) do
    player_action = %PlayerAction{
      overall_intent: "act",
      action: %SingleAction{
        action_type: :other,
        parameters: %{"skill" => skill}
      }
    }

    handler = %HandlerResult{handler: handler, skill: skill}
    Mechanics.apply_server_mechanics(@character, player_action, handler)
  end
end
