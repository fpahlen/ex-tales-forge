defmodule TalesForge.AdminTest do
  use TalesForge.DataCase, async: false

  import Ecto.Query

  alias TalesForge.Admin
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.NpcInstance

  test "stats returns counts" do
    {:ok, _} = GameSessions.create_session(%{name: "Stats Test"})
    stats = Admin.stats()
    assert stats.sessions >= 1
    assert is_integer(stats.turns)
  end

  test "list_sessions includes turn count" do
    {:ok, session} = GameSessions.create_session(%{name: "List Test"})

    assert [%{session: %{id: id}, turn_count: 0}] =
             Enum.filter(Admin.list_sessions(), &(&1.session.id == session.id))

    assert id == session.id
  end

  test "update_session_world_state validates json" do
    {:ok, session} = GameSessions.create_session(%{name: "JSON Test"})
    assert {:error, _} = Admin.update_session_world_state(session, "not json")
    assert {:ok, updated} = Admin.update_session_world_state(session, ~s({"location_id": "test"}))
    assert updated.world_state["location_id"] == "test"
  end

  test "delete_session cascades turns and npc instances" do
    {:ok, session} = GameSessions.create_session(%{name: "Delete Test"})
    assert length(Admin.list_npc_instances(session.id)) > 0
    assert {:ok, _} = Admin.delete_session(session)
    refute Repo.get(TalesForge.Schemas.GameSession, session.id)
    assert Admin.list_turns(session.id) == []
    assert Repo.all(from n in NpcInstance, where: n.game_session_id == ^session.id) == []
  end

  test "reset_session_npcs reseeds instances" do
    {:ok, session} = GameSessions.create_session(%{name: "Reseed Test"})
    [npc | _] = Admin.list_npc_instances(session.id)

    {:ok, _} =
      Admin.update_npc_instance(npc, %{
        runtime_state: Map.put(npc.runtime_state, "mood", "broken")
      })

    assert {:ok, _} = Admin.reset_session_npcs(session)
    refreshed = Admin.get_npc_instance!(session.id, npc.npc_id)
    assert Map.get(refreshed.runtime_state, "mood") != "broken"
  end

  test "npc definitions round trip" do
    [summary | _] = Admin.list_npc_definitions()
    json = Admin.npc_definition_json(summary.id)
    assert json =~ summary.id

    definition = Admin.get_npc_definition!(summary.id)
    original_name = definition["name"]

    try do
      definition = Map.put(definition, "name", "Admin Test Name")
      payload = Jason.encode!(definition)
      assert {:ok, saved} = Admin.save_npc_definition(summary.id, payload)
      assert saved["name"] == "Admin Test Name"
    after
      definition = Admin.get_npc_definition!(summary.id)
      definition = Map.put(definition, "name", original_name)
      Admin.save_npc_definition(summary.id, Jason.encode!(definition))
    end
  end
end
