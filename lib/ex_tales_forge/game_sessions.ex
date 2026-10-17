defmodule TalesForge.GameSessions do
  @moduledoc """
  Coordinates database sessions, the intent step, and Tier 2 Oban jobs.

  A core game runtime module: Ecto schemas (TalesForge.Schemas.*) and Repo only.
  """

  import Ecto.Query

  require Logger

  alias TalesForge.Agents.PlayerSessionAgent
  alias TalesForge.AICalls.{Steps, Tags}
  alias TalesForge.Characters
  alias TalesForge.Fronts
  alias TalesForge.Game.Context
  alias TalesForge.Game.Features
  alias TalesForge.Game.Intent
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Pack
  alias TalesForge.Game.SceneProcessor
  alias TalesForge.Game.Schemas.PlayerAction
  alias TalesForge.Game.Turn.Store
  alias TalesForge.Game.World
  alias TalesForge.GameSessions.TurnRequest
  alias TalesForge.IntentJev
  alias TalesForge.NPC
  alias TalesForge.NPCRegistry
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession
  alias TalesForge.Workers.{ProcessScene, ProcessTurn}

  def list_sessions do
    GameSession
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def get_session!(id), do: Repo.get!(GameSession, id)

  @character_opts [:controller, :controller_ref, :owner_player_id, :character]

  @doc """
  Creates a session with its world, NPCs, fronts and characters.

  Besides the session fields, `attrs` takes `:adventure_id` and the player
  character options `:controller` (`"player"` or `"bot"`), `:controller_ref`
  and `:owner_player_id` (see `TalesForge.Characters.seed_session/2`).

  `:character` is a created player character in the shape of a pack character
  file (`TalesForge.CharacterCreation.finalize/1`). It replaces the pack's
  default character (Elara) in `world_state["character"]` and gives the
  `characters` row its levers. An invalid one returns
  `{:error, {:invalid_character, message}}` and creates nothing.

  `:intent_jev` (`"off"`, `"shadow"` or `"on"`) overrides `INTENT_JEV` for this
  session, e.g. a playtest run's arm; the mode is stored in
  `world_state["intent_jev"]` when it is not off (`TalesForge.IntentJev`).
  """
  def create_session(attrs \\ %{}) do
    adventure_id = adventure_id_from(attrs)
    {intent_jev, attrs} = pop_session_flags(attrs)

    character_opts =
      Map.take(attrs, @character_opts ++ Enum.map(@character_opts, &Atom.to_string/1))

    with {:ok, character} <- validate_character(character_opts),
         world =
           adventure_id
           |> materialize_world()
           |> Map.put("game_system", TalesForge.Game.DiceSystem.default())
           |> put_character(character)
           |> IntentJev.put_mode(IntentJev.mode_for_new_session(intent_jev)) do
      insert_session(attrs, world, character_opts)
    end
  end

  # The Jev intent mode is a world-state choice, not a column.
  defp pop_session_flags(attrs) do
    intent_jev = Map.get(attrs, :intent_jev) || Map.get(attrs, "intent_jev")
    {intent_jev, Map.drop(attrs, [:intent_jev, "intent_jev"])}
  end

  defp insert_session(attrs, world, character_opts) do
    with {:ok, session} <-
           %GameSession{}
           |> GameSession.changeset(session_attrs(attrs, world, character_opts))
           |> Repo.insert(),
         :ok <- NPC.seed_session(session),
         :ok <- Fronts.seed_session(session),
         {:ok, session} <- NPC.refresh_session_world_state(session),
         :ok <- Characters.seed_session(session, character_opts),
         :ok <- ensure_agent(session),
         :ok <- NPCRegistry.sync(session),
         {:ok, _} <- ensure_scene(session) do
      {:ok, Repo.preload(session, [:npc_instances, :front_instances])}
    end
  end

  defp session_attrs(attrs, world, character_opts) do
    %{
      name: default_session_name(adventure_id_from(attrs)),
      status: "active",
      world_state: world
    }
    |> Map.merge(Map.drop(attrs, [:adventure_id, "adventure_id"] ++ Map.keys(character_opts)))
    |> Map.put(:world_state, world)
  end

  defp validate_character(opts) do
    case Map.get(opts, :character) || Map.get(opts, "character") do
      nil ->
        {:ok, nil}

      character when is_map(character) ->
        {:ok, Pack.validate_player_character!(character, "created character")}

      other ->
        {:error, {:invalid_character, "expected a map, got #{inspect(other)}"}}
    end
  rescue
    e in ArgumentError -> {:error, {:invalid_character, Exception.message(e)}}
  end

  defp put_character(world, nil), do: world

  defp put_character(world, character) do
    sheet =
      character
      |> Pack.sheet()
      |> Map.delete("creation")
      |> Map.put("location_id", world["location_id"])

    Map.put(world, "character", sheet)
  end

  defp adventure_id_from(attrs) do
    Map.get(attrs, :adventure_id) || Map.get(attrs, "adventure_id") || "crossroads_ledger"
  end

  defp default_session_name("tin_valley"), do: "Tin Valley"
  defp default_session_name(_), do: "Crossroads Hamlet"

  # Dual path: complete packs fail-fast via Pack; Crossroads keeps today's seed.
  # The session's world features (INN_WORLD, WORLD_ANTAGONIST) are read here,
  # once, and stored in world_state["features"].
  defp materialize_world("tin_valley"),
    do: Pack.materialize("tin_valley", Features.for_new_session())

  defp materialize_world(_adventure_id), do: World.default_world_state()

  def scene_status(session_id) do
    session_id
    |> get_session!()
    |> SceneProcessor.scene_status()
  end

  def ensure_scene(%GameSession{} = session) do
    if SceneProcessor.needs_scene?(session.world_state) do
      enqueue_scene(session.id)
    else
      {:ok, :scene_ready}
    end
  end

  def ensure_scene(session_id) when is_binary(session_id) do
    session_id
    |> get_session!()
    |> ensure_scene()
  end

  @doc """
  Submits the player's `text` for the session's next turn: reads the intent,
  then enqueues the turn job or, when the read is unsure, stores and
  broadcasts a clarification question (`{:ok, %{status: :clarification}}`).

  `opts` answers a pending clarification: `:clarification_id` with
  `:option_id` picks one of its options, and `:clarification_id` with text
  answers it in words. A picked option needs no text: blank `text` plays the
  player's words from when the question was asked (the play page sends none,
  so whatever sits in the input box doesn't matter). A clarification that is
  no longer pending returns `{:error, :clarification_expired}`. Blank text
  without an option returns `{:error, :empty_message}`.

  `:founder` is the email of the signed-in founder who plays. The turn row
  stores it for the work log.
  """
  @spec submit_message(String.t(), String.t(), keyword()) ::
          {:ok, %{required(:status) => :processing | :clarification, optional(atom()) => term()}}
          | {:error, term()}
  def submit_message(session_id, text, opts \\ []) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed == "" and not option_pick?(opts) do
      {:error, :empty_message}
    else
      with %GameSession{} = session <- Repo.get(GameSession, session_id),
           :ok <- reject_if_dead(session),
           {:ok, action_text} <- action_text(session, trimmed, opts),
           :ok <- ensure_runtime_started(session),
           :ok <- require_scene_ready(session),
           {:ok, outcome} <- resolve_and_enqueue(session, action_text, opts) do
        {:ok, outcome}
      else
        nil -> {:error, :not_found}
        {:error, _} = err -> err
      end
    end
  end

  @doc """
  The clarification question still waiting for the player's answer in
  `world_state`, or nil. The play page shows it again after a reload.
  """
  @spec pending_clarification(map() | nil) :: map() | nil
  def pending_clarification(%{"pending_clarification" => %{"clarification_id" => _} = pending}),
    do: pending

  def pending_clarification(_world_state), do: nil

  defp option_pick?(opts),
    do:
      not is_nil(Keyword.get(opts, :option_id)) and
        not is_nil(Keyword.get(opts, :clarification_id))

  # The text the turn plays. A picked option with no text of its own plays the
  # player's words from when the question was asked; any other answer to a
  # clarification needs that clarification to still be pending.
  defp action_text(session, text, opts) do
    case Keyword.get(opts, :clarification_id) do
      nil ->
        {:ok, text}

      clarification_id ->
        case pending_clarification(session.world_state) do
          %{"clarification_id" => ^clarification_id} = pending when text == "" ->
            pending_text(pending)

          %{"clarification_id" => ^clarification_id} ->
            {:ok, text}

          _ ->
            {:error, :clarification_expired}
        end
    end
  end

  defp pending_text(pending) do
    case String.trim(pending["player_text"] || pending["raw_action"] || "") do
      "" -> {:error, :empty_message}
      text -> {:ok, text}
    end
  end

  @doc "What the play page shows as the story so far. Needs `:turns` and `:scenes` preloaded."
  def transcript(%GameSession{} = session) do
    thoughts? = TalesForge.Characters.Thought.visible?()

    scene_rows =
      Enum.map(session.scenes, fn scene ->
        {scene.inserted_at, SceneProcessor.build_entry(scene)}
      end)

    turn_rows =
      session.turns
      |> Enum.sort_by(& &1.turn_number)
      |> Enum.flat_map(fn turn ->
        [
          {turn.inserted_at,
           %{id: "#{turn.id}-player", role: "player", text: turn.player_action}},
          {turn.inserted_at,
           %{
             id: "#{turn.id}-gm",
             role: "gm",
             text: turn.narrative || "",
             roll: TalesForge.Game.RollLine.text(turn.mechanical_resolution)
           }}
        ] ++ thought_rows(turn, thoughts?)
      end)

    (scene_rows ++ turn_rows)
    |> Enum.sort_by(fn {inserted_at, _} -> inserted_at end, DateTime)
    |> Enum.map(fn {_inserted_at, entry} -> entry end)
  end

  # Board card 845b6b15: a stored thought follows its GM entry (flag on only).
  defp thought_rows(%{thought: %{"text" => text} = thought} = turn, true) when is_binary(text),
    do: [{turn.inserted_at, TalesForge.Characters.Thought.entry(turn.id, thought)}]

  defp thought_rows(_turn, _visible), do: []

  def ensure_agent_started(%GameSession{} = session) do
    ensure_runtime_started(session)
  end

  def ensure_agent_started(session_id) when is_binary(session_id) do
    session_id
    |> get_session!()
    |> ensure_runtime_started()
  end

  def ensure_runtime_started(%GameSession{} = session) do
    with :ok <- ensure_agent(session),
         :ok <- NPCRegistry.sync(session) do
      :ok
    end
  end

  def agent_id(session_id), do: "session-#{session_id}"

  defp resolve_and_enqueue(%GameSession{} = session, raw_action, opts) do
    req = %TurnRequest{session: session, raw_action: raw_action, opts: opts}

    case IntentJev.mode(session.world_state) do
      :on -> resolve_and_enqueue_jev(req)
      mode -> resolve_and_enqueue_current(req, mode)
    end
  end

  # Today's intent path (INTENT_JEV off or shadow). In shadow the Jev read runs
  # in the background after the path has decided and is only logged; nothing
  # here changes.
  defp resolve_and_enqueue_current(
         %TurnRequest{session: session, raw_action: raw_action} = req,
         mode
       ) do
    req = %{req | context: Context.build_intent_context(session)}
    started_at = DateTime.utc_now()
    started = System.monotonic_time(:millisecond)

    try do
      {player_action, intent_source} = build_player_action(req)

      elapsed = System.monotonic_time(:millisecond) - started
      record_intent_step(session, %{started_at: started_at, elapsed_ms: elapsed})

      Logger.info(
        "intent resolved session=#{session.id} duration_ms=#{elapsed} source=#{intent_source}"
      )

      maybe_shadow(mode, req, %{
        source: intent_source,
        action: player_action,
        clarification: false
      })

      enqueue_turn(req, player_action, nil)
    rescue
      e in [Intent.ClarificationNeeded] ->
        elapsed = System.monotonic_time(:millisecond) - started
        record_intent_step(session, %{started_at: started_at, elapsed_ms: elapsed})
        clarification = Intent.build_clarification(e.extraction, raw_action)
        save_clarification(session, clarification, raw_action)

        maybe_shadow(mode, req, %{
          source: :llm,
          action: nil,
          clarification: true
        })

        SessionPubSub.broadcast(session.id, {:clarification_needed, clarification})
        {:ok, %{status: :clarification, clarification: clarification}}
    end
  end

  # Shadow reads only the player's own messages, not a clicked option.
  defp maybe_shadow(:shadow, %TurnRequest{session: session, context: context} = req, current) do
    if is_nil(Keyword.get(req.opts, :option_id)) do
      text = shadow_text(session, req.raw_action, req.opts)
      turn_number = Store.next_turn_number(session.id)
      IntentJev.shadow(Map.put(context, "turn_number", turn_number), text, current)
    end

    :ok
  end

  defp maybe_shadow(_mode, _req, _current), do: :ok

  defp shadow_text(session, raw_action, opts) do
    case Keyword.get(opts, :clarification_id) do
      nil ->
        raw_action

      _id ->
        pending = Map.get(session.world_state || %{}, "pending_clarification") || %{}
        (pending["raw_action"] || "") <> "\nClarification: " <> raw_action
    end
  end

  # INTENT_JEV=on: the Jev read drives the turn (TalesForge.IntentJev). The
  # heuristic reads only when Jev fails or times out.
  defp resolve_and_enqueue_jev(%TurnRequest{session: session, raw_action: raw_action} = req) do
    req = %{req | context: jev_context(session)}
    started_at = DateTime.utc_now()
    started = System.monotonic_time(:millisecond)

    outcome = jev_outcome(req)
    elapsed = System.monotonic_time(:millisecond) - started
    timing = %{started_at: started_at, elapsed_ms: elapsed}

    case outcome do
      {:act, player_action, gm, meta} ->
        record_intent_step(session, Map.put(timing, :meta, meta))

        Logger.info(
          "intent resolved session=#{session.id} duration_ms=#{elapsed} source=#{meta["source"]}"
        )

        enqueue_turn(req, player_action, gm)

      {:ask, clarification, meta} ->
        record_intent_step(session, Map.put(timing, :meta, meta))
        save_clarification(session, clarification, raw_action)
        SessionPubSub.broadcast(session.id, {:clarification_needed, clarification})
        {:ok, %{status: :clarification, clarification: clarification}}
    end
  end

  defp jev_context(session) do
    turn_number = Store.next_turn_number(session.id)
    session |> Context.build_intent_context() |> Map.put("turn_number", turn_number)
  end

  # What the player sent: a picked option of the pending question, a typed
  # answer to it, or a new message.
  defp reply_kind(%TurnRequest{opts: opts, raw_action: raw_action}) do
    option_id = Keyword.get(opts, :option_id)
    clarification_id = Keyword.get(opts, :clarification_id)

    cond do
      option_id && clarification_id -> {:option, clarification_id, option_id}
      clarification_id && raw_action != "" -> {:answer, clarification_id}
      true -> :message
    end
  end

  defp jev_outcome(%TurnRequest{} = req) do
    case reply_kind(req) do
      {:option, clarification_id, option_id} ->
        jev_option(req, clarification_id, option_id)

      {:answer, clarification_id} ->
        pending = get_pending(req.session, clarification_id)
        enriched = (pending["raw_action"] || "") <> "\nClarification: " <> req.raw_action
        IntentJev.resolve(req.context, enriched, never_ask: true)

      :message ->
        IntentJev.resolve(req.context, req.raw_action)
    end
  end

  defp jev_option(%TurnRequest{} = req, clarification_id, option_id) do
    pending = get_pending(req.session, clarification_id)
    option = Enum.find(pending["options"] || [], &(&1["id"] == option_id))
    if is_nil(option), do: raise(ArgumentError, "invalid clarification option")
    IntentJev.resolve_option(pending, option, req.context)
  end

  # Intent extraction + validation (the heuristic or the Jev
  # call, which have their own rows): the Elixir step before the turn job, on
  # the player's clock. `timing` has `:started_at`, `:elapsed_ms` and, in
  # INTENT_JEV=on, `:meta` (the Jev decision).
  defp record_intent_step(session, timing) do
    %{
      purpose: "turn.intent",
      latency_ms: timing.elapsed_ms,
      started_at: timing.started_at,
      game_session_id: session.id,
      turn_number: Store.next_turn_number(session.id)
    }
    |> put_meta(timing[:meta])
    |> Map.merge(Tags.for_world(session.world_state))
    |> Steps.record_one()
  end

  defp put_meta(step, nil), do: step
  defp put_meta(step, meta), do: Map.put(step, :meta, meta)

  defp build_player_action(%TurnRequest{} = req) do
    case reply_kind(req) do
      {:option, clarification_id, option_id} ->
        {resolve_clarification_option(req, clarification_id, option_id), :clarification}

      {:answer, clarification_id} ->
        pending = get_pending(req.session, clarification_id)
        enriched = pending["raw_action"] <> "\nClarification: " <> req.raw_action
        {Intent.extract_intent(enriched, req.context), :llm}

      :message ->
        resolve_message(req)
    end
  end

  defp resolve_message(%TurnRequest{raw_action: raw_action, context: context}) do
    {bundle, source} = Intent.resolve_bundle(raw_action, context)

    if Intent.needs_clarification?(bundle) do
      raise Intent.ClarificationNeeded, extraction: bundle
    end

    {Intent.validate_player_action(bundle, context), source}
  end

  defp resolve_clarification_option(%TurnRequest{} = req, clarification_id, option_id) do
    pending = get_pending(req.session, clarification_id)

    option =
      pending["options"]
      |> Enum.find(&(&1["id"] == option_id))

    if is_nil(option) do
      raise ArgumentError, "invalid clarification option"
    end

    extraction = %TalesForge.Game.Schemas.IntentExtraction{
      overall_intent: pending["overall_intent"],
      actions:
        pending
        |> Map.get("actions")
        |> case do
          nil -> [heuristic_from_pending(pending, option)]
          actions -> Enum.map(actions, &TalesForge.Game.Schemas.SingleAction.decode/1)
        end,
      primary_index: option["action_index"],
      confidence: pending["confidence"] || 1.0,
      needs_clarification: false
    }

    Intent.validate_player_action(extraction, req.context)
  end

  defp heuristic_from_pending(pending, option) do
    TalesForge.Game.Intent.heuristic_intent(
      "#{pending["raw_action"]} (#{option["label"]})",
      %{
        "exits" => [],
        "exit_names" => %{},
        "present_npcs" => [],
        "npc_details" => %{}
      }
    )
    |> Map.get(:actions)
    |> List.first()
  end

  defp get_pending(%GameSession{} = session, clarification_id) do
    pending =
      session.world_state
      |> Map.get("pending_clarification")

    if pending && pending["clarification_id"] == clarification_id do
      pending
    else
      raise ArgumentError, "clarification expired"
    end
  end

  defp reject_if_dead(%GameSession{status: "dead"}), do: {:error, :dead}

  defp reject_if_dead(%GameSession{world_state: world}) do
    if Mechanics.dead?(world) do
      {:error, :dead}
    else
      :ok
    end
  end

  defp require_scene_ready(%GameSession{} = session) do
    if SceneProcessor.needs_scene?(session.world_state) do
      ensure_scene(session)
      {:error, :needs_scene}
    else
      :ok
    end
  end

  defp enqueue_scene(session_id) do
    %{session_id: session_id}
    |> ProcessScene.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        SessionPubSub.broadcast(session_id, {:scene_processing, %{}})
        {:ok, :processing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # `gm` (INTENT_JEV=on only) adds the GM's quote and an optional note to the
  # job args; without it the args are exactly today's.
  defp enqueue_turn(
         %TurnRequest{session: session, raw_action: raw_action, opts: opts},
         %PlayerAction{} = player_action,
         gm
       ) do
    session
    |> clear_clarification()
    |> case do
      {:ok, session} ->
        %{
          session_id: session.id,
          raw_action: raw_action,
          player_action: PlayerAction.encode(player_action)
        }
        |> put_gm_args(gm)
        |> put_founder(Keyword.get(opts, :founder))
        |> ProcessTurn.new()
        |> Oban.insert()
        |> case do
          {:ok, _job} ->
            SessionPubSub.broadcast(session.id, {:turn_processing, %{}})
            {:ok, %{status: :processing}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp put_founder(args, founder) when is_binary(founder), do: Map.put(args, :founder, founder)
  defp put_founder(args, _founder), do: args

  defp put_gm_args(args, nil), do: args

  defp put_gm_args(args, %{gm_quote: quote} = gm) do
    args
    |> Map.put(:gm_quote, quote)
    |> then(fn a -> if gm[:gm_note], do: Map.put(a, :gm_note, gm.gm_note), else: a end)
  end

  # The stored copy also keeps the player's own words (`"player_text"`), which
  # a picked option plays; the broadcast question is unchanged.
  defp save_clarification(%GameSession{} = session, clarification, raw_action) do
    pending = Map.put(clarification, "player_text", raw_action)
    world_state = Map.put(session.world_state || %{}, "pending_clarification", pending)

    session
    |> GameSession.changeset(%{world_state: world_state})
    |> Repo.update()
  end

  defp clear_clarification(%GameSession{} = session) do
    world_state = Map.delete(session.world_state || %{}, "pending_clarification")

    session
    |> GameSession.changeset(%{world_state: world_state})
    |> Repo.update()
  end

  defp ensure_agent(%GameSession{id: id}) do
    aid = agent_id(id)

    if TalesForge.Jido.whereis(aid) do
      :ok
    else
      case TalesForge.Jido.start_agent(PlayerSessionAgent,
             id: aid,
             initial_state: %{session_id: id, turn_count: 0, entries: []}
           ) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, {:already_registered, _pid}} -> :ok
        other -> other
      end
    end
  end
end
