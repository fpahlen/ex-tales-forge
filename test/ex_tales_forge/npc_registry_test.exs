defmodule TalesForge.NPCRegistryTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.NPC
  alias TalesForge.NPCRegistry
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, NpcInstance}

  setup do
    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
    end)

    :ok
  end

  test "create_session starts agent for present NPC at tavern" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Agents"})

    aid = NPCRegistry.agent_id(session.id, "marta_kellen")
    assert Jido.whereis(aid)
  end

  test "sync stops agent when NPC leaves player location" do
    assert {:ok, session} = insert_session_without_scene("NPC Travel")

    :ok = NPCRegistry.sync(session)
    aid = NPCRegistry.agent_id(session.id, "marta_kellen")
    assert Jido.whereis(aid)

    inst = NPC.get_instance(session.id, "marta_kellen")

    inst
    |> NpcInstance.changeset(%{
      runtime_state: Map.put(inst.runtime_state, "location_id", "crossroads_square")
    })
    |> Repo.update!()

    {:ok, _session} = NPC.refresh_session_world_state(session)

    session = GameSessions.get_session!(session.id)
    assert "marta_kellen" not in session.world_state["present_npcs"]

    :ok = NPCRegistry.sync(session.id)
    refute Jido.whereis(aid)
  end

  defp insert_session_without_scene(name) do
    attrs = %{
      name: name,
      status: "active",
      world_state:
        TalesForge.Game.World.default_world_state()
        |> Map.put("last_scene_location", "weary_pilgrim")
    }

    with {:ok, session} <-
           %GameSession{}
           |> GameSession.changeset(attrs)
           |> Repo.insert(),
         :ok <- TalesForge.NPC.seed_session(session),
         {:ok, session} <- TalesForge.NPC.refresh_session_world_state(session) do
      {:ok, session}
    end
  end
end
