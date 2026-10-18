defmodule TalesForge.Game.Turn.Store do
  @moduledoc """
  The persist step of a turn (the effect at the end of the pipeline): one
  Multi with the session, the turn row, its events, the GM reasoning, the
  fronts and NPC ticks, the work-log push, the GM's NPC updates, the
  characters (`TalesForge.Characters.write_multi/1`) and the NPC Intentions
  of the turn (`TalesForge.NPCSignals.intentions/1`, applied by
  `TalesForge.Game.Turn.Intentions.apply_all/2`); then character memory,
  the registry sync, the thought and the initiative broadcasts.

  `TalesForge.Game.Turn.Adapters` uses `persist/1` as the default `store`.

  A `%Store{}` is one write: the session before the turn, the world after
  it, the turn number, the raw action and `ctx` (`:handler`,
  `:mechanical`, `:gm_result`, `:events`, `:sim`, `:founder`, and
  `:intention`, the acting character's `TalesForge.Intention`).
  """

  require Logger

  import Ecto.Query, only: [where: 3, select: 3]

  alias TalesForge.Characters
  alias TalesForge.Characters.{Moment, Thought}
  alias TalesForge.Fronts
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.RollLine
  alias TalesForge.Game.SceneProcessor
  alias TalesForge.Game.Schemas.MechanicalResolution
  alias TalesForge.Game.Turn.Intentions
  alias TalesForge.GMReasoning
  alias TalesForge.LLM
  alias TalesForge.NPC
  alias TalesForge.NPCInitiative
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

  @doc """
  Persists the turn, with the NPC Intentions it led to, and broadcasts the
  initiatives. The payload goes to the play page.
  """
  @spec persist(t()) :: {:ok, map()} | {:error, term()}
  def persist(%__MODULE__{} = store) do
    with {:ok, %{session: session, turn: turn, npc_intentions: initiatives}} <-
           transaction(store),
         moment = moment(store, turn),
         :ok <- after_commit(moment, session),
         thought = store_thought(moment, turn) do
      Enum.each(initiatives, &NPCInitiative.broadcast(session.id, &1))
      {:ok, payload(store, %{session: session, turn: turn}, thought)}
    end
  end

  # The saved turn as character memory and the thought see it; `actor` is
  # the character whose Intention the turn played.
  defp moment(%__MODULE__{session: session, world: world, ctx: ctx}, turn) do
    %Moment{
      session_id: session.id,
      turn_number: turn.turn_number,
      actor: ctx.intention.character_id,
      events: Map.get(ctx, :events, []),
      world: world,
      mode: TalesForge.Config.character_memory()
    }
  end

  defp after_commit(%Moment{} = moment, session) do
    # Character memory (board card fc3c9371): scene end moves working
    # memory to short-term; never fails the turn.
    with :ok <- TalesForge.Characters.Memory.on_turn(moment),
         # PR 2 (board card 845b6b15): Jev compression in a task, after commit.
         :ok <-
           TalesForge.Characters.Compression.after_turn(session.id, moment.events,
             now: Map.get(moment.world, "world_tick"),
             mode: moment.mode
           ) do
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

  # What the present NPCs heard and how long their concerns waited, as
  # Intentions applied in the transaction (`Turn.Intentions.apply_all/2`),
  # after the characters write, so the rows mirror them on the next turn as
  # before. None when the character died. Returns the initiative payloads.
  defp npc_intentions(multi, %__MODULE__{world: world} = store) do
    Ecto.Multi.run(multi, :npc_intentions, fn _repo, %{session: saved} ->
      if saved.status == "dead" or Mechanics.dead?(world) do
        {:ok, []}
      else
        {:ok, Intentions.apply_all(saved.id, NPCSignals.intentions(heard(store, saved)))}
      end
    end)
  end

  # The ticks that passed for the NPCs: the world after the turn less the
  # session as the turn loaded it. Comparing with `saved` (the session the
  # Multi saved, already the world after) gave 0, so no concern built and no
  # NPC spoke up on its own.
  defp heard(%__MODULE__{session: before, world: world, ctx: ctx} = store, saved) do
    %NPCSignals.Turn{
      session_id: saved.id,
      world_state: world,
      handler: ctx.handler,
      raw_action: store.raw_action,
      world_before: before.world_state
    }
  end

  defp transaction(%__MODULE__{} = store) do
    case store |> multi() |> Repo.transaction() do
      {:ok, result} -> {:ok, result}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp multi(%__MODULE__{session: session} = store) do
    Ecto.Multi.new()
    |> lock_session(session.id)
    |> turn_rows(store)
    |> world_rows(store)
  end

  # The session row, the turn and what the GM wrote down about it.
  defp turn_rows(multi, %__MODULE__{session: session, world: world, ctx: ctx} = store) do
    multi
    |> Ecto.Multi.update(:session, GameSession.changeset(session, session_attrs(world)))
    |> Ecto.Multi.insert(:turn, turn_changeset(store))
    |> push_work_log(Map.get(ctx, :founder))
    |> GMReasoning.multi_insert(
      %GMReasoning.At{session_id: session.id, tick: Map.get(world, "world_tick")},
      ctx.gm_result
    )
  end

  # What the turn did to the world: events, fronts, NPCs and characters.
  defp world_rows(multi, %__MODULE__{session: session, ctx: ctx} = store) do
    multi
    |> insert_events(session.id, ctx.events)
    |> Fronts.persist_tick_multi(session.id, ctx.sim)
    |> NPC.persist_tick_multi(session.id, ctx.sim)
    |> npc_gm_updates(store)
    |> Characters.write_multi()
    |> npc_intentions(store)
  end

  # The session's turn lock, held until the transaction ends: the backstop
  # behind TalesForge.World.Instance, which already runs one turn at a time,
  # for a turn from anywhere else (another machine, a script). Postgres has
  # no Ecto API for advisory locks. The first key keeps these locks apart
  # from other advisory locks (Oban's).
  @lock_class 10_006

  defp lock_session(multi, session_id) do
    Ecto.Multi.run(multi, :session_lock, fn repo, _changes ->
      repo.query("SELECT pg_advisory_xact_lock($1, hashtext($2))", [@lock_class, session_id])
    end)
  end

  # The GM's NPC memory updates, before the characters step mirrors them.
  defp npc_gm_updates(multi, %__MODULE__{session: session, world: world, ctx: ctx}) do
    Ecto.Multi.run(multi, :npc_gm_updates, fn _repo, _ ->
      {:ok, NPC.apply_gm_updates(session.id, ctx.gm_result, Map.get(world, "world_tick"))}
    end)
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
  defp store_thought(%Moment{} = moment, turn) do
    case Thought.for_turn(moment) do
      nil ->
        nil

      thought ->
        turn |> Ecto.Changeset.change(thought: thought) |> Repo.update!()
        if moment.mode == :on, do: thought
    end
  rescue
    e ->
      Logger.warning("thought not stored session=#{moment.session_id} #{Exception.message(e)}")
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
