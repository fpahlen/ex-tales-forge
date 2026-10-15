defmodule TalesForge.Game.QaD100Qa2Test do
  @moduledoc "QA 2026-10-15 (Gentry, sessions 99817343 and e2c7878d)."
  use TalesForge.DataCase, async: true

  alias TalesForge.Game.{Combat, Context, TargetCheck}
  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.Combat, as: TurnCombat
  alias TalesForge.Schemas.GameSession

  @dead_marta %{
    "name" => "Marta Kellen",
    "vitality" => "dead",
    "location_id" => "weary_pilgrim"
  }

  defp session(world), do: %GameSession{id: Ecto.UUID.generate(), world_state: world}

  describe "dead and absent targets" do
    test "an empty present list stays empty and a dead person is never present" do
      ctx =
        Context.build_intent_context(
          session(%{"location_id" => "cellar", "present_npcs" => [], "npc_state" => %{}})
        )

      assert ctx["present_npcs"] == []

      ctx =
        Context.build_intent_context(
          session(%{
            "present_npcs" => ["marta_kellen"],
            "npc_state" => %{"marta_kellen" => @dead_marta}
          })
        )

      assert ctx["present_npcs"] == []
      refute Map.has_key?(ctx["npc_locations"], "marta_kellen")
    end

    test "a social skill at a dead person is blocked" do
      world = %{"present_npcs" => [], "npc_state" => %{"marta_kellen" => @dead_marta}}

      action = %SingleAction{
        action_type: :observe,
        target: "marta_kellen",
        parameters: %{"skill" => "persuasion"}
      }

      assert TargetCheck.reason(world, action) =~ "is dead"
    end

    test "a persuasion at a person who is elsewhere is blocked with the place" do
      world = %{
        "present_npcs" => [],
        "npc_state" => %{
          "worried_merchant" => %{"name" => "Henrik", "location_id" => "market_square"}
        }
      }

      action = %SingleAction{
        action_type: :speak,
        target: "worried_merchant",
        parameters: %{"skill" => "persuasion"}
      }

      reason = TargetCheck.reason(world, action)
      assert reason =~ "Henrik is not here"
      assert reason =~ "Go there first"

      present = Map.put(world, "present_npcs", ["worried_merchant"])
      assert TargetCheck.reason(present, action) == nil
    end
  end

  describe "death roll and fallen section" do
    test "the summary shows the death roll" do
      ex = %{
        "attacker" => "You",
        "defender" => "Marta Kellen",
        "death" => %{"roll" => 83, "kills_above" => 27, "dead" => true}
      }

      assert Combat.death_text(ex) =~ "Death roll: d100 83, above 27 kills: Marta Kellen dies."
      assert Combat.death_text(%{}) == nil
    end

    test "a downed person is in the fallen section" do
      text =
        Combat.fallen_section(%{
          "npc_state" => %{"brenna" => %{"name" => "Brenna", "vitality" => "down"}}
        })

      assert text =~ "Brenna"
    end
  end

  describe "QA forced rolls" do
    test "work only on playtest and only for 1..100" do
      world = %{"qa_rolls" => %{"attack" => 1, "death" => 100, "bogus" => 5}}
      turn = %Turn{session: %GameSession{world_state: world}, role: :playtest}

      assert TurnCombat.qa_rolls(turn) == %{attack: 1, death: 100}
      assert TurnCombat.qa_rolls(%{turn | role: :prod}) == %{}

      bad = %{turn | session: %GameSession{world_state: %{"qa_rolls" => %{"attack" => 0}}}}
      assert TurnCombat.qa_rolls(bad) == %{}
    end
  end
end
