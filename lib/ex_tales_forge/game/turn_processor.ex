defmodule TalesForge.Game.TurnProcessor do
  @moduledoc """
  Turn pipeline: board first, then one table GM, then one Multi. A run
  is one pipe over a `%TalesForge.Game.Turn{}` struct; the stages are in
  `TalesForge.Game.Turn`. This module keeps the board, the Multi and the
  signals.

  PlayerAction → handler → server mechanics → inventory → clock+move →
  events → WorldSim → Perception → vitality → banked LP spent on improvement
  attempts on a long rest (`TalesForge.Game.Progression`) → premise check (default variant: the
  player's claims about items, coins, purchases and kills checked against the
  session, `TalesForge.Game.PremiseCheck`) → table GM (tone only) → allow-listed
  patches → Multi → NPC updates → characters mirror → sync/signals → turn_completed.

  Default variant: on a long rest the skills that improved overnight go to the
  per-turn GM prompt (`TalesForge.Game.Context.rest_growth_section/1`) so the
  GM can narrate the character waking surer of them.

  `TURN_OUTCOME_RECORD=on`: the board step writes an outcome record
  (`TalesForge.Game.OutcomeRecord`). The record goes to the per-turn GM prompt
  and to the turn as a `turn.outcome` event.

  `TURN_PREMISE_FIRST=on`: the premise check runs first, against the state
  before the turn. A claim that the state contradicts blocks the action: the
  turn rolls nothing, books nothing and costs no game time.

  Core runtime is 100% Ecto.
  """

  require Logger

  alias TalesForge.AICalls.{Steps, Tags}
  alias TalesForge.Characters
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
  alias TalesForge.Game.Progression.Tiered
  alias TalesForge.Game.Reflection
  alias TalesForge.Game.SceneProcessor

  alias TalesForge.Game.Schemas.{
    GMStructuredResponse,
    HandlerResult,
    MechanicalResolution,
    PlayerAction
  }

  alias TalesForge.Game.Train
  alias TalesForge.Game.Turn
  alias TalesForge.Game.TurnApply
  alias TalesForge.Game.Variant
  alias TalesForge.Game.World
  alias TalesForge.Game.WorldClock
  alias TalesForge.Game.WorldSim
  alias TalesForge.GMReasoning
  alias TalesForge.LLM
  alias TalesForge.NPC
  alias TalesForge.NPCRegistry
  alias TalesForge.NPCSignals
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, SessionEvent}
  alias TalesForge.Schemas.Turn, as: TurnRow
  alias TalesForge.Workers.PushWorkLogTurn

  @doc """
  Runs one turn. The main steps (rules, prompt build, GM call, persistence)
  are timed and recorded in `ai_calls` as `call_type` `function` rows
  (`TalesForge.AICalls.Steps`), whether the turn succeeds or fails.

  `player_action_map` is the encoded `PlayerAction` from the intent step.
  Returns `{:ok, payload}` once the turn is persisted and broadcast, or
  `{:error, reason}` (also broadcast as `:turn_failed`).

  A crash in a step (a raise, throw or exit) is logged with its stacktrace,
  broadcast as `:turn_failed` and recorded on the step's row, then re-raised
  so the Oban job records it and retries. Before this a crashed turn was
  silent: the job failed three times, nothing was logged or broadcast, and
  the player (or the playtest runner) waited until its timeout.

  `opts` (set only by the Jev intent path, `INTENT_JEV=on`):

    * `:gm_quote` — the text the GM gets as the action's `overall_intent`: the
      player's own words when the safety read was confidently benign, else a
      typed summary (`TalesForge.Game.PlayerQuote`). The rules still read
      `player_action_map`.
    * `:gm_note` — `"decline_nefarious"`: the GM declines the request in
      character (`TalesForge.Game.Context.player_request_section/1`).
    * `:founder` — the email of the signed-in founder who plays the turn. The
      turn row stores it for the work log. The GM prompt does not use it.

  Without them the GM prompt is byte-identical to before.
  """
  @spec run(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(session_id, raw_action, player_action_map, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    case Repo.get(GameSession, session_id) do
      nil ->
        {:error, :not_found}

      %GameSession{} = session ->
        turn_number = next_turn_number(session_id)

        {result, steps} =
          Steps.collect(fn ->
            session
            |> Turn.new(turn_number, raw_action, PlayerAction.decode(player_action_map), opts)
            |> Turn.Premise.check()
            |> Turn.Mechanics.apply()
            |> Turn.Npcs.react()
            |> Turn.Notice.select()
            |> Turn.Prompt.build()
            |> Turn.Gm.narrate()
            |> Turn.Outcome.persist()
            |> Turn.result()
          end)

        Steps.record(steps, session_id, turn_number, Tags.for_world(session.world_state))
        finish(result, session_id, turn_number, started)
    end
  end

  defp finish({:ok, payload}, session_id, turn_number, started) do
    elapsed = System.monotonic_time(:millisecond) - started

    Logger.info(
      "turn completed session=#{session_id} turn=#{turn_number} duration_ms=#{elapsed} llm_source=#{LLM.llm_source(LLM.provider())}"
    )

    SessionPubSub.broadcast(session_id, {:turn_completed, payload})
    {:ok, payload}
  end

  defp finish({:error, reason} = err, session_id, _turn_number, _started) do
    Logger.error("turn processor failed session=#{session_id} reason=#{inspect(reason)}")
    SessionPubSub.broadcast(session_id, {:turn_failed, SessionPubSub.failure_reason(reason)})
    err
  end

  defp finish({:crash, kind, reason, stacktrace}, session_id, turn_number, _started) do
    Logger.error(
      "turn processor crashed session=#{session_id} turn=#{turn_number}\n" <>
        Exception.format(kind, reason, stacktrace)
    )

    SessionPubSub.broadcast(session_id, {:turn_failed, crash_reason(kind, reason)})
    :erlang.raise(kind, reason, stacktrace)
  end

  # What the player and the playtest run see: the kind of crash, no internals
  # (the log has the details).
  defp crash_reason(:error, reason) do
    "crashed: " <> inspect(Exception.normalize(:error, reason, []).__struct__)
  end

  defp crash_reason(kind, _reason), do: "crashed: #{kind}"

  @doc false
  @spec simulate!(GameSession.t(), String.t(), struct(), struct(), struct(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def simulate!(session, raw_action, player_action, handler, mechanical, opts \\ []) do
    gm_result = %GMStructuredResponse{narrative: "ok", context_summary: nil}

    character = Map.get(session.world_state || %{}, "character", %{})
    turn_number = next_turn_number(session.id)

    %{
      world: world_board,
      events: events,
      sim: sim,
      improvements: improvements,
      training: training
    } =
      apply_board(session, character, handler, player_action, mechanical, opts)

    persist_and_signal(session, world_board, turn_number, raw_action, %{
      handler: handler,
      mechanical: %{mechanical | improvements: improvements, training: training},
      gm_result: gm_result,
      events: events,
      sim: sim
    })
  end

  @doc false
  @spec apply_board(GameSession.t(), map(), struct(), struct(), struct(), keyword()) :: map()
  def apply_board(session, character, handler, player_action, mechanical, opts \\ []) do
    world_before = session.world_state || %{}

    {world_traded, traded} =
      world_before
      |> put_in(["character"], character)
      |> trade(session, player_action, handler, opts)
      |> apply_catalogue(session, handler, player_action)

    inventory_result = premise_result(handler, traded)
    handler = handler |> mark_rejected(inventory_result) |> unpaid_sleep(inventory_result)

    world_present =
      world_traded
      |> maybe_move(handler)
      |> apply_location_presence(session)

    {world_paused, improvements, training} =
      apply_pause_or_train(world_present, session, handler, player_action, opts)

    fronts = Fronts.sim_fronts(session.id)
    people = NPC.sim_people(session.id)

    events =
      Events.from_turn(
        player_action,
        handler,
        mechanical,
        world_before,
        world_paused,
        fronts,
        people
      )

    {:ok, sim} = WorldSim.tick(%{fronts: fronts, people: people, events: events})
    hidden = Enum.reject(events, & &1["player_aware"])

    {world, spent, needs_reflection} =
      world_paused
      |> present_after_tick(sim.people)
      |> Perception.scrub_situation_lines(hidden)
      |> Perception.snapshot_public_facts(sim.fronts ++ sim.people)
      |> Mechanics.apply_vitality(mechanical, opts)
      |> note_reflection(player_action, improvements)
      |> maybe_spend_lp(handler, opts)

    %{
      world: world,
      events: events,
      sim: sim,
      improvements: improvements ++ spent,
      training: training,
      needs_reflection: needs_reflection,
      turn_growth: if(long_rest?(handler), do: [], else: spent),
      handler: handler,
      outcome:
        OutcomeRecord.build(world_before, world, player_action.action, handler, inventory_result)
    }
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

  defp apply_pause_or_train(world, session, %{handler: "train"}, player_action, opts) do
    apply_training(world, session, player_action, opts)
  end

  defp apply_pause_or_train(world, _session, handler, _player_action, opts) do
    world_moved = WorldClock.advance(world, ActionHandler.tick_delta(handler))
    {world_improved, improvements} = maybe_attempt_improvements(world_moved, handler, opts)
    {world_improved, improvements, nil}
  end

  # Default variant (decisions 2026-10-09): banked LP (one per failure) are
  # resolved only on a long rest (sleep, or a wait of six hours or more): at
  # most +1 per skill, and the skill's LP are gone afterwards, except for a
  # skill at the reflection level the character did not reflect on, whose LP
  # stay banked (Progression.resolve_rest/3). The "reflecting" list is cleared
  # by the rest, and so is "improved_since_rest". The physical skills in
  # Progression.immediate_skills/0 are resolved at the end of any other turn
  # (Progression.resolve_turn/3, at most +1 per skill per long-rest cycle).
  # The dead learn nothing. The baseline
  # variant spends LP only at a rest (maybe_attempt_improvements/3, the #64
  # rule).
  defp maybe_spend_lp(world, handler, opts) do
    if Variant.baseline?(world) or Mechanics.dead?(world) do
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

  # Default variant: skills the player's words reflect on, practise or study
  # (TalesForge.Game.Reflection), and a skill trained with a trainer this turn,
  # are kept in the character's "reflecting" list until the next long rest. The
  # key is only written when there is something to keep.
  defp note_reflection(world, player_action, turn_attempts) do
    if Variant.baseline?(world) do
      world
    else
      trained = for %{"bonus" => _, "skill" => skill} <- turn_attempts, do: skill
      found = Reflection.skills(player_action.overall_intent) ++ trained

      if found == [], do: world, else: update_in(world, ["character"], &add_reflecting(&1, found))
    end
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

  defp apply_training(world, session, player_action, opts) do
    action = player_action.action
    npc_id = action.target
    present_ids = Map.get(world, "present_npcs", [])
    npc_def = trainer_personality(session.id, npc_id)
    character = Map.get(world, "character", %{})

    {taught, improvements, training, ticks} =
      Train.apply(
        character,
        npc_def,
        present_ids,
        action,
        Keyword.put(opts, :variant, Variant.of(world))
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

  # Baseline variant only: the #64 rule tries eligible skills at a rest of an
  # hour or more.
  defp maybe_attempt_improvements(world, handler, opts) do
    pause? =
      Variant.baseline?(world) and handler.handler == "wait" and
        ActionHandler.tick_delta(handler) >= WorldClock.ticks_per_hour()

    if pause? do
      rolls = opts[:improvement_rolls] || %{}
      character = Map.get(world, "character", %{})
      {improved, improvements} = Tiered.attempt_improvements(character, rolls)
      {put_in(world, ["character"], improved), improvements}
    else
      {world, []}
    end
  end

  @doc false
  @spec persist_and_signal(GameSession.t(), map(), integer(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def persist_and_signal(session, world_after, turn_number, raw_action, ctx) do
    %{
      handler: handler,
      mechanical: mechanical,
      gm_result: gm_result
    } = ctx

    with {:ok, %{session: session, turn: turn}} <-
           persist_turn_multi(session, world_after, turn_number, raw_action, ctx),
         :ok <-
           NPC.apply_gm_updates(session.id, gm_result, Map.get(world_after, "world_tick")),
         # Double-write to `characters` (nothing reads it yet); never fails the turn.
         :ok <- Characters.mirror(session),
         :ok <- NPCRegistry.sync(session),
         :ok <- maybe_emit_turn_signals(session, world_after, handler, raw_action) do
      {:ok,
       %{
         session_id: session.id,
         turn_count: turn_number,
         entries: build_entries(raw_action, gm_result.narrative, turn.id),
         mechanical_resolution: MechanicalResolution.encode(mechanical),
         llm_provider: LLM.provider(),
         llm_source: LLM.llm_source(LLM.provider()),
         location_name: Map.get(world_after, "location_name"),
         world_state: world_after,
         session_status: session.status,
         needs_scene: SceneProcessor.needs_scene?(world_after)
       }}
    end
  end

  defp maybe_emit_turn_signals(%{status: "dead"}, _world_after, _handler, _raw_action), do: :ok

  defp maybe_emit_turn_signals(session, world_after, handler, raw_action) do
    if Mechanics.dead?(world_after) do
      :ok
    else
      NPCSignals.emit_turn_signals(
        session.id,
        world_after,
        handler,
        raw_action,
        session.world_state
      )
    end
  end

  @doc false
  @spec apply_mechanics(map() | nil, PlayerAction.t(), HandlerResult.t()) :: {map(), struct()}
  def apply_mechanics(world_state, player_action, handler) do
    character = Map.get(world_state || %{}, "character", %{})
    Mechanics.apply_server_mechanics(character, player_action, handler, Variant.of(world_state))
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

  # Default variant: only to a place that exists (the intent step resolves
  # names and routes; this guards a stale or invented id). Baseline: as before.
  defp move_to(world_state, location_id) do
    if Variant.baseline?(world_state) or World.runtime_location(world_state, location_id) != %{} do
      put_in(world_state, ["character", "location_id"], location_id)
    else
      Logger.warning("move ignored: unknown location_id=#{inspect(location_id)}")
      world_state
    end
  end

  defp maybe_apply_inventory(world_state, session_id, action, handler) do
    case Inventory.apply_server_inventory(world_state, session_id, action, handler) do
      {:ok, updated, %{applied: applied} = details} when is_list(applied) ->
        Logger.info("inventory applied session=#{session_id} changes=#{inspect(applied)}")
        {updated, {:ok, details}}

      {:ok, updated, nil} ->
        {updated, nil}

      {:ok, updated, details} ->
        {updated, {:ok, details}}

      {:error, reason} ->
        Logger.warning("inventory skipped session=#{session_id} reason=#{reason}")
        {world_state, {:error, reason}}
    end
  end

  # Catalogue v2 (JEV_CATALOGUE_V2): an NPC can refuse a trade, and the words
  # can ask for a haggle (TalesForge.Game.Bargain) before the inventory step.
  defp trade(world, session, player_action, handler, opts) do
    action = player_action.action

    if opts[:catalogue_v2] && handler.handler == "inventory" &&
         action.action_type in [:buy, :sell] do
      text = player_action.overall_intent || ""
      trader = trader_id(world, session.id, action)
      profile = trader && session.id |> NPC.notice_profiles([trader]) |> List.first()

      if Catalogue.refuses_trade?(profile) do
        reason = "#{profile["name"] || trader} refuses to trade with you."
        Logger.info("trade refused session=#{session.id} npc=#{trader}")
        {world, {:error, reason}}
      else
        {world, action} = maybe_haggle(world, session.id, action, trader, text, opts)
        maybe_apply_inventory(world, session.id, action, handler)
      end
    else
      maybe_apply_inventory(world, session.id, action, handler)
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

  defp maybe_haggle(world, session_id, action, trader, text, opts) do
    price = trade_price(world, session_id, action, trader)

    if Bargain.haggle?(text) and is_integer(price) and price > 0 do
      {character, result} =
        Bargain.haggle(world["character"], action.action_type, price,
          appraise: Bargain.appraise?(text),
          rolls: opts[:haggle_rolls] || %{},
          variant: Variant.of(world)
        )

      Logger.info("haggle session=#{session_id} result=#{inspect(result)}")
      params = Map.put(action.parameters || %{}, "price_copper", result["price_copper"])

      {Map.put(world, "character", character), %{action | parameters: params}}
    else
      {world, action}
    end
  end

  defp trade_price(_world, session_id, %{action_type: :buy} = action, trader)
       when is_binary(trader) do
    item_id = (action.parameters || %{})["item_id"]

    session_id
    |> NPC.stock_map([trader])
    |> Map.get(trader, [])
    |> Inventory.normalize_stock()
    |> Enum.find_value(&if(&1["id"] == item_id, do: &1["price_copper"]))
  end

  defp trade_price(world, _session_id, %{action_type: :sell} = action, _trader) do
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

  defp trade_price(_world, _session_id, _action, _trader), do: nil

  # Catalogue v2 (JEV_CATALOGUE_V2): work, equip and give
  # (TalesForge.Game.Catalogue). Other handlers pass through.
  defp apply_catalogue({world, traded}, session, %{handler: h} = handler, player_action)
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

  defp apply_catalogue(acc, _session, _handler, _player_action), do: acc

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

  defp persist_turn_multi(session, world_state, turn_number, raw_action, ctx) do
    %{gm_result: gm_result, mechanical: mechanical, events: events, sim: sim} = ctx

    turn_cs =
      %TurnRow{}
      |> TurnRow.changeset(%{
        game_session_id: session.id,
        turn_number: turn_number,
        player_action: raw_action,
        narrative: gm_result.narrative,
        mechanical_resolution: MechanicalResolution.encode(mechanical),
        founder: Map.get(ctx, :founder)
      })

    attrs = session_attrs(world_state)

    event_multi =
      events
      |> Enum.with_index()
      |> Enum.reduce(
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :session,
          GameSession.changeset(session, attrs)
        )
        |> Ecto.Multi.insert(:turn, turn_cs)
        |> push_work_log(Map.get(ctx, :founder))
        |> GMReasoning.multi_insert(session.id, Map.get(world_state, "world_tick"), gm_result),
        fn {ev, idx}, acc ->
          cs =
            %SessionEvent{}
            |> SessionEvent.changeset(%{
              game_session_id: session.id,
              kind: ev["kind"],
              actor: ev["actor"],
              player_aware: ev["player_aware"],
              tick: ev["tick"],
              location_id: ev["location_id"],
              payload: ev["payload"] || %{}
            })

          Ecto.Multi.insert(acc, {:event, idx}, cs)
        end
      )

    case event_multi
         |> Fronts.persist_tick_multi(session.id, sim)
         |> NPC.persist_tick_multi(session.id, sim)
         |> Repo.transaction() do
      {:ok, result} -> {:ok, result}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  # A founder's turn queues one work-log push to Workflow in the turn
  # transaction (TalesForge.Workers.PushWorkLogTurn). The turn makes no HTTP call.
  defp push_work_log(multi, founder) when is_binary(founder) and founder != "" do
    Oban.insert(multi, :work_log_push, fn %{turn: turn} -> PushWorkLogTurn.job(turn) end)
  end

  defp push_work_log(multi, _founder), do: multi

  defp session_attrs(world_state) do
    attrs = %{world_state: world_state}

    if Mechanics.dead?(world_state) do
      Map.put(attrs, :status, "dead")
    else
      attrs
    end
  end

  @doc false
  @spec next_turn_number(String.t()) :: pos_integer()
  def next_turn_number(session_id) do
    import Ecto.Query

    TurnRow
    |> where([t], t.game_session_id == ^session_id)
    |> select([t], max(t.turn_number))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  defp build_entries(raw_action, narrative, turn_id) do
    [
      %{id: "#{turn_id}-player", role: "player", text: raw_action},
      %{id: "#{turn_id}-gm", role: "gm", text: narrative}
    ]
  end
end
