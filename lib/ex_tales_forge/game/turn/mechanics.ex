defmodule TalesForge.Game.Turn.Mechanics do
  @moduledoc """
  Stage 3 of a turn: the handler, the server mechanics and the board
  (inventory, clock, move, events, WorldSim, perception), then the world
  agents and the server prices (`WORLD_AGENTS=on`). Everything here is decided
  before the narration.

  Writes `outcome`: `handler`, `mechanical`, `board`, `agents` and
  `price_lines`, and `combat` (the exchange, `COMBAT_OPPOSED=on`). A blocked action is data: the handler is a `narrate` handler
  with `"rejected" => true` and the reason.
  """

  require Logger

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Combat
  alias TalesForge.Game.Rest
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Game.SkillSplit
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.Combat, as: TurnCombat
  alias TalesForge.Game.TurnApply
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.Game.TurnRules
  alias TalesForge.World, as: WorldAgents
  alias TalesForge.World.Prices

  @doc "Writes `outcome`."
  @spec apply(Turn.t()) :: Turn.t()
  def apply(%Turn{} = turn) do
    {handler, mechanical, ruled, played, combat} = Steps.time(:rules, fn -> rules(turn) end)
    agents = agents(turn, ruled)
    {price_lines, board} = prices(turn, agents, ruled)

    %{
      turn
      | outcome: %{
          handler: handler,
          mechanical: mechanical,
          board: board,
          agents: agents,
          price_lines: price_lines,
          played: played,
          combat: combat
        }
    }
  end

  defp rules(%Turn{intent: player_action} = turn) do
    world = Turn.world_before(turn)

    resolved =
      player_action
      |> ActionHandler.resolve()
      |> Rest.apply(world, player_action.overall_intent)

    apply? = Turn.flag?(turn, :turn_apply_outcomes)
    lodging? = apply? or Turn.flag?(turn, :turn_state_from_mechanics)

    {played, premised} =
      resolved
      |> premise_block(player_action, turn.premise.first)
      |> apply_outcomes(world, apply?)

    ruled_before_target =
      premised
      |> lodging_block(world, played, lodging?)
      |> sleep_after_lodging(world, played, apply?)
      |> injection_block(turn.injected)

    # COMBAT_OPPOSED=on: the attack needs a person in the scene. An unclear
    # target blocks the roll, and the turn asks the player.
    {targeted, ruled, target} = TurnCombat.target(turn, world, played, ruled_before_target)

    # TURN_APPLY_OUTCOMES=on: the board books the played action (with the
    # payment amount). Off: the board gets the action of the intent step.
    board_action = if apply?, do: targeted, else: player_action

    {character, rolled} = roll(turn, targeted, ruled)

    {combat, foe} = TurnCombat.exchange(turn, world, target, rolled)

    applied =
      TurnProcessor.apply_board(turn.session, character, ruled, board_action, rolled,
        catalogue_v2: Turn.flag?(turn, :jev_catalogue_v2),
        opposed: TurnCombat.on?(turn),
        combat: combat
      )

    board =
      if TurnCombat.on?(turn), do: TurnCombat.book(applied, world, combat, foe), else: applied

    # TURN_APPLY_OUTCOMES=on: the GM gets the handler after the board, for
    # example the short sleep after a failed room payment.
    handler = if apply?, do: board.handler, else: ruled

    mechanical =
      %{rolled | improvements: board.improvements, training: board.training}
      |> with_exchange(combat)

    {handler, mechanical, board, board_action, combat}
  end

  # COMBAT_OPPOSED=on (QA 2026-10-14 08:57, #270): the mechanical resolution
  # shows the exchange (the d100 against the Parry and the counterattack), and
  # the outcome is the hit or the miss of the attack, not the flat skill roll.
  defp with_exchange(mechanical, %{"attack" => attack} = exchange) do
    %{
      mechanical
      | combat: exchange,
        outcome: attack_outcome(attack),
        notes: Combat.summary(exchange)
    }
  end

  defp with_exchange(mechanical, _exchange), do: mechanical

  # QA 2026-10-14 21:15: the outcome keeps the d100 band of the attack
  # (critical success, near miss, critical failure), not only hit or miss.
  defp attack_outcome(%{"result" => result}) when is_binary(result), do: result
  defp attack_outcome(%{"hit" => true}), do: "success"
  defp attack_outcome(_attack), do: "failure"

  # SKILL_SPLIT=on: the split request of the player rolls each part
  # (TalesForge.Game.SkillSplit). Off: one roll, as before.
  defp roll(turn, played, ruled) do
    if Turn.flag?(turn, :skill_split) do
      world = turn.session.world_state || %{}

      SkillSplit.apply(
        Map.get(world, "character", %{}),
        played,
        ruled,
        turn.raw_action,
        rolls: Keyword.get(turn.opts, :rolls, [])
      )
    else
      TurnProcessor.apply_mechanics(turn.session.world_state, played, ruled)
    end
  end

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

  # TURN_APPLY_OUTCOMES=on: a purchase of a service is a payment, a payment
  # gets its amount, a move goes to the place that the text names, and a move
  # to an unknown place is rejected (TalesForge.Game.TurnApply).
  # Takes the {handler, action} pair of premise_block/3. Returns {action, handler}.
  defp apply_outcomes({handler, played}, _world, false), do: {played, handler}

  defp apply_outcomes({handler, played}, world, true) do
    {listed, item} = TurnApply.item_buy(played, handler, world)
    {bought, served} = TurnApply.service_buy(listed, item, world)
    {paid, priced} = TurnApply.put_spend_amount(bought, served)

    moved =
      priced
      |> TurnApply.named_move(world, played.overall_intent)
      |> TurnApply.unknown_move(world)
      |> TurnApply.deferred_move(world, played.overall_intent)
      |> TurnApply.wait_until(world, played.overall_intent)
      |> TurnApply.service_prices(world, played.overall_intent)

    {paid, moved}
  end

  # TURN_APPLY_OUTCOMES=on: "pay for a room and go to sleep" also plays the
  # sleep. A rejected payment gets the short sleep.
  defp sleep_after_lodging(handler, _world, _action, false), do: handler

  defp sleep_after_lodging(%{state_hints: %{"premise_rejected" => true}} = handler, _w, _a, true),
    do: handler

  defp sleep_after_lodging(handler, world, player_action, true),
    do: TurnApply.sleep_after_lodging(handler, world, player_action.overall_intent)

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
