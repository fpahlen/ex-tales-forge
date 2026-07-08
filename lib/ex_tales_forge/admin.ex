defmodule TalesForge.Admin do
  @moduledoc """
  Admin context for sessions, NPC instances, turns, and NPC definition files.
  """

  import Ecto.Query

  require Logger

  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, NpcInstance, Scene, Turn}

  @npc_dir Path.join(:code.priv_dir(:ex_tales_forge), "npcs")

  def stats do
    %{
      sessions: Repo.aggregate(GameSession, :count, :id),
      active_sessions:
        GameSession
        |> where([s], s.status == "active")
        |> Repo.aggregate(:count, :id),
      turns: Repo.aggregate(Turn, :count, :id),
      npc_instances: Repo.aggregate(NpcInstance, :count, :id),
      scenes: Repo.aggregate(Scene, :count, :id)
    }
  end

  def list_sessions do
    sessions =
      GameSession
      |> order_by([s], desc: s.inserted_at)
      |> Repo.all()

    counts = turn_counts(Enum.map(sessions, & &1.id))

    Enum.map(sessions, fn session ->
      %{
        session: session,
        turn_count: Map.get(counts, session.id, 0),
        location_name: session_location(session),
        character_name: session_character_name(session)
      }
    end)
  end

  def get_session!(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    GameSession
    |> Repo.get!(id)
    |> Repo.preload(preloads)
  end

  def update_session(%GameSession{} = session, attrs) do
    session
    |> GameSession.changeset(attrs)
    |> Repo.update()
  end

  def update_session_world_state(%GameSession{} = session, json_string)
      when is_binary(json_string) do
    with {:ok, world_state} <- decode_json_map(json_string),
         {:ok, session} <- update_session(session, %{world_state: world_state}) do
      {:ok, session}
    end
  end

  def delete_session(%GameSession{} = session) do
    Logger.warning("admin deleting session id=#{session.id} name=#{session.name}")
    Repo.delete(session)
  end

  def reset_session_npcs(%GameSession{} = session) do
    from(n in NpcInstance, where: n.game_session_id == ^session.id)
    |> Repo.delete_all()

    :ok = NPC.seed_session(session)

    case NPC.refresh_session_world_state(session) do
      {:ok, refreshed} -> {:ok, refreshed}
      error -> error
    end
  end

  def list_npc_instances(session_id) do
    NpcInstance
    |> where([n], n.game_session_id == ^session_id)
    |> order_by([n], asc: n.npc_id)
    |> Repo.all()
  end

  def get_npc_instance!(session_id, npc_id) do
    NpcInstance
    |> where([n], n.game_session_id == ^session_id and n.npc_id == ^npc_id)
    |> Repo.one!()
  end

  def update_npc_instance(%NpcInstance{} = instance, attrs) do
    instance
    |> NpcInstance.changeset(attrs)
    |> Repo.update()
  end

  def update_npc_runtime_state(%NpcInstance{} = instance, json_string)
      when is_binary(json_string) do
    with {:ok, runtime_state} <- decode_json_map(json_string),
         {:ok, instance} <- update_npc_instance(instance, %{runtime_state: runtime_state}) do
      {:ok, instance}
    end
  end

  def list_turns(session_id) do
    Turn
    |> where([t], t.game_session_id == ^session_id)
    |> order_by([t], desc: t.turn_number)
    |> Repo.all()
  end

  def get_turn!(session_id, turn_id) do
    Turn
    |> where([t], t.game_session_id == ^session_id and t.id == ^turn_id)
    |> Repo.one!()
  end

  def list_npc_definitions do
    @npc_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(&load_npc_definition_summary/1)
    |> Enum.sort_by(& &1.id)
  end

  def get_npc_definition!(npc_id) do
    path = npc_definition_path(npc_id)

    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
    else
      raise ArgumentError, "NPC definition '#{npc_id}' not found"
    end
  end

  def npc_definition_json(npc_id) do
    npc_id
    |> get_npc_definition!()
    |> Jason.encode!(pretty: true)
  end

  def save_npc_definition(npc_id, json_string) when is_binary(json_string) do
    with {:ok, definition} <- decode_json_map(json_string),
         :ok <- validate_npc_definition(definition),
         :ok <- write_npc_definition_file(npc_id, definition) do
      {:ok, definition}
    end
  end

  def encode_json(data) do
    Jason.encode!(data, pretty: true)
  end

  def decode_json_map(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, "JSON must be an object"}
      {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end

  defp turn_counts([]), do: %{}

  defp turn_counts(session_ids) do
    Turn
    |> where([t], t.game_session_id in ^session_ids)
    |> group_by([t], t.game_session_id)
    |> select([t], {t.game_session_id, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp session_location(%GameSession{world_state: world_state}) do
    world_state
    |> Kernel.||(%{})
    |> Map.get("location_name", Map.get(world_state || %{}, "location_id", "—"))
  end

  defp session_character_name(%GameSession{world_state: world_state}) do
    world_state
    |> Kernel.||(%{})
    |> get_in(["character", "name"])
    |> case do
      nil -> "—"
      name -> name
    end
  end

  defp load_npc_definition_summary(file) do
    definition = @npc_dir |> Path.join(file) |> File.read!() |> Jason.decode!()
    id = Map.get(definition, "id", Path.rootname(file))

    %{
      id: id,
      name: Map.get(definition, "name", id),
      role: Map.get(definition, "role", "—"),
      default_location_id: Map.get(definition, "default_location_id", "—"),
      file: file
    }
  end

  defp npc_definition_path(npc_id) do
    Path.join(@npc_dir, "#{npc_id}.json")
  end

  defp validate_npc_definition(definition) do
    cond do
      not is_map(definition) ->
        {:error, "Definition must be a JSON object"}

      blank?(Map.get(definition, "id")) ->
        {:error, "Definition requires id"}

      blank?(Map.get(definition, "name")) ->
        {:error, "Definition requires name"}

      true ->
        :ok
    end
  end

  defp write_npc_definition_file(npc_id, definition) do
    path = npc_definition_path(npc_id)
    tmp = path <> ".tmp"
    payload = Jason.encode!(definition, pretty: true) <> "\n"

    with :ok <- File.write(tmp, payload),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} -> {:error, "Could not save file: #{inspect(reason)}"}
    end
  end

  defp blank?(value), do: is_nil(value) or to_string(value) |> String.trim() == ""
end
