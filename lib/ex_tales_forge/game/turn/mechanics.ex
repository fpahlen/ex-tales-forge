defmodule TalesForge.Game.Turn.Mechanics do
  @moduledoc """
  Stage 3 of a turn: the handler, the server mechanics and the board
  (inventory, clock, move, events, WorldSim, perception), then the world
  agents and the server prices (`WORLD_AGENTS=on`). Everything here is decided
  before the narration.

  Writes `outcome`: `handler`, `mechanical`, `board`, `agents` and
  `price_lines`, and `combat` (the exchange, `COMBAT_OPPOSED=on`). A blocked action is data: the handler is a `narrate` handler
  with `"rejected" => true` and the reason. The board carries the turn's
  cast (`board.cast`, `TalesForge.Game.Cast`), with the fight booked on it.
  """

  require Logger

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Combat
  alias TalesForge.Game.Rest
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Game.SkillSplit
  alias TalesForge.Game.TargetCheck
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.Board
  alias TalesForge.Game.Turn.Combat, as: TurnCombat
  alias TalesForge.Game.Turn.SelfCheck, as: TurnSelfCheck
  alias TalesForge.Game.TurnApply
  alias TalesForge.Game.TurnRules
  alias TalesForge.World, as: WorldAgents
  alias TalesForge.World.Prices

  @doc "Writes `outcome`."
  @spec apply(Turn.t()) :: Turn.t()
  def apply(%Turn{} = turn) do
    # JEV_SELF_CHECK=on: a speak to an NPC the text does not name, which
    # only asks, has no target from here on (the GM's action, the board).
    turn = TurnSelfCheck.address(turn)
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

  # The options of the board step (`TalesForge.Game.Turn.Board`).
  defp board_opts(turn, combat) do
    [
      catalogue_v2: Turn.flag?(turn, :jev_catalogue_v2),
      opposed: TurnCombat.on?(turn),
      combat: combat
    ]
  end

  defp rules(%Turn{intent: player_action} = turn) do
    {targeted, ruled, target} = ruled(turn)
    apply? = Turn.flag?(turn, :turn_apply_outcomes)

    # TURN_APPLY_OUTCOMES=on: the board books the played action (with the
    # payment amount). Off: the board gets the action of the intent step.
    board_action = if apply?, do: targeted, else: player_action

    {character, rolled} = roll(turn, targeted, ruled)
    fight = TurnCombat.exchange(turn, target, rolled)
    board = board(turn, {character, ruled, board_action, rolled}, fight)

    # TURN_APPLY_OUTCOMES=on: the GM gets the handler after the board, for
    # example the short sleep after a failed room payment. Off: the handler
    # before it. Both with the board's decision on a buy or a sale.
    # JEV_SELF_CHECK=on: the GM's self-check facts, from after the trade.
    handler =
      if(apply?, do: board.handler, else: ruled)
      |> Board.trade_outcome(board.handler)
      |> TurnSelfCheck.hint(turn, board.world)

    mechanical =
      %{rolled | improvements: board.improvements, training: board.training}
      |> with_exchange(fight.exchange)

    {handler, mechanical, board, board_action, fight.exchange}
  end

  # The rules before the roll: the action handler, rest, the premise check,
  # the outcomes, the place, the target and the lodging. Returns the played
  # action, the handler and the combat target.
  defp ruled(%Turn{intent: player_action} = turn) do
    world = Turn.world_before(turn)

    {played, premised} =
      player_action
      |> ActionHandler.resolve()
      |> Rest.apply(world, player_action.overall_intent)
      |> premise_block(player_action, turn.premise.first)
      |> apply_outcomes({world, turn.cast}, Turn.flag?(turn, :turn_apply_outcomes))
      |> same_place(world, turn.raw_action)
      |> target_block({world, turn.cast}, turn.raw_action)

    ruled_before_target =
      premised
      |> lodging_rules(turn, played)
      |> injection_block(turn.injected)
      |> TurnSelfCheck.only_ask(turn)

    # COMBAT_OPPOSED=on: the attack needs a person in the scene. An unclear
    # target blocks the roll, and the turn asks the player.
    TurnCombat.target(turn, played, ruled_before_target)
  end

  # The board after the roll, with the turn's cast and, with
  # COMBAT_OPPOSED=on, the fight booked on it.
  defp board(turn, {character, ruled, board_action, rolled}, fight) do
    board =
      %Board{
        session: turn.session,
        character: character,
        handler: ruled,
        player_action: board_action,
        mechanical: rolled,
        opts: board_opts(turn, fight.exchange)
      }
      |> Board.resolve()
      |> Map.put(:cast, turn.cast)

    if TurnCombat.on?(turn), do: TurnCombat.book(board, fight), else: board
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
        %SkillSplit.Check{
          player_action: played,
          handler: ruled,
          text: turn.raw_action,
          rolls: Keyword.get(turn.opts, :rolls, [])
        }
      )
    else
      Board.apply_mechanics(turn.session.world_state, played, ruled)
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

    {blocked, unrolled(player_action)}
  end

  # A blocked action rolls nothing: the action without its skill.
  defp unrolled(%PlayerAction{action: action} = played) do
    parameters = Map.delete(action.parameters || %{}, "skill")
    %PlayerAction{played | action: %{action | parameters: parameters}}
  end

  # A move to the place where the character is plays no walk, with or
  # without TURN_APPLY_OUTCOMES (TalesForge.Game.TurnApply.same_place/3).
  defp same_place({played, handler}, world, text),
    do: {played, TurnApply.same_place(handler, world, text)}

  # A dead person, or a social check at a person who is elsewhere
  # (TalesForge.Game.TargetCheck): the action is blocked with the reason.
  defp target_block({played, %{state_hints: %{"rejected" => true}} = handler}, _scene, _text),
    do: {played, handler}

  defp target_block({played, handler}, scene, text) do
    case TargetCheck.reason(scene, played.action, text) do
      nil ->
        {played, handler}

      reason ->
        blocked = %HandlerResult{
          handler: "narrate",
          notes: "Target check: the action is blocked.",
          state_hints: %{"target_rejected" => true, "rejected" => true, "reason" => reason}
        }

        {unrolled(played), blocked}
    end
  end

  # TURN_STATE_FROM_MECHANICS=on (provisional rule): "pay for a room" with
  # nobody here who rents rooms is rejected (TalesForge.Game.TurnRules).
  defp lodging_block(%{state_hints: %{"rejected" => true}} = handler, _world, _action),
    do: handler

  defp lodging_block(handler, world, player_action) do
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
  # gets its amount, and a talk that sets out for an unknown place keeps the
  # character here (TalesForge.Game.TurnApply). Moves are settled by the intent
  # step (TalesForge.Locations.Destination).
  # Takes the {handler, action} pair of premise_block/3. Returns {action, handler}.
  defp apply_outcomes({handler, played}, _scene, false), do: {played, handler}

  defp apply_outcomes({handler, played}, {world, cast} = scene, true) do
    {listed, item} = TurnApply.item_buy(played, handler, cast)
    {paid, priced} = TurnApply.put_spend_amount(listed, item)

    moved =
      priced
      |> TurnApply.deferred_move(scene, played.overall_intent)
      |> TurnApply.wait_until(world, played.overall_intent)
      |> TurnApply.service_prices(world, played.overall_intent)

    {paid, moved}
  end

  # TURN_APPLY_OUTCOMES=on: "pay for a room and go to sleep" also plays the
  # sleep. A rejected payment gets the short sleep.
  defp sleep_after_lodging(%{state_hints: %{"premise_rejected" => true}} = handler, _w, _a),
    do: handler

  defp sleep_after_lodging(handler, world, player_action),
    do: TurnApply.sleep_after_lodging(handler, world, player_action.overall_intent)

  # The room payment rules (lodging_block/3 and sleep_after_lodging/3), each
  # behind its flag.
  defp lodging_rules(handler, turn, played) do
    world = Turn.world_before(turn)
    apply? = Turn.flag?(turn, :turn_apply_outcomes)
    lodging? = apply? or Turn.flag?(turn, :turn_state_from_mechanics)

    handler
    |> when_on(lodging?, &lodging_block(&1, world, played))
    |> when_on(apply?, &sleep_after_lodging(&1, world, played))
  end

  # A rule step that only runs when its flag is on.
  defp when_on(handler, true, step), do: step.(handler)
  defp when_on(handler, false, _step), do: handler

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
        Prices.resolve(agents, board.world, %Prices.Turn{
          world_before: turn.session.world_state,
          raw_action: turn.raw_action,
          player_action: turn.intent
        })

      if lines != [],
        do: Logger.info("world prices session=#{turn.session.id} lines=#{inspect(lines)}")

      {lines, %{board | world: world}}
    end)
  end
end
