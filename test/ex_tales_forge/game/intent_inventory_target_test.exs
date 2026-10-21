defmodule TalesForge.Game.IntentInventoryTargetTest do
  @moduledoc """
  Characterization of the heuristic intent's target for inventory-type
  actions (`Intent.inventory_target/3`), before round 2 PR 2. Each case
  plays the text through the public turn path with no LLM calls:
  `Intent.heuristic_intent/2`, `Intent.validate_player_action/2`, then
  `Turn.new/3`, `Turn.Premise.check/1` and `Turn.Mechanics.apply/1`.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Context
  alias TalesForge.Game.Intent
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Target", adventure_id: "tin_valley"})
    %{session: session}
  end

  defp play(session, text) do
    context = Context.build_intent_context(session)
    extraction = Intent.heuristic_intent(text, context)
    action = Intent.validate_player_action(extraction, context)

    turn =
      {session, 1}
      |> Turn.new({text, action}, flags: Turn.read_flags(), role: :playtest)
      |> Turn.Premise.check()
      |> Turn.Mechanics.apply()

    [raw | _] = extraction.actions
    {raw, turn.outcome.handler}
  end

  # {text, action type, target, parameters, handler, handler target}, from main
  @cases [
    {"I buy an ale from Brenna", :buy, "innkeep",
     %{"item_id" => "ale_mug", "npc_id" => "innkeep", "price_copper" => 2, "quantity" => 1},
     "inventory", "innkeep"},
    {"I drop my hunting knife", :drop, "hunting_knife",
     %{"item_id" => "hunting_knife", "quantity" => 1}, "inventory", "hunting_knife"},
    {"I sell my hunting knife to Brenna", :sell, "innkeep",
     %{"item_id" => "hunting_knife", "npc_id" => "innkeep", "quantity" => 1}, "inventory",
     "innkeep"},
    {"I pick up the mug", :pickup, nil, %{"quantity" => 1}, "inventory", nil},
    {"I tip Brenna two copper", :spend, "innkeep", %{"amount_copper" => 0}, "inventory",
     "innkeep"},
    {"I ask Brenna to train me in haggling", :train, "innkeep", %{"ticks" => 4}, "train",
     "innkeep"},
    {"I look around the inn", :observe, nil, %{}, "narrate", nil},
    {"I walk to the market square", :move, "market_square", %{}, "move", "market_square"}
  ]

  for {text, type, target, params, handler, handler_target} <- @cases do
    @case {text, type, target, params, handler, handler_target}
    test "#{text}", %{session: session} do
      {text, type, target, params, handler, handler_target} = @case
      {raw, h} = play(session, text)
      assert {raw.action_type, raw.target, raw.parameters} == {type, target, params}
      assert {h.handler, h.target} == {handler, handler_target}
    end
  end
end
