defmodule TalesForge.Game.Turn.Store do
  @moduledoc """
  The persist step of a turn (the effect at the end of the pipeline): one
  Multi with the session, the turn row, its events, the GM reasoning, the
  fronts and NPC ticks and the work-log push; then the NPC updates, the
  characters mirror, character memory, the registry sync, the thought and
  the turn signals.

  `TalesForge.Game.Turn.Adapters` uses `persist/1` as the default `store`.

  A `%Store{}` is one write: the session before the turn, the world after
  it, the turn number, the raw action and `ctx` (`:handler`,
  `:mechanical`, `:gm_result`, `:events`, `:sim`, `:founder`).
  """

  require Logger

  import Ecto.Query, only: [where: 3, select: 3]

  alias TalesForge.Characters
  alias TalesForge.Fronts
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.RollLine
  alias TalesForge.Game.SceneProcessor
  alias TalesForge.Game.Schemas.MechanicalResolution
  alias TalesForge.GMReasoning
  alias TalesForge.LLM
  alias TalesForge.NPC
  alias TalesForge.NPCRegistry
  alias TalesForge.NPCSignals
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, SessionEvent}
  alias TalesForge.Schemas.Turn, as: TurnRow
  alias TalesForge.Workers.PushWorkLogTurn

  @enforce_keys [:session, :world, :number, :raw_action, :ctx]
  defstruct [:session, :world, :number, :raw_action, :ctx]

  @type t :: %__MODULE__{
          session: GameSession.t(),
          world: map(),
          number: pos_integer(),
          raw_action: String.t(),
          ctx: map()
        }

  @doc "Persists the turn and signals it. The payload goes to the play page."
  @spec persist(t()) :: {:ok, map()} | {:error, term()}
  def persist(%__MODULE__{} = store) do
    with {:ok, %{session: session, turn: turn}} <- transaction(store),
         :ok <- after_commit(store, session),
         thought = store_thought(store, turn),
         :ok <- maybe_emit_turn_signals(store, session) do
      {:ok, payload(store, %{session: session, turn: turn}, thought)}
    end
  end

  defp after_commit(%__MODULE__{world: world, ctx: ctx}, session) do
    events = Map.get(ctx, :events, [])
    tick = Map.get(world, "world_tick")
    memory = TalesForge.Config.character_memory()

    with :ok <- NPC.apply_gm_updates(session.id, ctx.gm_result, tick),
         # Double-write to `characters` (nothing reads it yet); never fails the turn.
         :ok <- Characters.mirror(session),
         # Character memory (board card fc3c9371): scene end moves working
         # memory to short-term; never fails the turn.
         :ok <- TalesForge.Characters.Memory.on_turn(session.id, events, memory),
         # PR 2 (board card 845b6b15): Jev compression in a task, after commit.
         :ok <- TalesForge.Characters.Compression.after_turn(session.id, events, tick, memory) do
      NPCRegistry.sync(session)
    end
  end

  defp payload(
         %__MODULE__{world: world, ctx: ctx} = store,
         %{session: session, turn: turn},
         thought
       ) do
    mechanical = MechanicalResolution.encode(ctx.mechanical)

    %{
      session_id: session.id,
      turn_count: store.number,
      entries: build_entries(store, turn.id, mechanical) ++ thought_entries(turn.id, thought),
      mechanical_resolution: mechanical,
      llm_provider: LLM.provider(),
      llm_source: LLM.llm_source(LLM.provider()),
      location_name: Map.get(world, "location_name"),
      world_state: world,
      session_status: session.status,
      needs_scene: SceneProcessor.needs_scene?(world)
    }
  end

  # `session` is the one the Multi saved: its status and world_state are
  # after the turn.
  defp maybe_emit_turn_signals(%__MODULE__{}, %{status: "dead"}), do: :ok

  defp maybe_emit_turn_signals(%__MODULE__{world: world} = store, session) do
    if Mechanics.dead?(world) do
      :ok
    else
      NPCSignals.emit_turn_signals(
        session.id,
        world,
        store.ctx.handler,
        store.raw_action,
        session.world_state
      )
    end
  end

  defp transaction(%__MODULE__{} = store) do
    case store |> multi() |> Repo.transaction() do
      {:ok, result} -> {:ok, result}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp multi(%__MODULE__{session: session, world: world, ctx: ctx} = store) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, GameSession.changeset(session, session_attrs(world)))
    |> Ecto.Multi.insert(:turn, turn_changeset(store))
    |> push_work_log(Map.get(ctx, :founder))
    |> GMReasoning.multi_insert(session.id, Map.get(world, "world_tick"), ctx.gm_result)
    |> insert_events(session.id, ctx.events)
    |> Fronts.persist_tick_multi(session.id, ctx.sim)
    |> NPC.persist_tick_multi(session.id, ctx.sim)
  end

  defp turn_changeset(%__MODULE__{session: session, ctx: ctx} = store) do
    TurnRow.changeset(%TurnRow{}, %{
      game_session_id: session.id,
      turn_number: store.number,
      player_action: store.raw_action,
      narrative: ctx.gm_result.narrative,
      mechanical_resolution: MechanicalResolution.encode(ctx.mechanical),
      founder: Map.get(ctx, :founder)
    })
  end

  defp insert_events(multi, session_id, events) do
    events
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {ev, idx}, acc ->
      Ecto.Multi.insert(acc, {:event, idx}, event_changeset(session_id, ev))
    end)
  end

  defp event_changeset(session_id, ev) do
    SessionEvent.changeset(%SessionEvent{}, %{
      game_session_id: session_id,
      kind: ev["kind"],
      actor: ev["actor"],
      player_aware: ev["player_aware"],
      tick: ev["tick"],
      location_id: ev["location_id"],
      payload: ev["payload"] || %{}
    })
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

  @doc "The number of the session's next turn (1 for the first)."
  @spec next_turn_number(String.t()) :: pos_integer()
  def next_turn_number(session_id) do
    TurnRow
    |> where([t], t.game_session_id == ^session_id)
    |> select([t], max(t.turn_number))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  # Board card 845b6b15, PR 3: the player character's thought, stored on the
  # turn (also in shadow), shown only with CHARACTER_MEMORY=on.
  defp store_thought(%__MODULE__{session: session, world: world, ctx: ctx}, turn) do
    mode = TalesForge.Config.character_memory()
    events = Map.get(ctx, :events, [])

    case TalesForge.Characters.Thought.for_turn(session.id, events, world, turn.turn_number, mode) do
      nil ->
        nil

      thought ->
        turn |> Ecto.Changeset.change(thought: thought) |> Repo.update!()
        if mode == :on, do: thought
    end
  rescue
    e ->
      Logger.warning("thought not stored session=#{session.id} #{Exception.message(e)}")
      nil
  end

  defp thought_entries(_turn_id, nil), do: []

  defp thought_entries(turn_id, thought),
    do: [TalesForge.Characters.Thought.entry(turn_id, thought)]

  defp build_entries(%__MODULE__{raw_action: raw_action, ctx: ctx}, turn_id, mechanical) do
    [
      %{id: "#{turn_id}-player", role: "player", text: raw_action},
      %{
        id: "#{turn_id}-gm",
        role: "gm",
        text: ctx.gm_result.narrative,
        roll: RollLine.text(mechanical)
      }
    ]
  end
end
