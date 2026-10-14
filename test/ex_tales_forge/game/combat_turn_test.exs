defmodule TalesForge.Game.CombatTurnTest do
  @moduledoc "The opposed combat steps in the turn pipe (COMBAT_OPPOSED=on)."
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

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

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Fight", adventure_id: "tin_valley"})
    %{session: session}
  end

  defp turn(session, text, opts \\ []) do
    action = %PlayerAction{
      overall_intent: text,
      action: %SingleAction{
        action_type: :combat,
        target: Keyword.get(opts, :target),
        parameters: Map.merge(%{"skill" => "melee_combat"}, Keyword.get(opts, :params, %{}))
      }
    }

    flags = Map.merge(@flags, Keyword.get(opts, :flags, %{}))

    session
    |> Turn.new(1, text, action, Keyword.merge(opts, flags: flags, role: :playtest))
    |> Turn.Mechanics.apply()
  end

  test "an unclear target rolls nothing and the turn asks the player", %{session: session} do
    t = turn(session, "I lash out wildly")

    assert t.outcome.handler.state_hints["combat_target_unclear"]
    assert t.outcome.handler.state_hints["rejected"]
    assert t.outcome.mechanical.roll == nil
    assert %{"target_unclear" => _names} = t.outcome.combat

    prompt = t |> Turn.Npcs.react() |> Turn.Notice.select() |> Turn.Prompt.build()
    text = prompt.prompt.messages |> Enum.map_join("\n", & &1.content)
    assert text =~ "Ask the player whom the character attacks"
  end

  test "an attack on a person outside the world data makes a minor foe", %{session: session} do
    t = turn(session, "I attack the miner", combat_rolls: %{attack: 1})

    assert %{"defender" => "a miner", "minor" => true, "defender_vitality" => "down"} =
             t.outcome.combat

    world = t.outcome.board.world
    assert world["npc_state"]["foe_miner"]["vitality"] == "down"
    assert Enum.any?(t.outcome.board.events, &(&1["kind"] == "npc.down"))
    assert t.outcome.board.outcome["combat"]["defender_id"] == "foe_miner"
    assert world["character"]["wounds"] in [0, nil]

    prompt = t |> Turn.Npcs.react() |> Turn.Notice.select() |> Turn.Prompt.build()
    text = prompt.prompt.messages |> Enum.map_join("\n", & &1.content)
    assert text =~ "## Combat exchange (rolled by the server)"
    assert text =~ "The target is a miner."
  end

  test "a miss with no counterattack gives the player no wound", %{session: session} do
    t = turn(session, "I attack the miner", combat_rolls: %{attack: 20, counter_chance: 0.99})

    refute t.outcome.combat["attack"]["hit"]
    assert t.outcome.combat["counter"] == nil
    assert t.outcome.board.world["character"]["wounds"] in [0, nil]
  end

  test "with the flag off, the turn has no exchange", %{session: session} do
    t = turn(session, "I attack the miner", flags: %{combat_opposed: false})

    assert t.outcome.combat == nil
    refute Map.has_key?(t.outcome.board.outcome, "combat")
  end

  describe "d100 bands (QA 2026-10-14 21:15)" do
    test "the outcome keeps the band of the attack roll", %{session: session} do
      t = turn(session, "I attack the miner", combat_rolls: %{attack: 100, counter_chance: 0.99})
      assert t.outcome.combat["attack"]["result"] == "critical_failure"
      assert t.outcome.mechanical.outcome == "critical_failure"
      assert t.outcome.mechanical.notes =~ "critical miss"
    end

    test "a roll just above the target is a near miss", %{session: session} do
      t = turn(session, "I attack the miner", combat_rolls: %{attack: 2, counter_chance: 0.99})
      target = t.outcome.combat["attack"]["target"]

      t =
        turn(session, "I attack the miner",
          combat_rolls: %{attack: target + 1, counter_chance: 0.99}
        )

      assert t.outcome.mechanical.outcome == "partial_success"
      refute t.outcome.combat["attack"]["hit"]
      assert t.outcome.mechanical.notes =~ "near miss"
    end
  end

  test "a person picked from the whom question is the target", %{session: session} do
    world = session.world_state
    [npc_id | _] = world["present_npcs"]

    t =
      turn(session, "I attack",
        target: npc_id,
        params: %{"target_chosen" => true},
        combat_rolls: %{attack: 1, counter_chance: 0.99}
      )

    refute t.outcome.handler.state_hints["combat_target_unclear"]
    assert t.outcome.combat["defender_id"] == npc_id
  end
end
