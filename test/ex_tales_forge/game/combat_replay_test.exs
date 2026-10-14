defmodule TalesForge.Game.CombatReplayTest do
  @moduledoc """
  Replays Håkan's Ezzor playtest, Tin Valley turns 27 to 29
  (`test/fixtures/combat/hakan_ezzor_turns_27_29.json`): the stored player
  text and d20, with injected counterattack rolls. The record names the
  right target, and the prose check finds the hits that the GM told without
  a die. Prose that tells the record passes.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.{Combat, ProseCheck}

  @fixture "test/fixtures/combat/hakan_ezzor_turns_27_29.json"
           |> File.read!()
           |> Jason.decode!()

  test "the record and the prose agree for turns 27 to 29" do
    rules = Defaults.rules("tin_valley")
    player = Map.put(@fixture["character"], "id", "player")

    Enum.reduce(@fixture["turns"], @fixture["world"], fn turn, world ->
      attacker = put_in(player, ["skills", "melee_combat"], turn["melee_combat"])

      {defender, foe} =
        case Combat.target(nil, turn["player_action"], world) do
          {:npc, "guild_steward"} ->
            {Map.merge(@fixture["osric"], world["npc_state"]["guild_steward"]), nil}

          {:npc, id} ->
            {world["npc_state"][id], nil}

          {:foe, id, name} ->
            Combat.minor_foe(id, name, rules, 29) |> then(&{&1, &1})
        end

      rolls =
        turn["rolls"]
        |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
        |> Map.put(:attack, turn["attack_roll"])

      ex = Combat.exchange(attacker, defender, "melee_combat", rolls)
      expect = turn["expect"]

      assert ex["defender"] == expect["target"], "turn #{turn["turn"]}"
      assert ex["attack"]["hit"] == expect["attack_hit"], "turn #{turn["turn"]}"

      assert (ex["counter"] && ex["counter"]["hit"]) == expect["counter_hit"],
             "turn #{turn["turn"]}"

      record = %{"combat" => ex}

      assert ProseCheck.check(turn["agreeing_prose"], record) == [],
             "turn #{turn["turn"]}: the agreeing prose tells the record"

      {booked, _events} = Combat.book(world, ex, foe, world["npc_state"])
      booked
    end)
  end

  test "the stored GM prose of turns 27 and 28 tells blood that no die gave" do
    [t27, t28 | _] = @fixture["turns"]

    for turn <- [t27, t28] do
      osric = @fixture["osric"]
      attacker = put_in(@fixture["character"], ["skills", "melee_combat"], turn["melee_combat"])

      ex =
        Combat.exchange(attacker, osric, "melee_combat", %{
          attack: turn["attack_roll"],
          counter_chance: 0.99
        })

      kinds = turn["gm_prose"] |> ProseCheck.check(%{"combat" => ex}) |> Enum.map(& &1.kind)
      assert :wound in kinds, "turn #{turn["turn"]}"
    end
  end

  test "turn 29 targets the miner, not Osric" do
    t29 = List.last(@fixture["turns"])

    assert {:foe, "foe_miner", "a miner"} =
             Combat.target(nil, t29["player_action"], @fixture["world"])
  end
end
