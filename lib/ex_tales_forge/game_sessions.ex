defmodule TalesForge.GameSessions do
  @moduledoc """
  Coordinates database sessions, Tier 1 intent, and Tier 2 Oban jobs.
  """

  import Ecto.Query

  require Logger

  alias TalesForge.Agents.PlayerSessionAgent
  alias TalesForge.Game.Context
  alias TalesForge.Game.Intent
  alias TalesForge.Game.SceneProcessor
  alias TalesForge.Game.Schemas.PlayerAction
  alias TalesForge.Game.World
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

  def create_session(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Crossroads Hamlet",
          status: "active",
          world_state: World.default_world_state()
        },
        attrs
      )

    with {:ok, session} <-
           %GameSession{}
           |> GameSession.changeset(attrs)
           |> Repo.insert(),
         :ok <- NPC.seed_session(session),
         {:ok, session} <- NPC.refresh_session_world_state(session),
         :ok <- ensure_agent(session),
         :ok <- NPCRegistry.sync(session),
         {:ok, _} <- ensure_scene(session) do
      {:ok, Repo.preload(session, :npc_instances)}
    end
  end

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

  def submit_message(session_id, text, opts \\ []) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed == "" do
      {:error, :empty_message}
    else
      with %GameSession{} = session <- Repo.get(GameSession, session_id),
           :ok <- ensure_agent(session),
           :ok <- require_scene_ready(session),
           {:ok, outcome} <- resolve_and_enqueue(session, trimmed, opts) do
        {:ok, outcome}
      else
        nil -> {:error, :not_found}
        {:error, _} = err -> err
      end
    end
  end

  def ensure_agent_started(%GameSession{id: id}) do
    ensure_agent(%GameSession{id: id})
  end

  def agent_id(session_id), do: "session-#{session_id}"

  defp resolve_and_enqueue(%GameSession{} = session, raw_action, opts) do
    context = Context.build_intent_context(session)
    started = System.monotonic_time(:millisecond)

    try do
      {player_action, intent_source} =
        build_player_action(session, raw_action, context, opts)

      elapsed = System.monotonic_time(:millisecond) - started

      Logger.info(
        "intent resolved session=#{session.id} duration_ms=#{elapsed} source=#{intent_source}"
      )

      enqueue_turn(session, raw_action, player_action)
    rescue
      e in [Intent.ClarificationNeeded] ->
        clarification = Intent.build_clarification(e.extraction, raw_action)
        save_clarification(session, clarification)
        SessionPubSub.broadcast(session.id, {:clarification_needed, clarification})
        {:ok, %{status: :clarification, clarification: clarification}}
    end
  end

  defp build_player_action(%GameSession{} = session, raw_action, context, opts) do
    option_id = Keyword.get(opts, :option_id)
    clarification_id = Keyword.get(opts, :clarification_id)

    cond do
      option_id && clarification_id ->
        {resolve_clarification_option(session, context, clarification_id, option_id),
         :clarification}

      clarification_id && raw_action != "" ->
        pending = get_pending(session, clarification_id)
        enriched = pending["raw_action"] <> "\nClarification: " <> raw_action
        {Intent.extract_intent(enriched, context), :llm}

      true ->
        {bundle, source} = Intent.resolve_bundle(raw_action, context)

        if Intent.needs_clarification?(bundle) do
          raise Intent.ClarificationNeeded, extraction: bundle
        end

        {Intent.validate_player_action(bundle, context), source}
    end
  end

  defp resolve_clarification_option(session, context, clarification_id, option_id) do
    pending = get_pending(session, clarification_id)

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

    Intent.validate_player_action(extraction, context)
  end

  defp heuristic_from_pending(pending, option) do
    TalesForge.Game.Intent.heuristic_intent(
      "#{pending["raw_action"]} (#{option["label"]})",
      %{"exits" => [], "exit_names" => %{}, "present_npcs" => [], "npc_details" => %{}}
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

  defp enqueue_turn(%GameSession{} = session, raw_action, %PlayerAction{} = player_action) do
    session
    |> clear_clarification()
    |> case do
      {:ok, session} ->
        %{
          session_id: session.id,
          raw_action: raw_action,
          player_action: PlayerAction.encode(player_action)
        }
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

  defp save_clarification(%GameSession{} = session, clarification) do
    world_state = Map.put(session.world_state || %{}, "pending_clarification", clarification)

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
