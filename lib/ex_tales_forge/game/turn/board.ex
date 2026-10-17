defmodule TalesForge.Game.Turn.Board do
  @moduledoc """
  The board step of a turn and its input: the session, the
  character, the handler, the PlayerAction, the mechanical resolution and
  the options (`:catalogue_v2`, `:opposed`, `:combat`, `:haggle_rolls`,
  `:improvement_rolls`, `:death_roll`, ...). The trade step may change the
  action (a haggled price). Also the mechanics step before it
  (`apply_mechanics/3`) and the allow-listed GM patches after the GM
  (`turn_patches/3`).

  `resolve/1` runs the step: PlayerAction → handler → server mechanics → inventory → clock+move →
  events → WorldSim → Perception → vitality → banked LP spent on improvement
  attempts on a long rest (`TalesForge.Game.Progression`) → premise check.
  The steps of `TalesForge.Game.TurnProcessor` call this module; it calls
  none of them.

  On a long rest the skills that improved overnight go to the per-turn GM
  prompt (`TalesForge.Game.Context.rest_growth_section/1`) so the GM can
  narrate the character waking surer of them.

  `TURN_OUTCOME_RECORD=on`: the board step writes an outcome record
  (`TalesForge.Game.OutcomeRecord`). The record goes to the per-turn GM
  prompt and to the turn as a `turn.outcome` event.
  """

  require Logger

  alias TalesForge.Config
  alias TalesForge.Fronts
  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Bargain
  alias TalesForge.Game.Catalogue
  alias TalesForge.Game.Events
  alias TalesForge.Game.Inventory
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.OutcomeRecord
  alias TalesForge.Game.Perception
  alias TalesForge.Game.Progression
  alias TalesForge.Game.Reflection

  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}

  alias TalesForge.Game.Train
  alias TalesForge.Game.TurnApply
  alias TalesForge.Game.World
  alias TalesForge.Game.WorldClock
  alias TalesForge.Game.WorldSim
  alias TalesForge.NPC
  alias TalesForge.Schemas.GameSession

  @enforce_keys [:session, :handler, :player_action, :mechanical]
  defstruct [:session, :character, :handler, :player_action, :mechanical, opts: []]

  @type t :: %__MODULE__{
          session: TalesForge.Schemas.GameSession.t(),
          character: map() | nil,
          handler: struct(),
          player_action: struct(),
          mechanical: struct(),
          opts: keyword()
        }

  @doc """
  The board step: trade, catalogue, clock and move, events, WorldSim,
  perception, reflection and learning points, then the outcome record.
  """
  @spec resolve(t()) :: map()
  def resolve(%__MODULE__{session: session} = board) do
    world_before = session.world_state || %{}
    {world_traded, inventory_result, board} = trade_step(world_before, board)
    {world_paused, improvements, training} = pause_step(world_traded, board)

    %{world: world, handler: handler} =
      result =
      %{
        world: world_paused,
        improvements: improvements,
        training: training,
        handler: board.handler
      }
      |> tick(board, world_before)
      |> perceive(board)

    outcome =
      OutcomeRecord.build(
        world_before,
        world,
        board.player_action.action,
        handler,
        inventory_result
      )

    Map.put(result, :outcome, outcome)
  end

  # Trade, catalogue and the premise of the inventory. Gives the world, the
  # inventory result and `board` with the handler marked rejected or as an
  # unpaid sleep.
  defp trade_step(world_before, %__MODULE__{handler: handler} = board) do
    {world_traded, traded} =
      world_before
      |> put_in(["character"], board.character)
      |> trade(board)
      |> apply_catalogue(board)

    inventory_result = premise_result(handler, traded)
    handler = handler |> mark_rejected(inventory_result) |> unpaid_sleep(inventory_result)
    {world_traded, inventory_result, %{board | handler: handler}}
  end

  # The move, who is present, then the pause or the training.
  defp pause_step(world_traded, %__MODULE__{opts: opts} = board) do
    moved_from = get_in(world_traded, ["character", "location_id"])

    world_traded
    |> maybe_move(board.handler)
    |> apply_location_presence(board.session)
    |> apply_pause_or_train(%{board | opts: Keyword.put(opts, :moved_from, moved_from)})
  end

  # The turn's events and one world-sim tick.
  defp tick(%{world: world_paused} = result, %__MODULE__{} = board, world_before) do
    {events, sim} =
      simulate_world(
        %Events.Turn{
          player_action: board.player_action,
          handler: board.handler,
          mechanical: board.mechanical,
          world_before: world_before,
          world_after: world_paused
        },
        board.session.id
      )

    Map.merge(result, %{events: events, sim: sim})
  end

  # What the character perceives after the tick, vitality, reflection and
  # the banked LP spent on a long rest.
  defp perceive(%{world: world_paused, events: events, sim: sim} = result, %__MODULE__{} = board) do
    %__MODULE__{handler: handler, player_action: player_action, opts: opts} = board

    {world, spent, needs_reflection} =
      world_paused
      |> perceived(events, sim)
      |> Mechanics.apply_vitality(board.mechanical, opts)
      |> note_reflection(player_action, result.improvements)
      |> maybe_spend_lp(handler, opts)

    Map.merge(result, %{
      world: world,
      improvements: result.improvements ++ spent,
      needs_reflection: needs_reflection,
      turn_growth: if(long_rest?(handler), do: [], else: spent)
    })
  end

  # The world as the character perceives it after the tick: who the fronts
  # moved in, no situation line about a hidden event, the public facts.
  defp perceived(world, events, sim) do
    hidden = Enum.reject(events, & &1["player_aware"])

    world
    |> present_after_tick(sim.people)
    |> Perception.scrub_situation_lines(hidden)
    |> Perception.snapshot_public_facts(sim.fronts ++ sim.people)
  end

  # The turn's events with the session's fronts and people, then one
  # world-sim tick of them.
  defp simulate_world(%Events.Turn{} = turn, session_id) do
    fronts = Fronts.sim_fronts(session_id)
    people = NPC.sim_people(session_id)
    events = Events.from_turn(%{turn | fronts: fronts, people: people})
    {:ok, sim} = WorldSim.tick(%{fronts: fronts, people: people, events: events})
    {events, sim}
  end

  # People a front moved this tick (e.g. the Tinjacks walking into the inn) are
  # present this turn, not only from the next one.
  defp present_after_tick(world, []), do: world

  defp present_after_tick(world, people) do
    here = world["location_id"]

    present =
      people
      |> Enum.filter(&(get_in(&1, [:runtime_state, "location_id"]) == here))
      |> Enum.map(& &1.npc_id)
      |> Enum.sort()

    Map.put(world, "present_npcs", present)
  end

  defp apply_pause_or_train(world, %__MODULE__{handler: %{handler: "train"}} = board),
    do: apply_training(world, board)

  defp apply_pause_or_train(world, %__MODULE__{handler: handler, opts: opts}),
    do: {WorldClock.advance(world, ticks(world, handler, opts[:moved_from])), [], nil}

  # Hierarchical locations (board card 7aba0394, PR 2): a move costs the walk
  # time from the place tree (TalesForge.Game.Travel), when the places have
  # positions. Other actions, and a rejected move, keep their cost.
  defp ticks(world, %{handler: "move"} = handler, from) do
    default = ActionHandler.tick_delta(handler)
    to = get_in(world, ["character", "location_id"])

    if default == 1 and is_binary(from) and from != to,
      do: TalesForge.Game.Travel.ticks(world, from, to) || default,
      else: default
  end

  defp ticks(_world, handler, _from), do: ActionHandler.tick_delta(handler)

  # Decisions 2026-10-09: banked LP (one per failure) are
  # resolved only on a long rest (sleep, or a wait of six hours or more): at
  # most +1 per skill, and the skill's LP are gone afterwards, except for a
  # skill at the reflection level the character did not reflect on, whose LP
  # stay banked (Progression.resolve_rest/3). The "reflecting" list is cleared
  # by the rest, and so is "improved_since_rest". The physical skills in
  # Progression.immediate_skills/0 are resolved at the end of any other turn
  # (Progression.resolve_turn/3, at most +1 per skill per long-rest cycle).
  # The dead learn nothing.
  defp maybe_spend_lp(world, handler, opts) do
    if Mechanics.dead?(world) do
      {world, [], []}
    else
      character = Map.get(world, "character", %{})
      rolls = opts[:improvement_rolls] || %{}
      reflected = Map.get(character, "reflecting", [])

      if long_rest?(handler) do
        {rested, attempts, needs} =
          Progression.resolve_rest(character, rolls, reflected: reflected)

        rested = Map.drop(rested, ["reflecting", "improved_since_rest"])
        {put_in(world, ["character"], rested), attempts, needs}
      else
        {now, attempts} = Progression.resolve_turn(character, rolls, reflected: reflected)
        {put_in(world, ["character"], now), attempts, []}
      end
    end
  end

  # Skills the player's words reflect on, practise or study
  # (TalesForge.Game.Reflection), and a skill trained with a trainer this turn,
  # are kept in the character's "reflecting" list until the next long rest. The
  # key is only written when there is something to keep.
  defp note_reflection(world, player_action, turn_attempts) do
    trained = for %{"bonus" => _, "skill" => skill} <- turn_attempts, do: skill
    found = Reflection.skills(player_action.overall_intent) ++ trained

    if found == [], do: world, else: update_in(world, ["character"], &add_reflecting(&1, found))
  end

  defp add_reflecting(character, skills) do
    character = character || %{}
    already = Map.get(character, "reflecting", [])
    Map.put(character, "reflecting", Enum.sort(Enum.uniq(already ++ skills)))
  end

  defp long_rest?(%{state_hints: %{"sleep_ticks" => _}} = handler),
    do: handler |> ActionHandler.tick_delta() |> Progression.long_rest?()

  defp long_rest?(%{handler: "wait"} = handler),
    do: handler |> ActionHandler.tick_delta() |> Progression.long_rest?()

  defp long_rest?(_handler), do: false

  defp apply_training(world, %__MODULE__{
         session: session,
         player_action: player_action,
         opts: opts
       }) do
    action = player_action.action
    npc_id = action.target
    present_ids = Map.get(world, "present_npcs", [])
    npc_def = trainer_personality(session.id, npc_id)
    character = Map.get(world, "character", %{})

    {taught, improvements, training, ticks} =
      Train.apply(
        %Train.Session{character: character, trainer: npc_def, present_ids: present_ids},
        action,
        opts
      )

    world =
      world
      |> put_in(["character"], taught)
      |> WorldClock.advance(ticks)

    {world, improvements, training}
  end

  defp trainer_personality(session_id, npc_id) when is_binary(npc_id) and npc_id != "" do
    case NPC.get_instance(session_id, npc_id) do
      %{personality: personality} when is_map(personality) -> personality
      _ -> %{}
    end
  end

  defp trainer_personality(_session_id, _npc_id), do: %{}

  @doc false
  @spec apply_mechanics(map() | nil, PlayerAction.t(), HandlerResult.t()) :: {map(), struct()}
  def apply_mechanics(world_state, player_action, handler) do
    character = Map.get(world_state || %{}, "character", %{})
    Mechanics.apply_server_mechanics(character, player_action, handler)
  end

  # HISTORY_STRIP_INJECTION=on: an injection turn writes no context_summary.
  @doc false
  @spec turn_patches(map(), struct(), boolean()) :: map()
  def turn_patches(world, _gm_result, true), do: world

  def turn_patches(world, gm_result, false), do: apply_allowlisted_patches(world, gm_result)

  defp apply_allowlisted_patches(world, gm_result) do
    maybe_apply_context_summary(world, gm_result.context_summary)
  end

  defp apply_location_presence(world_state, %GameSession{} = session) do
    location_id = get_in(world_state, ["character", "location_id"])
    location = World.runtime_location(world_state, location_id)

    world_state
    |> Map.put("location_id", location_id)
    |> Map.put(
      "location_name",
      Map.get(location, "name", Map.get(world_state, "location_name"))
    )
    |> Map.put("present_npcs", NPC.sync_present_npcs(session.id, location_id))
    |> Map.put("npc_state", NPC.refresh_world_npc_state(session.id))
  end

  defp maybe_move(world_state, %{handler: "move", state_hints: %{"location_id" => location_id}})
       when is_binary(location_id) do
    move_to(world_state, location_id)
  end

  defp maybe_move(world_state, %{handler: "move", target: target}) when is_binary(target) do
    move_to(world_state, target)
  end

  defp maybe_move(world_state, _), do: world_state

  # Only to a place that exists (the intent step resolves names and routes;
  # this guards a stale or invented id).
  defp move_to(world_state, location_id) do
    if World.runtime_location(world_state, location_id) != %{} do
      put_in(world_state, ["character", "location_id"], location_id)
    else
      Logger.warning("move ignored: unknown location_id=#{inspect(location_id)}")
      world_state
    end
  end

  defp maybe_apply_inventory(world_state, %__MODULE__{player_action: %{action: action}} = board) do
    if Inventory.applies?(board.handler, action),
      do: apply_inventory(world_state, board.session.id, action),
      else: {world_state, nil}
  end

  # The inventory step is pure; the NPC stock it reads and the stock it
  # changes are loaded and saved here.
  defp apply_inventory(world_state, session_id, action) do
    keys = Inventory.npc_stock_keys(action, Map.get(world_state, "present_npcs", []))

    case Inventory.apply_transaction(world_state, NPC.stock_map(session_id, keys), action) do
      {:ok, updated, details, npc_updates} ->
        :ok = NPC.persist_stock_updates(session_id, npc_updates)
        Logger.info("inventory applied session=#{session_id} changes=#{inspect(details.applied)}")
        {updated, {:ok, details}}

      {:error, reason} ->
        Logger.warning("inventory skipped session=#{session_id} reason=#{reason}")
        {world_state, {:error, reason}}
    end
  end

  # Catalogue v2 (JEV_CATALOGUE_V2): an NPC can refuse a trade, and the words
  # can ask for a haggle (TalesForge.Game.Bargain) before the inventory step.
  defp trade(world, %__MODULE__{session: session, player_action: player_action} = board) do
    action = player_action.action

    if board.opts[:catalogue_v2] && board.handler.handler == "inventory" &&
         action.action_type in [:buy, :sell] do
      trader = trader_id(world, session.id, action)
      profile = trader && session.id |> NPC.notice_profiles([trader]) |> List.first()

      if Catalogue.refuses_trade?(profile) do
        reason = "#{profile["name"] || trader} refuses to trade with you."
        Logger.info("trade refused session=#{session.id} npc=#{trader}")
        {world, {:error, reason}}
      else
        {world, board} = maybe_haggle(world, board, trader)
        maybe_apply_inventory(world, board)
      end
    else
      maybe_apply_inventory(world, board)
    end
  end

  defp trader_id(world, session_id, action) do
    present = List.wrap(world["present_npcs"])
    item_id = (action.parameters || %{})["item_id"]

    cond do
      action.target in present ->
        action.target

      action.action_type == :buy and is_binary(item_id) ->
        session_id
        |> NPC.stock_map(present)
        |> Enum.find_value(&seller(&1, item_id))

      true ->
        nil
    end
  end

  defp seller({npc_id, stock}, item_id) do
    if Enum.any?(Inventory.normalize_stock(stock), &(&1["id"] == item_id)), do: npc_id
  end

  # `board` with the haggled price on its action, when the words ask for a
  # haggle and the trade has a price.
  defp maybe_haggle(
         world,
         %__MODULE__{player_action: %{action: action} = player_action} = board,
         trader
       ) do
    text = player_action.overall_intent || ""
    price = trade_price(world, board, trader)

    if Bargain.haggle?(text) and is_integer(price) and price > 0 do
      {character, result} =
        Bargain.haggle(world["character"], action.action_type, price,
          appraise: Bargain.appraise?(text),
          rolls: board.opts[:haggle_rolls] || %{}
        )

      Logger.info("haggle session=#{board.session.id} result=#{inspect(result)}")
      params = Map.put(action.parameters || %{}, "price_copper", result["price_copper"])
      action = %{action | parameters: params}

      {Map.put(world, "character", character),
       %{board | player_action: %{player_action | action: action}}}
    else
      {world, board}
    end
  end

  defp trade_price(
         _world,
         %__MODULE__{player_action: %{action: %{action_type: :buy} = action}} = board,
         trader
       )
       when is_binary(trader) do
    session_id = board.session.id
    item_id = (action.parameters || %{})["item_id"]

    session_id
    |> NPC.stock_map([trader])
    |> Map.get(trader, [])
    |> Inventory.normalize_stock()
    |> Enum.find_value(&if(&1["id"] == item_id, do: &1["price_copper"]))
  end

  defp trade_price(
         world,
         %__MODULE__{player_action: %{action: %{action_type: :sell} = action}},
         _trader
       ) do
    params = action.parameters || %{}

    case params["price_copper"] do
      price when is_integer(price) and price > 0 ->
        price

      _ ->
        world
        |> get_in(["character", "inventory"])
        |> List.wrap()
        |> Enum.find_value(&if(&1["id"] == params["item_id"], do: &1["copper_value"]))
    end
  end

  defp trade_price(_world, %__MODULE__{}, _trader), do: nil

  # Catalogue v2 (JEV_CATALOGUE_V2): work, equip and give
  # (TalesForge.Game.Catalogue). Other handlers pass through.
  defp apply_catalogue(
         {world, traded},
         %__MODULE__{
           session: session,
           handler: %{handler: h} = handler,
           player_action: player_action
         }
       )
       when h in ["work", "equip", "give"] do
    npc = if h == "give", do: gift_npc(session, handler.target)

    case Catalogue.apply(world, handler, player_action.overall_intent || "", npc) do
      {updated, {:error, reason} = error} ->
        Logger.info("catalogue skipped session=#{session.id} reason=#{reason}")
        {updated, error}

      {updated, result} ->
        {updated, result || traded}
    end
  end

  defp apply_catalogue(acc, %__MODULE__{}), do: acc

  defp gift_npc(_session, nil), do: nil

  defp gift_npc(session, npc_id),
    do: session.id |> NPC.notice_profiles([npc_id]) |> List.first()

  defp premise_result(%{state_hints: %{"premise_rejected" => true, "reason" => reason}}, _result),
    do: {:error, "Premise check: " <> reason}

  defp premise_result(%{state_hints: %{"lodging_rejected" => true, "reason" => reason}}, _result),
    do: {:error, reason}

  defp premise_result(_handler, result), do: result

  # TURN_OUTCOME_RECORD=on: stage 3 rejected the action, so the turn costs
  # no game time (ActionHandler.tick_delta/1).
  defp mark_rejected(handler, {:error, _reason}) do
    if Config.turn_outcome_record?(),
      do: %{handler | state_hints: Map.put(handler.state_hints || %{}, "rejected", true)},
      else: handler
  end

  defp mark_rejected(handler, _result), do: handler

  # A failed room payment gives the short sleep, with no paid bed.
  defp unpaid_sleep(handler, {:error, _reason}), do: TurnApply.unpaid_sleep(handler)

  defp unpaid_sleep(handler, _result), do: handler

  defp maybe_apply_context_summary(world_state, nil), do: world_state

  defp maybe_apply_context_summary(world_state, summary) do
    lines =
      summary
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(world_state, "situation_lines", lines)
  end
end
