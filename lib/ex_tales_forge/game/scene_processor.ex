defmodule TalesForge.Game.SceneProcessor do
  @moduledoc """
  Opening location exposition before player turns (v1 scene tier).
  """

  require Logger

  import Ecto.Query

  alias TalesForge.Game.Context
  alias TalesForge.Game.Prompts
  alias TalesForge.Game.World
  alias TalesForge.Images
  alias TalesForge.LLM
  alias TalesForge.NPC
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, NpcInstance, Scene}

  def needs_scene?(world_state) when is_map(world_state) do
    location_id = Context.location_id(world_state)
    last_scene = Context.last_scene_location(world_state)
    is_binary(location_id) and location_id != last_scene
  end

  def needs_scene?(_), do: true

  def scene_status(%GameSession{} = session) do
    world = session.world_state || %{}

    %{
      needs_scene: needs_scene?(world),
      current_location: Context.location_id(world),
      last_scene_location: Context.last_scene_location(world)
    }
  end

  def run(session_id) do
    started = System.monotonic_time(:millisecond)

    with %GameSession{} = session <- Repo.get(GameSession, session_id),
         true <- needs_scene?(session.world_state),
         {:ok, payload} <- describe_scene(session) do
      elapsed = System.monotonic_time(:millisecond) - started

      Logger.info(
        "scene completed session=#{session_id} location=#{payload.location_id} duration_ms=#{elapsed} llm_source=#{payload.llm_source}"
      )

      SessionPubSub.broadcast(session_id, {:scene_completed, payload})
      {:ok, payload}
    else
      nil ->
        {:error, :not_found}

      false ->
        {:ok, :scene_ready}

      {:error, reason} = err ->
        Logger.error("scene processor failed session=#{session_id} reason=#{inspect(reason)}")
        SessionPubSub.broadcast(session_id, {:scene_failed, inspect(reason)})
        err
    end
  end

  defp describe_scene(%GameSession{} = session) do
    world = session.world_state || %{}
    location_id = Context.location_id(world) || "weary_pilgrim"

    case load_scene(session.id, location_id) do
      %Scene{} = scene ->
        maybe_enqueue_missing_image(scene)
        finalize_scene(session, scene, "cache")

      nil ->
        generate_scene(session, location_id)
    end
  end

  defp generate_scene(%GameSession{} = session, location_id) do
    gm_context = Context.build_gm_context(session)
    # Use builder for symmetry / future evolution of scene prompt assembly.
    user_prompt = Prompts.build_scene_user(Context.format_gm_prompt(gm_context))

    case LLM.complete_scene(Prompts.scene_system(), user_prompt, gm_context.intent_context) do
      {:ok, %{location_name: location_name, narrative: narrative}} ->
        authored_image = World.scene_image_url(location_id)

        attrs = %{
          game_session_id: session.id,
          location_id: location_id,
          location_name: location_name,
          narrative: narrative,
          image_url: authored_image
        }

        with {:ok, scene} <- persist_scene(attrs) do
          maybe_enqueue_missing_image(scene)
          finalize_scene(session, scene, LLM.llm_source(LLM.provider()))
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finalize_scene(%GameSession{id: session_id}, %Scene{} = scene, llm_source) do
    session = Repo.get!(GameSession, session_id)

    world_state =
      session.world_state
      |> Map.put("last_scene_location", scene.location_id)
      |> Map.put("location_name", scene.location_name)

    with {:ok, session} <- persist_world_state(session, world_state),
         {:ok, session} <- NPC.refresh_session_world_state(session) do
      payload = %{
        session_id: session.id,
        location_id: scene.location_id,
        location_name: scene.location_name,
        image_url: scene.image_url,
        world_state: session.world_state,
        llm_source: llm_source,
        entries: [build_entry(scene)]
      }

      {:ok, payload}
    end
  end

  defp persist_world_state(%GameSession{} = session, world_state) do
    session
    |> GameSession.changeset(%{world_state: world_state})
    |> Repo.update()
  end

  defp persist_scene(attrs) do
    changeset =
      %Scene{}
      |> Scene.changeset(attrs)
      # Force :image_url (even when nil) so the column always appears in the INSERT
      # statement. This ensures EXCLUDED.image_url is defined for the on_conflict
      # update and the row is created with an explicit (NULL) image_url.
      |> Ecto.Changeset.put_change(:image_url, Map.get(attrs, :image_url))

    changeset
    |> Repo.insert(
      on_conflict: {:replace, [:location_name, :narrative, :image_url]},
      conflict_target: [:game_session_id, :location_id]
    )
  end

  defp load_scene(session_id, location_id) do
    Scene
    |> where([s], s.game_session_id == ^session_id and s.location_id == ^location_id)
    |> Repo.one()
  end

  defp maybe_enqueue_missing_image(%Scene{} = scene) do
    if (is_nil(scene.image_url) or scene.image_url == "") and not is_nil(scene.narrative) do
      npc_refs = build_npc_refs_for_image(scene.game_session_id)

      Images.enqueue_scene_image(scene.location_id, %{
        session_id: scene.game_session_id,
        narrative: scene.narrative,
        location_name: scene.location_name,
        npc_refs: npc_refs
      })
    end
  end

  defp build_npc_refs_for_image(session_id) do
    case Repo.get(GameSession, session_id) do
      nil ->
        []

      session ->
        Enum.map(Context.present_npcs(session.world_state || %{}), &npc_ref(session_id, &1))
    end
  end

  defp npc_ref(session_id, npc_id) do
    case NPC.get_instance(session_id, npc_id) do
      %NpcInstance{personality: pers} when is_map(pers) ->
        %{
          name: Map.get(pers, "name", npc_id),
          appearance: Map.get(pers, "appearance", ""),
          personality: Map.get(pers, "personality", ""),
          portrait_url: Map.get(pers, "portrait_url", "")
        }

      _ ->
        %{name: npc_id, appearance: "", personality: "", portrait_url: ""}
    end
  end

  def build_entry(%Scene{} = scene) do
    %{
      id: "#{scene.id}-scene",
      role: "scene",
      location_name: scene.location_name,
      text: scene.narrative,
      image_url: scene.image_url
    }
  end
end
