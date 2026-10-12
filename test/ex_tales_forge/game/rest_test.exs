defmodule TalesForge.Game.RestTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.{ActionHandler, Intent, JevIntent, Rest}
  alias TalesForge.Game.Schemas.PlayerAction

  doctest TalesForge.Game.Rest

  @square_world %{
    "location_id" => "crossroads_square",
    "locations" => %{
      "crossroads_square" => %{
        "name" => "Crossroads Square",
        "blurb" => "Mud and cobbles churned by cart wheels.",
        "fixtures" => ["signpost", "merchant stalls"]
      },
      "weary_pilgrim" => %{
        "name" => "The Weary Pilgrim",
        "blurb" => "A low-ceilinged tavern smelling of woodsmoke and spilled ale."
      },
      "valley_inn" => %{"name" => "Valley Inn", "aliases" => ["the inn"]},
      "mine_workings" => %{"name" => "Mine Workings", "fixtures" => ["cot"]}
    }
  }

  defp sleep_handler(text) do
    %PlayerAction{
      overall_intent: text,
      action: %TalesForge.Game.Schemas.SingleAction{action_type: :wait, parameters: %{}}
    }
    |> ActionHandler.resolve()
    |> Rest.apply(@square_world, text)
  end

  describe "rest places" do
    test "an inn, a tavern and a place with a cot are rest places" do
      assert Rest.rest_place?(@square_world, "weary_pilgrim")
      assert Rest.rest_place?(@square_world, "valley_inn")
      assert Rest.rest_place?(@square_world, "mine_workings")
    end

    test "a square is not a rest place" do
      refute Rest.rest_place?(@square_world, "crossroads_square")
      refute Rest.rest_place?(@square_world, nil)
    end

    test "the default Crossroads locations are read when the world has no locations" do
      assert Rest.rest_place?(%{}, "weary_pilgrim")
      refute Rest.rest_place?(%{}, "crossroads_square")
    end
  end

  describe "a sleep request" do
    test "in the square is a short wait and the GM is told there is no bed" do
      handler = sleep_handler("I go to sleep")
      assert ActionHandler.tick_delta(handler) == 4
      assert handler.notes =~ "no bed here"
      assert handler.notes =~ "Crossroads Square"
    end

    test "with hours in the square is also a short wait" do
      assert ActionHandler.tick_delta(sleep_handler("I sleep for eight hours")) == 4
    end

    test "at the tavern is a long sleep of eight hours" do
      world = Map.put(@square_world, "location_id", "weary_pilgrim")

      handler =
        %PlayerAction{
          overall_intent: "I go to sleep",
          action: %TalesForge.Game.Schemas.SingleAction{action_type: :wait, parameters: %{}}
        }
        |> ActionHandler.resolve()
        |> Rest.apply(world, "I go to sleep")

      assert ActionHandler.tick_delta(handler) == 32
    end

    test "a plain wait with hours does not change" do
      assert ActionHandler.tick_delta(sleep_handler("I wait eight hours")) == 32
    end
  end

  describe "pay for a room and sleep" do
    test "Jev's wait reading becomes a payment now and a wait later" do
      text = "I pay for a room and go to sleep."

      reply = %{
        action: :wait,
        target: :none,
        skill: :none,
        later: :none,
        later_target: :none,
        safety: :benign,
        confidence: %{action: 0.9, safety: 0.95}
      }

      reading = JevIntent.decode(reply, [], text: text, context: %{})

      assert reading.action == :spend
      assert reading.later == :wait
      assert [%{action_type: :spend}, %{action_type: :wait}] = reading.extraction.actions
    end

    test "a purchase stays a purchase and gets the sleep as the later action" do
      reply = %{action: :buy, later: :none, safety: :benign}
      reading = JevIntent.decode(reply, [], text: "I rent a bed and turn in", context: %{})
      assert reading.action == :buy
      assert reading.later == :wait
    end

    test "a message that is not benign does not change" do
      reply = %{action: :wait, later: :none, safety: :prompt_injection}
      reading = JevIntent.decode(reply, [], text: "I pay for a room and sleep", context: %{})
      assert reading.action == :wait
      assert reading.later == nil
    end

    test "the heuristic reads it as a payment now and a wait later" do
      extraction =
        Intent.heuristic_intent("I pay for a room and go to sleep.", %{
          "location_id" => "crossroads_square",
          "exits" => ["weary_pilgrim"],
          "exit_names" => %{"weary_pilgrim" => "The Weary Pilgrim"},
          "present_npcs" => [],
          "npc_details" => %{}
        })

      assert [%{action_type: :spend}, %{action_type: :wait}] = extraction.actions
    end
  end
end
