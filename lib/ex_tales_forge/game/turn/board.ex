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
  alias TalesForge.GameCharacter.Rows

  alias TalesForge.Fronts
  alias TalesForge.Game.Absent
  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Arrivals
  alias TalesForge.Game.Bargain
  alias TalesForge.Game.Catalogue
  alias TalesForge.Game.Events
  alias TalesForge.Game.Inventory
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Offer
  alias TalesForge.Game.OutcomeRecord
  alias TalesForge.Game.Perception
  alias TalesForge.Game.Progression
  alias TalesForge.Game.Reflection

  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction, SingleAction}

  alias TalesForge.Game.Train
  alias TalesForge.Game.TurnApply
  alias TalesForge.Game.WalkThenTrade
  alias TalesForge.Game.World
  alias TalesForge.Game.WorldClock
  alias TalesForge.Game.WorldSim
  alias TalesForge.GameCharacter
  alias TalesForge.GameCharacter.{Agency, Roster}
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
      OutcomeRecord.build(%OutcomeRecord.Input{
        world_before: world_before,
        world_after: world,
        action: board.player_action.action,
        handler: handler,
        inventory_result: inventory_result
      })

    Map.merge(result, %{outcome: outcome, traders: traders(inventory_result)})
  end

  defp traders({:ok, %{traders: traders}}), do: traders
  defp traders(_inventory_result), do: []

  # Trade, catalogue and the premise of the inventory. Gives the world, the
  # inventory result and `board` with the handler marked rejected or as an
  # unpaid sleep.
  defp trade_step(world_before, %__MODULE__{handler: handler} = board) do
    {world_traded, traded} =
      world_before
      |> put_in(["character"], board.character)
      |> walk_first(board)
      |> answer_offer(board.player_action)
      |> trade(board)
      |> apply_catalogue(board)

    inventory_result = premise_result(handler, traded)

    handler =
      handler
      |> mark_rejected(inventory_result)
      |> unpaid_sleep(inventory_result)
      |> decided_trade(inventory_result, board.player_action.action)
      |> declined(world_before["open_offer"], board.player_action)

    {world_traded, inventory_result, %{board | handler: handler}}
  end

  # The open offer answered (design-trade-offers.md): an accept is already
  # the purchase (`Offer.answered/2`, at the turn's intention), so both an
  # accept and a decline close it; any other message ages it. An unclear
  # turn (`TalesForge.Game.Clarify`) keeps it as it is, not aged: the
  # person asks what the player meant (leaving, the giver gone or a new
  # offer still end it).
  defp answer_offer(world, %PlayerAction{clarify: %{}}), do: world

  defp answer_offer(world, %PlayerAction{offer_answer: answer})
       when answer in [:accept, :decline],
       do: Map.delete(world, "open_offer")

  defp answer_offer(%{"open_offer" => %{} = stored} = world, %PlayerAction{}) do
    case Offer.aged(stored) do
      nil -> Map.delete(world, "open_offer")
      aged -> Map.put(world, "open_offer", aged)
    end
  end

  defp answer_offer(world, %PlayerAction{}), do: world

  # The open offer ends when the player leaves its place or its giver is gone.
  defp expire_offer(%{"open_offer" => %{} = stored} = world) do
    if Offer.expired?(stored, world), do: Map.delete(world, "open_offer"), else: world
  end

  defp expire_offer(world), do: world

  # A trade that walks first (`"move_to"`, `TalesForge.Game.Intent`): the
  # character is at the place, with who is there, before the trade.
  defp walk_first(
         world,
         %__MODULE__{player_action: %{action: %{parameters: %{"move_to" => to}}}} = board
       ),
       do: world |> move_to(to) |> apply_location_presence(board.session)

  defp walk_first(world, %__MODULE__{}), do: world

  # The move, who is present, then the pause or the training.
  defp pause_step(world_traded, %__MODULE__{opts: opts} = board) do
    moved_from = board.character["location_id"]

    world_traded
    |> maybe_move(board.handler)
    |> apply_location_presence(board.session)
    |> expire_offer()
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
    |> Arrivals.present(sim.people)
    |> Perception.scrub_situation_lines(hidden)
    |> Perception.snapshot_public_facts(sim.fronts ++ sim.people)
    |> Arrivals.put(sim)
  end

  # The turn's events with the session's fronts and people, then one
  # world-sim tick of them.
  defp simulate_world(%Events.Turn{} = turn, session_id) do
    fronts = Fronts.sim_fronts(session_id)
    people = Agency.sim_people(session_id)
    events = Events.from_turn(%{turn | fronts: fronts, people: people})
    {:ok, sim} = WorldSim.tick(%{fronts: fronts, people: people, events: events})
    Arrivals.after_tick({events, sim}, people, turn.world_after)
  end

  defp apply_pause_or_train(world, %__MODULE__{handler: %{handler: "train"}} = board),
    do: apply_training(world, board)

  defp apply_pause_or_train(world, %__MODULE__{handler: handler, opts: opts}),
    do: {WorldClock.advance(world, ticks(world, handler, opts[:moved_from])), [], nil}

  # Hierarchical locations (board card 7aba0394, PR 2): a move costs the walk
  # time from the place tree (TalesForge.Game.Travel), when the places have
  # positions. Other actions, and a rejected move, keep their cost.
  # A trade that walked first (TalesForge.Game.WalkThenTrade) costs the walk,
  # then the trade.
  defp ticks(world, handler, from) do
    delta = ActionHandler.tick_delta(handler)

    case {handler.handler, WalkThenTrade.ticks(world, from)} do
      {_, nil} -> delta
      {"move", walk} when delta == 1 -> walk
      {_, walk} -> delta + walk
    end
  end

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
    case Rows.get(session_id, npc_id) do
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
    |> Map.put("present_npcs", Roster.sync_present_npcs(session.id, location_id))
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

  defp maybe_apply_inventory(
         world_state,
         %__MODULE__{player_action: %{action: action}} = board,
         refusals
       ) do
    cond do
      not Inventory.applies?(board.handler, action) ->
        {world_state, nil}

      reason = Absent.reason(board.session, action, world_state) ->
        {world_state, {:error, reason}}

      true ->
        apply_inventory(world_state, board, refusals)
    end
  end

  # The inventory step is pure; the traders it reads are loaded here, with
  # the `refusals` (trader id to reason) of the ones who will not trade, and
  # the traders whose inventory and coins it changes go with the result
  # (`:traders`), saved in the turn's transaction (`Turn.Store`) with the
  # character, so a trade is all or nothing.
  defp apply_inventory(world_state, %__MODULE__{session: session} = board, refusals) do
    action = board.player_action.action
    ids = Inventory.trader_ids(action, Map.get(world_state, "present_npcs", []))
    traders = session.id |> Roster.traders(ids) |> refuse(refusals)

    case decide_inventory(world_state, traders, board.player_action) do
      {:ok, %Offer{} = offer} ->
        {open_offer(world_state, offer), {:ok, %{applied: [], traders: [], offer: offer}}}

      {:ok, updated, details, changed} ->
        Logger.info("inventory applied session=#{session.id} changes=#{inspect(details.applied)}")
        {updated, {:ok, Map.put(details, :traders, changed)}}

      {:error, reason} ->
        Logger.warning("inventory skipped session=#{session.id} reason=#{reason}")
        {world_state, {:error, reason}}
    end
  end

  # The offer is the session's one open offer, replacing any other, made here.
  defp open_offer(world_state, %Offer{} = offer) do
    place = get_in(world_state, ["character", "location_id"])
    Map.put(world_state, "open_offer", Offer.to_world(%{offer | location_id: place}))
  end

  # Asking a price is never a purchase (#470 retest, session 8a9dbde9; Jev's
  # `ask_price`, `Offer.asks?/1`, #476 retest session 6d938a30), and
  # an unclear buy lists the options: the seller's offer stays open, and
  # nothing moves. An accepted offer is the purchase.
  defp decide_inventory(world_state, traders, %{action: %SingleAction{action_type: :buy}} = pa) do
    action = Inventory.named_item(pa.action, traders, pa.overall_intent)

    asked? =
      (Offer.asks?(pa.action) or Offer.asked?(pa.overall_intent)) and pa.offer_answer != :accept

    if asked? or Inventory.unclear?(action),
      do: Inventory.offer(world_state, traders, action),
      else: Inventory.apply_transaction(world_state, traders, action)
  end

  defp decide_inventory(world_state, traders, %{action: action}),
    do: Inventory.apply_transaction(world_state, traders, action)

  defp refuse(traders, refusals) do
    Enum.reduce(refusals, traders, fn {id, reason}, traders ->
      Map.replace_lazy(traders, id, &put_in(&1.runtime["refuses_trade"], reason))
    end)
  end

  # Catalogue v2 (JEV_CATALOGUE_V2): an NPC can refuse a trade, and the words
  # can ask for a haggle (TalesForge.Game.Bargain) before the inventory step.
  # The refusal is the trader's, decided with the rest of the trade
  # (`TalesForge.Game.Trade`).
  defp trade(world, %__MODULE__{session: session, player_action: player_action} = board) do
    action = player_action.action

    if board.opts[:catalogue_v2] && board.handler.handler == "inventory" &&
         action.action_type in [:buy, :sell] do
      trader = trader_id(world, session.id, action)
      profile = trader && session.id |> Roster.notice_profiles([trader]) |> List.first()

      if Catalogue.refuses_trade?(profile) do
        Logger.info("trade refused session=#{session.id} npc=#{trader}")
        refusal = "#{profile["name"] || trader} refuses to trade with you."
        maybe_apply_inventory(world, board, %{trader => refusal})
      else
        {world, board} = maybe_haggle(world, board, trader)
        maybe_apply_inventory(world, board, %{})
      end
    else
      maybe_apply_inventory(world, board, %{})
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
        |> Roster.traders(present)
        |> Enum.find_value(&seller(&1, item_id))

      true ->
        nil
    end
  end

  defp seller({npc_id, %GameCharacter{inventory: stock}}, item_id) do
    if Enum.any?(stock, &(&1["id"] == item_id)), do: npc_id
  end

  # `board` with the haggled price on its action, when the words ask for a
  # haggle and the trade has a price.
  defp haggle_opts(board, text),
    do: [appraise: Bargain.appraise?(text), rolls: board.opts[:haggle_rolls] || %{}]

  defp maybe_haggle(
         world,
         %__MODULE__{player_action: %{action: action} = player_action} = board,
         trader
       ) do
    text = player_action.overall_intent || ""
    price = trade_price(world, board, trader)

    if Bargain.haggle?(text) and is_integer(price) and price > 0 do
      {character, result} =
        Bargain.haggle(
          world["character"],
          %Bargain.Deal{kind: action.action_type, price: price},
          haggle_opts(board, text)
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
    item_id = (action.parameters || %{})["item_id"]

    with %GameCharacter{inventory: stock} <- Roster.traders(board.session.id, [trader])[trader],
         do: Enum.find_value(stock, &if(&1["id"] == item_id, do: &1["price_copper"]))
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

    case Catalogue.apply(world, %Catalogue.Act{
           handler: handler,
           text: player_action.overall_intent || "",
           npc: npc
         }) do
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
    do: session.id |> Roster.notice_profiles([npc_id]) |> List.first()

  defp premise_result(%{state_hints: %{"premise_rejected" => true, "reason" => reason}}, _result),
    do: {:error, "Premise check: " <> reason}

  defp premise_result(%{state_hints: %{"lodging_rejected" => true, "reason" => reason}}, _result),
    do: {:error, reason}

  defp premise_result(_handler, result), do: result

  # Stage 3 rejected the action, so the turn costs no game time
  # (ActionHandler.tick_delta/1).
  defp mark_rejected(handler, {:error, _reason}),
    do: %{handler | state_hints: Map.put(handler.state_hints || %{}, "rejected", true)}

  defp mark_rejected(handler, _result), do: handler

  # A buy or a sale as the board step decided it, for the GM
  # (`trade_outcome/2`): done, or refused with nothing moved.
  defp decided_trade(handler, result, %SingleAction{action_type: type} = action)
       when type in [:buy, :sell] do
    case trade_status(result) do
      nil ->
        handler

      {status, detail} ->
        put_trade(handler, %{"status" => countered(status, action), "detail" => detail})
    end
  end

  defp decided_trade(handler, _result, _action), do: handler

  # The trader's price quoted back on a price the player named that is worse
  # for her (`TalesForge.Game.NamedPrice.settle/3`): her counter-offer.
  defp countered("offered", %SingleAction{parameters: %{"named_price" => _}}), do: "counter"
  defp countered(status, _action), do: status

  defp trade_status({:error, reason}), do: {"refused", reason}

  defp trade_status({:ok, %{offer: %Offer{item: nil} = offer}}),
    do: {"options", Offer.text(offer)}

  defp trade_status({:ok, %{offer: %Offer{} = offer}}), do: {"offered", Offer.text(offer)}
  defp trade_status({:ok, %{applied: [done | _]}}), do: {"done", done}
  defp trade_status(_result), do: nil

  # The player declined the open offer: nothing moves, and the GM says so.
  defp declined(handler, %{} = stored, %PlayerAction{offer_answer: :decline}),
    do:
      put_trade(handler, %{
        "status" => "declined",
        "detail" => stored |> Offer.from_world() |> Offer.text()
      })

  defp declined(handler, _stored, _player_action), do: handler

  defp put_trade(handler, trade),
    do: %{handler | state_hints: Map.put(handler.state_hints || %{}, "trade", trade)}

  @doc """
  `handler` (what the GM gets) with the board step's decision on the buy or
  the sale of `board_handler` (`"trade"`), and for a refusal its reason as
  the handler's `"reason"` (the GM turn section of the prompt). The GM
  narrates only that outcome. Gentry's playtest sessions 643b8031 (a sale
  that paid nothing narrated as paid) and 3d9788e0 (a sale the server made
  narrated as refused), 2026-10-18.

      iex> refused = %TalesForge.Game.Schemas.HandlerResult{handler: "inventory",
      ...>   state_hints: %{"trade" => %{"status" => "refused", "detail" => "No price for travel cloak: nothing changed hands."}}}
      iex> TalesForge.Game.Turn.Board.trade_outcome(%TalesForge.Game.Schemas.HandlerResult{handler: "inventory"}, refused).state_hints["reason"]
      "No price for travel cloak: nothing changed hands."
  """
  @spec trade_outcome(HandlerResult.t(), HandlerResult.t()) :: HandlerResult.t()
  def trade_outcome(%HandlerResult{} = handler, %HandlerResult{
        state_hints: %{"trade" => %{"status" => "refused", "detail" => reason} = trade}
      }),
      do: %{
        handler
        | state_hints:
            Map.merge(handler.state_hints || %{}, %{"trade" => trade, "reason" => reason})
      }

  def trade_outcome(%HandlerResult{} = handler, %HandlerResult{state_hints: %{"trade" => trade}}),
    do: put_trade(handler, trade)

  def trade_outcome(handler, _board_handler), do: handler

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
