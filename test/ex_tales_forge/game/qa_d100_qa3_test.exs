defmodule TalesForge.Game.QaD100Qa3Test do
  @moduledoc "QA 2026-10-15 retest (Gentry, session 9a1ff8c2, playtest e7cf184)."
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{Combat, Context, Intent, Mechanics, RollLine, TargetCheck}
  alias TalesForge.Game.Schemas.{HandlerResult, IntentExtraction, PlayerAction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions
  alias TalesForgeWeb.PlayComponents

  @flags %{
    turn_outcome_record: true,
    turn_apply_outcomes: false,
    npc_dialogue_memory: false,
    npc_reactions: false,
    world_agents: false,
    turn_premise_first: false,
    turn_state_from_mechanics: false,
    history_strip_injection: false,
    skill_detail_level: false
  }

  @dead_marta %{
    "name" => "Marta Kellen",
    "role" => "barkeep",
    "minor" => true,
    "vitality" => "dead",
    "wounds" => 1,
    "wound_max" => 1,
    "location_id" => "weary_pilgrim"
  }

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "QA", adventure_id: "crossroads_ledger"})

    world =
      session.world_state
      |> Map.put("location_id", "weary_pilgrim")
      |> put_in(["character", "location_id"], "weary_pilgrim")
      |> Map.put("present_npcs", [])
      |> Map.update("npc_state", %{"marta_kellen" => @dead_marta}, fn state ->
        Map.put(state || %{}, "marta_kellen", @dead_marta)
      end)

    %{session: %{session | world_state: world}}
  end

  defp play(session, text, type, target, params \\ %{}) do
    pa = %PlayerAction{
      overall_intent: text,
      action: %SingleAction{action_type: type, target: target, parameters: params}
    }

    session
    |> Turn.new(1, text, pa, flags: @flags, role: :playtest)
    |> Turn.Mechanics.apply()
  end

  describe "a dead person is never present" do
    test "the Present panel drops a dead minor foe and a dead listed person" do
      world = %{
        "location_id" => "weary_pilgrim",
        "present_npcs" => [],
        "npc_state" => %{"marta_kellen" => @dead_marta}
      }

      assert PlayComponents.present_npcs(world) == []

      listed = Map.put(world, "present_npcs", ["marta_kellen"])
      assert PlayComponents.present_npcs(listed) == []

      alive = put_in(world, ["npc_state", "marta_kellen", "vitality"], "hurt")
      assert [%{id: "marta_kellen"}] = PlayComponents.present_npcs(alive)
    end
  end

  describe "the dead get no roll" do
    test "the classifier route: persuasion with no target is blocked", %{session: session} do
      t = play(session, "I persuade Marta", :speak, nil, %{"skill" => "persuasion"})

      assert t.outcome.handler.state_hints["target_rejected"]
      assert t.outcome.handler.state_hints["reason"] =~ "Marta Kellen is dead"
      assert t.outcome.mechanical.roll == nil
    end

    test "the classifier route: a name as the target is blocked", %{session: session} do
      t = play(session, "I persuade Marta", :speak, "Marta", %{"skill" => "persuasion"})
      assert t.outcome.handler.state_hints["target_rejected"]
      assert t.outcome.mechanical.roll == nil
    end

    for {text, type} <- [
          {"I persuade Marta to tell me the truth", :speak},
          {"I lie to Marta about the ledger", :speak},
          {"I intimidate Marta", :other},
          {"I talk to Marta", :speak},
          {"I attack Marta again", :combat},
          {"I trade my knife with Marta", :trade}
        ] do
      test "the fallback route: #{text}", %{session: session} do
        params = %{"skill" => Mechanics.infer_check_skill(unquote(text))}
        t = play(session, unquote(text), unquote(type), nil, params)

        assert t.outcome.handler.state_hints["target_rejected"], unquote(text)
        assert t.outcome.mechanical.roll == nil
      end
    end

    test "looking at the body is no block", %{session: session} do
      t = play(session, "I look at Marta's body", :observe, nil)
      refute t.outcome.handler.state_hints["target_rejected"]
    end

    test "talk about the dead to a living person is no block" do
      world = %{
        "present_npcs" => ["worried_merchant"],
        "npc_state" => %{
          "marta_kellen" => @dead_marta,
          "worried_merchant" => %{"name" => "Henrik", "location_id" => "weary_pilgrim"}
        }
      }

      action = %SingleAction{action_type: :speak, target: "worried_merchant"}
      assert TargetCheck.reason(world, action, "I ask Henrik about Marta") == nil
    end
  end

  describe "persuasion at a person who is elsewhere" do
    test "stays a speak and rolls nothing" do
      context = %{
        "location_id" => "weary_pilgrim",
        "present_npcs" => [],
        "places" => %{
          "weary_pilgrim" => %{"exits" => ["crossroads_square"]},
          "crossroads_square" => %{"name" => "Crossroads Square", "exits" => ["weary_pilgrim"]}
        },
        "npc_locations" => %{
          "worried_merchant" => %{"name" => "Henrik", "location_id" => "crossroads_square"}
        }
      }

      extraction = %IntentExtraction{
        overall_intent: "I persuade Henrik",
        actions: [
          %SingleAction{
            action_type: :speak,
            target: "worried_merchant",
            parameters: %{"skill" => "persuasion"}
          }
        ],
        primary_index: 0,
        confidence: 0.9
      }

      pa = Intent.validate_player_action(extraction, context)
      assert pa.action.action_type == :speak
      assert pa.action.target == "worried_merchant"

      world = %{
        "present_npcs" => [],
        "npc_state" => %{
          "worried_merchant" => %{"name" => "Henrik", "location_id" => "crossroads_square"}
        }
      }

      assert TargetCheck.reason(world, pa.action, "I persuade Henrik") =~ "Henrik is not here"
    end
  end

  describe "a critical miss wounds the attacker" do
    test "the exchange books the self wound" do
      attacker = %{"id" => "player", "name" => "Elara", "skills" => %{"melee_combat" => 10}}
      defender = %{"id" => "marta_kellen", "name" => "Marta Kellen", "skills" => %{"dodge" => 40}}
      rolls = %{attack: 100, counter_chance: 1.0, counter: 99, death: 1}

      ex = Combat.exchange({attacker, defender}, "melee_combat", rolls)
      assert ex["attack"]["result"] == "critical_failure"
      assert ex["self_wound"]
      assert ex["attacker_wounded"]
      assert Combat.summary(ex) =~ "Elara takes 1 wound."

      world = %{"character" => %{"wounds" => 0, "stats" => %{"CON" => 10}}}
      booked = Mechanics.apply_vitality(world, nil, opposed: true, combat: ex)
      assert booked["character"]["wounds"] == 1
    end

    test "a crit miss and a counter hit give two wounds" do
      world = %{"character" => %{"wounds" => 0, "stats" => %{"CON" => 10}}}
      ex = %{"attacker_wounds" => 2, "attacker_wounded" => true}
      booked = Mechanics.apply_vitality(world, nil, opposed: true, combat: ex)
      assert booked["character"]["wounds"] == 2
    end
  end

  describe "a move to the current place" do
    test "go inside the inn while in the inn plays no walk, flag off", %{session: session} do
      t = play(session, "I go inside the inn.", :move, "pilgrim_cellar")

      hints = t.outcome.handler.state_hints
      assert hints["same_place"]
      assert hints["reason"] =~ "already in The Weary Pilgrim"
      assert t.outcome.board.world["location_id"] == "weary_pilgrim"
    end

    test "a move with the current place as the target plays no walk", %{session: session} do
      t = play(session, "I walk over to the bar.", :move, "weary_pilgrim")
      assert t.outcome.handler.state_hints["same_place"]
    end

    test "the cellar of the inn is still a move" do
      world = %{"location_id" => "weary_pilgrim"}

      h = %HandlerResult{
        handler: "move",
        target: "pilgrim_cellar",
        state_hints: %{"location_id" => "pilgrim_cellar"}
      }

      assert TalesForge.Game.TurnApply.same_place(h, world, "I go down to the cellar of the inn").handler ==
               "move"
    end
  end

  describe "nits" do
    test "an exit with no location entry gets a name, not the id" do
      assert Context.place_name("kings_road") == "Kings Road"
    end

    test "the improvement shows the sheet numbers" do
      mech = %{
        "outcome" => "none",
        "improvements" => [
          %{
            "skill" => "melee_combat",
            "improved" => true,
            "raw_skill" => 5,
            "gain" => 5,
            "effective_before" => 10,
            "effective_after" => 15
          }
        ]
      }

      assert RollLine.text(mech) == "Skill improved: melee combat +5 (10 to 15)."
    end

    test "the last exchange shows only at the place of the fight" do
      world = %{
        "location_id" => "crossroads_square",
        "combat_last" => %{"text" => "Attack", "location_id" => "weary_pilgrim"}
      }

      assert PlayComponents.last_exchange(world) == nil
    end
  end
end
