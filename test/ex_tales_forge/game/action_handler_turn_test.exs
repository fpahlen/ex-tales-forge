defmodule TalesForge.Game.ActionHandlerTurnTest do
  @moduledoc """
  Playtest-safe turns through the public turn path (`Turn.new/3` then
  `Turn.Premise.check/1` and `Turn.Mechanics.apply/1`) for the action handler.
  No LLM calls: the flags are read from the environment, which CI leaves off.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Context
  alias TalesForge.Game.Intent
  alias TalesForge.Game.Schemas.{IntentExtraction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Table", adventure_id: "tin_valley"})
    %{session: session}
  end

  defp play(session, {text, type, target, params}) do
    extraction = %IntentExtraction{
      overall_intent: text,
      actions: [%SingleAction{action_type: type, target: target, parameters: params}]
    }

    action = Intent.validate_player_action(extraction, Context.build_intent_context(session))

    {session, 1}
    |> Turn.new({text, action}, flags: Turn.read_flags(), role: :playtest)
    |> Turn.Premise.check()
    |> Turn.Mechanics.apply()
  end

  test "a move to an exit takes the move handler", %{session: session} do
    turn = play(session, {"I head out to the market square", :move, "market_square", %{}})
    handler = turn.outcome.handler

    assert {handler.handler, handler.target, handler.notes} ==
             {"move", "market_square", "Move to market_square."}

    assert handler.state_hints == %{"location_id" => "market_square"}
  end

  test "a wait takes the wait handler with its ticks", %{session: session} do
    turn = play(session, {"I wait a while", :wait, nil, %{"ticks" => 3}})
    handler = turn.outcome.handler
    assert {handler.handler, handler.notes} == {"wait", "Wait 3 ticks."}
    assert handler.state_hints == %{"ticks" => 3}
  end

  test "a buy takes the inventory handler", %{session: session} do
    turn = play(session, {"I buy an ale from the innkeeper", :buy, nil, %{"item_id" => "ale"}})
    handler = turn.outcome.handler
    assert {handler.handler, handler.notes} == {"inventory", "Inventory buy."}
    assert handler.state_hints["action_type"] == "buy"
    assert handler.state_hints["parameters"] == %{"item_id" => "ale"}
  end
end
