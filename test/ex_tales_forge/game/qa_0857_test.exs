defmodule TalesForge.Game.Qa0857Test do
  @moduledoc """
  Regressions from Gentry's QA of 2026-10-14 08:57 (playtest a1acbe8,
  sessions a1bed2f5 and 6ab77f0f). The fixture is
  test/fixtures/qa/gentry_0857.json.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.{Combat, PremiseCheck, TurnApply, WorldClock}
  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions
  alias TalesForgeWeb.PlayComponents

  @fixture "test/fixtures/qa/gentry_0857.json" |> File.read!() |> Jason.decode!()

  @flags %{
    turn_outcome_record: true,
    npc_dialogue_memory: false,
    npc_reactions: false,
    world_agents: false,
    turn_premise_first: false,
    turn_state_from_mechanics: false,
    history_strip_injection: false,
    skill_detail_level: false,
    combat_opposed: true
  }

  defp fixture_turn(session, n) do
    Enum.find(@fixture["sessions"][session]["turns"], &(&1["turn"] == n))
  end

  defp combat_turn(session, text, target, opts) do
    action = %PlayerAction{
      overall_intent: text,
      action: %SingleAction{
        action_type: :combat,
        target: target,
        parameters: %{"skill" => "melee_combat"}
      }
    }

    {session, 1}
    |> Turn.new({text, action}, Keyword.merge(opts, flags: @flags, role: :playtest))
    |> Turn.Mechanics.apply()
  end

  describe "6ab77f0f combat" do
    setup do
      {:ok, session} = GameSessions.create_session(%{name: "Fight", adventure_id: "tin_valley"})
      %{session: session}
    end

    test "(f) a bare \"I attack\" with a Jev target asks whom", %{session: session} do
      %{"text" => text, "jev" => %{"target" => target}} = fixture_turn("6ab77f0f", 3)
      world = Map.put(session.world_state, "present_npcs", [target])
      session = %{session | world_state: world}

      t = combat_turn(session, text, target, combat_rolls: %{attack: 3})

      assert t.outcome.handler.state_hints["combat_target_unclear"]
      assert t.outcome.mechanical.roll == nil
    end

    test "(f) the Jev target counts when the text refers to the person", %{session: session} do
      world = Map.put(session.world_state, "present_npcs", ["innkeep"])
      scene = {world, TalesForge.Characters.cast(session.id)}

      assert {:npc, "innkeep"} = Combat.target("innkeep", "I attack her", scene)
      assert {:npc, "innkeep"} = Combat.target("innkeep", "I attack the innkeeper", scene)
    end

    test "(e) the miner is a minor foe, and the exchange is in the mechanical resolution",
         %{session: session} do
      %{"text" => text} = fixture_turn("6ab77f0f", 4)

      t =
        combat_turn(session, text, nil,
          combat_rolls: %{attack: 60, counter_chance: 0.0, counter: 1}
        )

      assert t.outcome.combat["defender_id"] == "foe_miner"
      assert t.outcome.board.cast["foe_miner"].minor

      mech = t.outcome.mechanical
      assert mech.outcome == "failure"
      assert mech.combat["defender_id"] == "foe_miner"

      assert mech.notes =~
               ~r/^Attack: d100 60 vs \d+ \(melee_combat \d+, a miner's Parry \d+\): miss\./

      assert mech.notes =~ "Counterattack: d100 1 vs"
      assert MechanicalResolution.encode(mech)["combat"]["defender_id"] == "foe_miner"

      assert t.outcome.board.world["combat_last"]["text"] == mech.notes
    end

    test "(e) a world refresh keeps the minor foes and the NPC wounds", %{session: session} do
      {:ok, plain} = TalesForge.NPC.refresh_session_world_state(session)
      cast = TalesForge.Characters.cast(session.id)
      [npc_id | _] = cast |> Map.keys() |> Enum.sort()
      foe = Combat.minor_foe({"foe_miner", "a miner"}, Defaults.rules("tin_valley"), 7)

      cast =
        cast
        |> Map.put("foe_miner", %{foe | location_id: plain.world_state["location_id"]})
        |> Map.update!(npc_id, &%{&1 | wounds: 1})

      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.put(:session, plain)
        |> TalesForge.Characters.write_multi(cast)
        |> TalesForge.Repo.transaction()

      {:ok, refreshed} = TalesForge.NPC.refresh_session_world_state(plain)
      reloaded = TalesForge.Characters.cast(session.id)

      refute Map.has_key?(refreshed.world_state, "npc_state")
      assert reloaded["foe_miner"].minor
      assert reloaded[npc_id].wounds == 1
    end
  end

  test "(e) the Present panel shows the minor foes and the wounds" do
    world = %{
      "location_id" => "valley_inn",
      "present_npcs" => ["innkeep"],
      "combat_last" => %{"text" => "Attack: d100 3 vs 1: miss."}
    }

    gc = &struct(%TalesForge.GameCharacter{slug: &1}, &2)

    cast = %{
      "innkeep" => gc.("innkeep", name: "Brenna Holt", wounds: 1, wound_max: 3),
      "foe_miner" =>
        gc.("foe_miner",
          name: "a miner",
          minor: true,
          location_id: "valley_inn",
          wounds: 1,
          wound_max: 1,
          vitality: "down"
        ),
      "foe_guard" => gc.("foe_guard", name: "a guard", minor: true, location_id: "inn_yard")
    }

    assert [
             %{id: "innkeep", wounds_label: "1/3 wounds"},
             %{id: "foe_miner", wounds_label: "down · 1/1 wounds"}
           ] = PlayComponents.present_npcs(world, cast)

    assert PlayComponents.last_exchange(world) == "Attack: d100 3 vs 1: miss."
  end

  describe "a1bed2f5 time and price" do
    test "T10 \"I wait until dusk\" waits to dusk" do
      %{"text" => text} = fixture_turn("a1bed2f5", 10)

      handler = %HandlerResult{
        handler: "wait",
        notes: "Wait 4 ticks.",
        state_hints: %{"ticks" => 4}
      }

      # Day 2 · morning
      world = %{"world_tick" => 104}

      waited = TurnApply.wait_until(handler, world, text)

      assert WorldClock.period(104 + waited.state_hints["ticks"]) == "dusk"
      assert waited.notes =~ "until Day 2 · dusk"
    end

    test "T11 \"It's already midnight\" gets a time correction at midday" do
      %{"text" => text} = fixture_turn("a1bed2f5", 11)
      # Day 2 · midday
      world = %{"world_tick" => 96 + 18, "character" => %{"inventory" => []}}

      assert [finding] = PremiseCheck.check(text, PremiseCheck.state(world, world, [], 0))
      assert finding.kind == :time
      assert finding.correction =~ "Player claims it is midnight; the clock says Day 2 · midday."

      night = %{world | "world_tick" => 96 + 72}
      assert PremiseCheck.check(text, PremiseCheck.state(night, night, [], 0)) == []
    end

    test "T12 the room price in the turn data is the server price" do
      %{"text" => text} = fixture_turn("a1bed2f5", 12)
      handler = %HandlerResult{handler: "inventory", notes: nil}
      world = %{"location_id" => "weary_pilgrim"}

      assert TurnApply.service_prices(handler, world, text).notes =~
               "a room for the night costs 3 silver (30c)"

      assert TurnApply.spend_copper("I pay for a room") == 30
    end

    test "the premise correction lists each carried item once" do
      items = [
        %{"id" => "travel_cloak", "name" => "travel cloak", "quantity" => 1},
        %{"id" => "hunting_knife", "name" => "hunting knife", "quantity" => 1}
      ]

      before = %{"character" => %{"inventory" => items}}
      after_turn = %{"character" => %{"inventory" => items}}

      [finding] =
        PremiseCheck.check(
          "I put on my enchanted armor.",
          PremiseCheck.state(before, after_turn, [], 0)
        )

      assert finding.correction =~ "(they carry: travel cloak, hunting knife)"
    end
  end
end
