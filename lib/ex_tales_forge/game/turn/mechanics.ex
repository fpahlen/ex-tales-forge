defmodule TalesForge.Game.Turn.Mechanics do
  @moduledoc """
  Stage 3 of a turn: the handler, the server mechanics and the board
  (inventory, clock, move, events, WorldSim, perception), then the world
  agents and the server prices (`WORLD_AGENTS=on`). Everything here is decided
  before the narration.

  Writes `outcome`: `handler`, `mechanical`, `board`, `agents` and
  `price_lines`. A blocked action is data: the handler is a `narrate` handler
  with `"rejected" => true` and the reason.
  """

  require Logger

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.AreaInventory
  alias TalesForge.Game.Rest
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Game.Turn
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.Game.TurnRules
  alias TalesForge.Game.Variant
  alias TalesForge.World, as: WorldAgents
  alias TalesForge.World.Prices

  @doc "Writes `outcome`."
  @spec apply(Turn.t()) :: Turn.t()
  def apply(%Turn{} = turn) do
    {handler, mechanical, ruled} = Steps.time(:rules, fn -> rules(turn) end)
    agents = agents(turn, ruled)
    {price_lines, board} = prices(turn, agents, ruled)

    %{
      turn
      | outcome: %{
          handler: handler,
          mechanical: mechanical,
          board: board,
          agents: agents,
          price_lines: price_lines
        }
    }
  end

  defp rules(%Turn{intent: player_action} = turn) do
    world = Turn.world_before(turn)

    resolved =
      player_action
      |> ActionHandler.resolve(Variant.of(turn.session.world_state))
      |> Rest.apply(world, player_action.overall_intent)
      |> find(world, player_action, Turn.flag?(turn, :jev_catalogue_v2))

    {premised, played} = premise_block(resolved, player_action, turn.premise.first)

    handler =
      premised
      |> lodging_block(world, played, Turn.flag?(turn, :turn_state_from_mechanics))
      |> injection_block(turn.injected)

    {character, rolled} = TurnProcessor.apply_mechanics(turn.session.world_state, played, handler)

    board =
      TurnProcessor.apply_board(turn.session, character, handler, player_action, rolled,
        catalogue_v2: Turn.flag?(turn, :jev_catalogue_v2)
      )

    {handler, %{rolled | improvements: board.improvements, training: board.training}, board}
  end

  # Catalogue v2 (JEV_CATALOGUE_V2): a search, forage or hunt in an area
  # with a stock rolls to find something (TalesForge.Game.AreaInventory).
  defp find(handler, _world, _player_action, false), do: handler

  defp find(handler, world, player_action, true),
    do: AreaInventory.handler(handler, world, player_action.overall_intent || "")

  # A claim that the state contradicts blocks the action: the turn narrates,
  # rolls nothing, books nothing and costs no game time. The outcome record
  # shows the action as rejected, with the corrections as the reason.
  defp premise_block(handler, player_action, nil), do: {handler, player_action}
  defp premise_block(handler, player_action, []), do: {handler, player_action}

  defp premise_block(_handler, player_action, findings) do
    reason = Enum.map_join(findings, " ", & &1.correction)

    blocked = %HandlerResult{
      handler: "narrate",
      notes: "Premise check: the action is blocked.",
      state_hints: %{"premise_rejected" => true, "rejected" => true, "reason" => reason}
    }

    action = player_action.action
    unrolled = %{action | parameters: Map.delete(action.parameters, "skill")}
    {blocked, %PlayerAction{player_action | action: unrolled}}
  end

  # TURN_STATE_FROM_MECHANICS=on (provisional rule): "pay for a room" with
  # nobody here who rents rooms is rejected (TalesForge.Game.TurnRules).
  defp lodging_block(%{state_hints: %{"rejected" => true}} = handler, _world, _action, _on),
    do: handler

  defp lodging_block(handler, _world, _action, false), do: handler

  defp lodging_block(handler, world, player_action, true) do
    if player_action.action.action_type == :spend and
         Rest.lodging_then_sleep?(player_action.overall_intent || "") and
         not TurnRules.lodging_seller?(world, world["location_id"]) do
      %HandlerResult{
        handler: "narrate",
        notes: "Room payment: nobody here rents rooms.",
        state_hints: %{
          "lodging_rejected" => true,
          "rejected" => true,
          "reason" => TurnRules.nobody_rents_rooms()
        }
      }
    else
      handler
    end
  end

  # HISTORY_STRIP_INJECTION=on: an injection turn plays no action.
  defp injection_block(handler, false), do: handler

  defp injection_block(_handler, true) do
    %HandlerResult{
      handler: "narrate",
      notes: "Out-of-character text: the server plays no action. Decline in character.",
      state_hints: %{"no_action" => true}
    }
  end

  # Prototype, WORLD_AGENTS=on: the agents relevant to this turn and their facts.
  defp agents(turn, board) do
    if Turn.flag?(turn, :world_agents),
      do: Steps.time(:world_facts, fn -> WorldAgents.collect(turn.session.id, board.world) end),
      else: []
  end

  defp prices(_turn, [], board), do: {[], board}

  defp prices(turn, agents, board) do
    Steps.time(:prices, fn ->
      {world, lines} =
        Prices.resolve(
          agents,
          turn.session.world_state,
          board.world,
          turn.raw_action,
          turn.intent
        )

      if lines != [],
        do: Logger.info("world prices session=#{turn.session.id} lines=#{inspect(lines)}")

      {lines, %{board | world: world}}
    end)
  end
end
