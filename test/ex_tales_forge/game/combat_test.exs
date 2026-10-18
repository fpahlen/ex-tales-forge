defmodule TalesForge.Game.CombatTest do
  @moduledoc "Opposed combat rolls with injected dice (COMBAT_OPPOSED, card e6a933d4)."
  use ExUnit.Case, async: true

  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.{Combat, Mechanics, ProseCheck}
  alias TalesForge.Game.Schemas.MechanicalResolution
  alias TalesForge.GameCharacter

  doctest TalesForge.Game.Combat

  # The fighters below are sheets, as the turn has them; Combat takes the
  # GameCharacter of each one (refactor step 10c).
  defp f(%GameCharacter{} = gc), do: gc
  defp f(sheet), do: GameCharacter.from_sheet(sheet)

  # Melee 40 (STR 10), Dodge 20 (DEX 10): Parry 60.
  @player %{
    "id" => "player",
    "name" => "Ezzor",
    "stats" => %{"STR" => 10, "DEX" => 10, "CON" => 10},
    "skills" => %{"melee_combat" => 40, "dodge" => 20}
  }

  # A guard: melee 40, low agreeableness, duty concern. Parry 57 (untrained dodge floor 15).
  @guard %{
    "id" => "gate_guard",
    "name" => "Gate Guard",
    "stats" => %{"STR" => 10, "DEX" => 10, "CON" => 10},
    "skills" => %{"melee_combat" => 40},
    "ocean" => %{"agreeableness" => 3, "extraversion" => 6, "neuroticism" => 4},
    "maslow" => "safety",
    "concerns" => [%{"focus" => "duty", "priority" => 5}]
  }

  # A scared shopkeeper: no combat skill, high neuroticism, safety concern.
  @shopkeeper %{
    "id" => "shopkeeper",
    "name" => "Marta",
    "stats" => %{"STR" => 9, "DEX" => 10, "CON" => 9},
    "skills" => %{"persuasion" => 40},
    "ocean" => %{"agreeableness" => 7, "extraversion" => 4, "neuroticism" => 8},
    "maslow" => "safety",
    "concerns" => [%{"focus" => "safety", "priority" => 8}]
  }

  describe "parry/1 and attack_target/2" do
    test "Parry is Dodge/2 + 50 + 5 × (DEX - 10)/2" do
      assert Combat.parry(f(@player)) == 60
      assert Combat.parry(f(%{"stats" => %{"DEX" => 15}, "skills" => %{"dodge" => 20}})) == 75
    end

    test "an untrained fighter uses the untrained floor" do
      {_skill, level} = Combat.combat_skill(f(@shopkeeper))
      assert level == Mechanics.effective_level(@shopkeeper, "melee_combat")
      assert level == 15
    end
  end

  describe "exchange/3" do
    test "a hit gives the defender one wound, and the attacker takes no wound" do
      ex =
        Combat.exchange({f(@player), f(@guard)}, "melee_combat", %{
          attack: 20,
          counter_chance: 0.99
        })

      assert ex["attack"]["parry"] == 57
      assert ex["attack"]["target"] == 33
      assert ex["attack"]["hit"]
      assert ex["defender_wounds"] == 1
      assert ex["defender_vitality"] == "hurt"
      assert ex["counter"] == nil
      refute ex["attacker_wounded"]
    end

    test "a miss with no counterattack is only a miss" do
      ex =
        Combat.exchange({f(@player), f(@shopkeeper)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.9
        })

      refute ex["attack"]["hit"]
      assert ex["defender_wounds"] == 0
      assert ex["counter"] == nil
      refute ex["attacker_wounded"]
    end

    test "a miss where the counterattack hits wounds the attacker" do
      ex =
        Combat.exchange({f(@player), f(@guard)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.1,
          counter: 25
        })

      refute ex["attack"]["hit"]
      assert %{"hit" => true, "parry" => 60, "target" => 30, "roll" => 25} = ex["counter"]
      assert ex["attacker_wounded"]
    end

    test "a counterattack that misses gives no wound" do
      ex =
        Combat.exchange({f(@player), f(@guard)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.1,
          counter: 35
        })

      assert %{"hit" => false} = ex["counter"]
      refute ex["attacker_wounded"]
    end

    test "an NPC at the cap goes down and does not counterattack" do
      cap = Mechanics.wound_max(f(@guard))
      guard = Map.put(@guard, "wounds", cap - 1)

      ex =
        Combat.exchange({f(@player), f(guard)}, "melee_combat", %{
          attack: 10,
          counter_chance: 0.0,
          counter: 1
        })

      assert ex["defender_wounds"] == cap
      assert ex["defender_vitality"] == "down"
      assert ex["counter"] == nil
      refute ex["attacker_wounded"]
    end

    test "a hit on a down NPC makes the death roll from combat.md" do
      cap = Mechanics.wound_max(f(@guard))
      down = Map.merge(@guard, %{"wounds" => cap, "vitality" => "down"})

      assert Combat.exchange({f(@player), f(down)}, "melee_combat", %{attack: 10, death: 30})[
               "defender_vitality"
             ] ==
               "dead"

      assert Combat.exchange({f(@player), f(down)}, "melee_combat", %{attack: 10, death: 25})[
               "defender_vitality"
             ] ==
               "down"
    end

    test "a hit wounds an NPC by the player character's rule (Mechanics.wound/2)" do
      guard = f(@guard)

      for {wounds, death} <- [{0, 50}, {2, 50}, {3, 10}, {3, 90}, {-1, 50}] do
        ex =
          Combat.exchange({f(@player), %{guard | wounds: wounds}}, "melee_combat", %{
            attack: 10,
            death: death
          })

        pc_rule = Mechanics.wound(%{guard | wounds: wounds, vitality: "ok"}, death)

        assert {ex["defender_wounds"], ex["defender_vitality"]} ==
                 {pc_rule.wounds, pc_rule.vitality}
      end

      # Wounds below 0 count as 0 for everyone (10c-b; the NPC path used to give 0).
      ex = Combat.exchange({f(@player), %{guard | wounds: -1}}, "melee_combat", %{attack: 10})
      assert {ex["defender_wounds"], ex["defender_vitality"]} == {1, "hurt"}
    end

    test "the attacker id is the attacker's own, with no \"player\" default (10c-c)" do
      rolls = %{attack: 50, counter_chance: 0.99}
      elara = Map.put(@player, "id", "elara_voss")

      assert Combat.exchange({f(elara), f(@guard)}, nil, rolls)["attacker_id"] == "elara_voss"
      assert Combat.exchange({f(@guard), f(elara)}, nil, rolls)["attacker_id"] == "gate_guard"

      assert Combat.exchange({f(Map.delete(elara, "id")), f(@guard)}, nil, rolls)["attacker_id"] ==
               nil
    end

    test "a minor foe has 1 wound and goes down on the first hit" do
      foe = Combat.minor_foe({"foe_miner", "a miner"}, Defaults.rules("tin_valley"), 7)

      assert %GameCharacter{skills: %{}, minor: true, role: "minor foe"} = foe
      assert Mechanics.wound_max(f(foe)) == 1
      ex = Combat.exchange({f(@player), f(foe)}, "melee_combat", %{attack: 15})
      assert ex["defender_vitality"] == "down"
      assert ex["minor"]
    end

    test "a roll of 1 always hits and a critical failure always misses" do
      assert Combat.hit?(1, 1)
      refute Combat.hit?(100, 99)
      refute Combat.hit?(96, 50)
    end
  end

  describe "counter_chance/1" do
    test "a guard fights back most of the time, a scared shopkeeper often does not" do
      assert Combat.counter_chance(f(@guard)) >= 0.7
      assert Combat.counter_chance(f(@shopkeeper)) <= 0.3
    end

    test "wounds lower the chance, and the chance stays from 0.05 to 0.95" do
      assert Combat.counter_chance(f(Map.put(@guard, "wounds", 2))) <
               Combat.counter_chance(f(@guard))

      for npc <- [
            Map.put(@shopkeeper, "wounds", 9),
            put_in(@guard, ["skills", "melee_combat"], 40)
          ] do
        chance = Combat.counter_chance(f(npc))
        assert chance >= 0.05 and chance <= 0.95
      end
    end

    test "the current concern counts" do
      calm = Map.put(@shopkeeper, "concerns", [])

      assert Combat.counter_chance(f(Map.put(calm, "current_concern", %{"focus" => "revenge"}))) >
               Combat.counter_chance(f(calm))
    end
  end

  describe "target/3" do
    @world %{"location_id" => "market_square", "present_npcs" => ["guild_steward", "innkeep"]}

    defp member(slug, fields), do: struct(%GameCharacter{slug: slug}, fields)

    defp cast do
      %{
        "guild_steward" => member("guild_steward", name: "Osric Vane"),
        "innkeep" => member("innkeep", name: "Brenna Holt")
      }
    end

    test "the Jev target id or a name in the text gives the NPC" do
      assert Combat.target("innkeep", "I punch her", {@world, cast()}) == {:npc, "innkeep"}
      assert Combat.target(nil, "I stab Brenna", {@world, cast()}) == {:npc, "innkeep"}
    end

    test "an unclear target asks the player with the names of the people here" do
      assert Combat.target(nil, "I swing my knife wildly", {@world, cast()}) ==
               {:unclear, ["Osric Vane", "Brenna Holt"]}
    end

    test "a person who is not in the world data becomes a minor foe" do
      assert Combat.target(nil, "I attack the miners", {@world, cast()}) ==
               {:foe, "foe_miner", "a miner"}
    end

    test "a minor foe in the scene is found again by its word" do
      foe = member("foe_miner", name: "a miner", minor: true, location_id: "market_square")
      cast = Map.put(cast(), "foe_miner", foe)

      assert Combat.target(nil, "I hit the miner again", {@world, cast}) == {:npc, "foe_miner"}
    end

    test "a dead NPC is not a target" do
      cast = put_in(cast()["guild_steward"].vitality, "dead")
      assert Combat.target(nil, "I stab Osric", {@world, cast}) == {:unclear, ["Brenna Holt"]}
    end
  end

  describe "book/3" do
    @at %{"location_id" => "market_square", "world_tick" => 40}

    test "wounds go to the defender's character, and going down emits npc.down" do
      cast = %{"gate_guard" => %GameCharacter{slug: "gate_guard", name: "Gate Guard"}}
      guard = Map.put(@guard, "wounds", Mechanics.wound_max(f(@guard)) - 1)
      ex = Combat.exchange({f(@player), f(guard)}, "melee_combat", %{attack: 10})

      {cast, [event]} = Combat.book(cast, @at, {ex, nil})
      assert cast["gate_guard"].vitality == "down"
      assert cast["gate_guard"].wounds == ex["defender_wounds"]
      assert event["kind"] == "npc.down"
      assert event["payload"]["session_only"]
    end

    test "a death emits npc.dead and stays on the character" do
      down = Map.merge(@guard, %{"wounds" => 3, "vitality" => "down"})

      cast = %{
        "gate_guard" => %GameCharacter{slug: "gate_guard", wounds: 3, vitality: "down"}
      }

      ex = Combat.exchange({f(@player), f(down)}, "melee_combat", %{attack: 10, death: 100})

      {cast, [event]} = Combat.book(cast, @at, {ex, nil})
      assert event["kind"] == "npc.dead"
      assert cast["gate_guard"].vitality == "dead"
    end

    test "a new minor foe joins the cast at the place of the fight, for the scene" do
      foe = Combat.minor_foe({"foe_miner", "a miner"}, Defaults.rules("tin_valley"), 7)
      ex = Combat.exchange({f(@player), foe}, "melee_combat", %{attack: 10, death: 100})

      {cast, _events} = Combat.book(%{}, @at, {ex, foe})

      assert %GameCharacter{minor: true, lifetime: :scene, location_id: "market_square"} =
               cast["foe_miner"]

      assert cast["foe_miner"].vitality == ex["defender_vitality"]
    end
  end

  describe "the prompt section" do
    test "lists who attacked whom, both rolls, the results and the wounds" do
      ex =
        Combat.exchange({f(@player), f(@guard)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.1,
          counter: 25
        })

      text = Combat.prompt_section(ex)

      assert text =~ "Ezzor attacks Gate Guard"
      assert text =~ "d100 75 against 33. Miss."
      assert text =~ "Gate Guard counterattacks Ezzor"
      assert text =~ "d100 25 against 30. Hit: Ezzor takes 1 wound."
      assert text =~ "Gate Guard: 0 of 3 wounds"
      assert text =~ "The target is Gate Guard."
    end

    test "an unclear target asks the player" do
      assert Combat.prompt_section(%{"target_unclear" => ["Osric Vane"]}) =~ "Ask the player whom"
    end
  end

  describe "Mechanics.apply_vitality/3 with opposed combat" do
    @failure %MechanicalResolution{outcome: "failure", skill: "melee_combat", roll: 15}

    test "a failed attack gives no wound without a counterattack hit" do
      world = %{"character" => %{"stats" => %{"CON" => 10}, "wounds" => 0}}

      ex =
        Combat.exchange({f(@player), f(@shopkeeper)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.9
        })

      assert Mechanics.apply_vitality(world, @failure, opposed: true, combat: ex)["character"][
               "wounds"
             ] == 0

      assert Mechanics.apply_vitality(world, @failure)["character"]["wounds"] == 1
    end

    test "a counterattack hit gives the player one wound" do
      world = %{"character" => %{"stats" => %{"CON" => 10}, "wounds" => 0}}

      ex =
        Combat.exchange({f(@player), f(@guard)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.1,
          counter: 2
        })

      assert Mechanics.apply_vitality(world, @failure, opposed: true, combat: ex)["character"][
               "wounds"
             ] == 1
    end
  end

  describe "ProseCheck :wound" do
    test "blood on a foe that the attack missed is a bug" do
      ex =
        Combat.exchange({f(@player), f(@guard)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.9
        })

      record = %{"combat" => ex}

      assert [%{kind: :wound}] =
               ProseCheck.check("Blood wells from a cut on the guard's arm.", record)

      assert ProseCheck.check("The guard steps back from the blade.", record) == []
    end

    test "a strike on the character with no counterattack hit is a bug" do
      ex =
        Combat.exchange({f(@player), f(@guard)}, "melee_combat", %{
          attack: 75,
          counter_chance: 0.9
        })

      assert [%{kind: :wound, detail: "character: " <> _}] =
               ProseCheck.check("He drives a fist into your ribs.", %{"combat" => ex})
    end

    test "without a combat exchange in the record, the check adds no wound kind" do
      assert ProseCheck.check("Blood everywhere.", %{}) == []
    end
  end
end
