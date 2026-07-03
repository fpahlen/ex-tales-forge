defmodule TalesForge.NPC do
  @moduledoc """
  Per-session NPC runtime: definitions, NpcInstance persistence, memories, presence.
  """

  import Ecto.Query

  alias TalesForge.Game.WorldClock
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, NpcInstance}

  @npc_dir Path.join(:code.priv_dir(:ex_tales_forge), "npcs")
  @memory_limit 20
  @memory_context_limit 5

  def refresh_session_world_state(%GameSession{} = session) do
    location_id = Map.get(session.world_state, "location_id", "weary_pilgrim")

    world_state =
      session.world_state
      |> Map.put("present_npcs", sync_present_npcs(session.id, location_id))
      |> Map.put("npc_state", refresh_world_npc_state(session.id))

    session
    |> GameSession.changeset(%{world_state: world_state})
    |> Repo.update()
  end

  def seed_session(%{id: session_id, world_state: world_state}) do
    world_tick = Map.get(world_state, "world_tick", WorldClock.default_start_tick())

    @npc_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.each(fn file ->
      definition = load_definition_file(file)
      npc_id = Map.get(definition, "id", Path.rootname(file))

      insert_instance!(session_id, npc_id, definition, world_tick)
    end)

    :ok
  end

  def list_instances(session_id) do
    NpcInstance
    |> where([n], n.game_session_id == ^session_id)
    |> Repo.all()
  end

  def get_instance(session_id, npc_id) do
    Repo.get_by(NpcInstance, game_session_id: session_id, npc_id: npc_id)
  end

  def apply_gm_updates(session_id, gm_result, world_tick) do
    gm_result.npc_memory_updates
    |> List.wrap()
    |> Enum.each(fn update ->
      append_memory(session_id, update, world_tick)
    end)

    gm_result.state_updates
    |> List.wrap()
    |> Enum.each(fn update ->
      apply_state_update(session_id, update)
    end)

    :ok
  end

  def sync_present_npcs(session_id, location_id) do
    session_id
    |> list_instances()
    |> Enum.filter(fn inst ->
      Map.get(inst.runtime_state, "location_id") == location_id
    end)
    |> Enum.map(& &1.npc_id)
    |> Enum.sort()
  end

  def refresh_world_npc_state(session_id) do
    session_id
    |> list_instances()
    |> Enum.into(%{}, fn inst ->
      {inst.npc_id, display_npc(inst)}
    end)
  end

  def format_gm_sections(session_id, present_npc_ids) do
    present =
      session_id
      |> list_instances()
      |> Enum.filter(&(&1.npc_id in present_npc_ids))

    npc_json =
      present
      |> Enum.map(&merged_npc_context/1)
      |> Jason.encode!(pretty: true)

    memory_lines =
      present
      |> Enum.flat_map(fn inst ->
        inst
        |> recent_memories()
        |> Enum.map(fn mem ->
          "- #{inst.npc_id}: #{Map.get(mem, "summary", "")}"
        end)
      end)

    memory_block =
      if memory_lines == [],
        do: "(none)",
        else: Enum.join(memory_lines, "\n")

    """
    ## Present NPCs (merged definition + runtime)
    #{npc_json}

    ## NPC Memories (recent)
    #{memory_block}
    """
  end

  defp insert_instance!(session_id, npc_id, definition, world_tick) do
    location_id = Map.get(definition, "default_location_id", "weary_pilgrim")

    runtime =
      %{
        "location_id" => location_id,
        "mood" => get_in(definition, ["motivations", "mood"]) || "neutral",
        "relationship_score" => 0.0,
        "memories" => [],
        "since_tick" => world_tick
      }
      |> maybe_seed_concern_tick(definition, world_tick)

    %NpcInstance{}
    |> NpcInstance.changeset(%{
      game_session_id: session_id,
      npc_id: npc_id,
      personality: definition,
      runtime_state: runtime,
      disposition: 0.0
    })
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:game_session_id, :npc_id]
    )
  end

  defp maybe_seed_concern_tick(runtime, definition, world_tick) do
    case get_in(definition, ["motivations", "current_concern"]) do
      %{} = concern ->
        Map.put(runtime, "current_concern", Map.put(concern, "since_tick", world_tick))

      _ ->
        runtime
    end
  end

  defp append_memory(session_id, update, world_tick) when is_map(update) do
    npc_id = Map.get(update, "npc_id") || Map.get(update, :npc_id)
    summary = Map.get(update, "summary") || Map.get(update, :summary)

    if is_binary(npc_id) and is_binary(summary) and String.trim(summary) != "" do
      case get_instance(session_id, npc_id) do
        %NpcInstance{} = inst -> persist_memory(inst, summary, world_tick)
        nil -> :ok
      end
    end
  end

  defp append_memory(_session_id, _update, _world_tick), do: :ok

  defp persist_memory(%NpcInstance{} = inst, summary, world_tick) do
    entry = %{
      "summary" => String.trim(summary),
      "tick" => world_tick,
      "at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    memories =
      inst.runtime_state
      |> Map.get("memories", [])
      |> Kernel.++([entry])
      |> Enum.take(-@memory_limit)

    update_runtime!(inst, Map.put(inst.runtime_state, "memories", memories))
  end

  defp apply_state_update(session_id, %{"path" => path, "patch" => patch})
       when is_binary(path) and is_map(patch) do
    cond do
      String.starts_with?(path, "npcs/") ->
        npc_id = path |> String.split("/") |> Enum.at(1)
        apply_npc_patch(session_id, npc_id, patch)

      String.starts_with?(path, "characters/") ->
        :ok

      true ->
        :ok
    end
  end

  defp apply_state_update(_session_id, _update), do: :ok

  defp apply_npc_patch(session_id, npc_id, patch) when is_binary(npc_id) do
    case get_instance(session_id, npc_id) do
      %NpcInstance{} = inst ->
        runtime = deep_merge(inst.runtime_state, patch)
        update_runtime!(inst, runtime)

      nil ->
        :ok
    end
  end

  defp update_runtime!(%NpcInstance{} = inst, runtime_state) do
    inst
    |> NpcInstance.changeset(%{runtime_state: runtime_state})
    |> Repo.update!()
  end

  defp display_npc(%NpcInstance{} = inst) do
    definition = inst.personality || %{}

    %{
      "id" => inst.npc_id,
      "name" => Map.get(definition, "name", inst.npc_id),
      "role" => Map.get(definition, "role", "present"),
      "disposition" => Map.get(inst.runtime_state, "mood", "neutral"),
      "portrait_url" => Map.get(definition, "portrait_url")
    }
  end

  defp merged_npc_context(%NpcInstance{} = inst) do
    definition = inst.personality || %{}

    definition
    |> Map.put("runtime_state", inst.runtime_state)
    |> Map.put("relationship_score", Map.get(inst.runtime_state, "relationship_score", 0.0))
  end

  defp recent_memories(%NpcInstance{} = inst) do
    inst.runtime_state
    |> Map.get("memories", [])
    |> Enum.take(-@memory_context_limit)
  end

  defp load_definition_file(file) do
    @npc_dir
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, l, r ->
      if is_map(l) and is_map(r), do: deep_merge(l, r), else: r
    end)
  end

  defp deep_merge(_left, right), do: right
end
