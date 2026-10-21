defmodule TalesForge.AdminTest do
  use TalesForge.DataCase, async: false

  import Ecto.Query
  alias TalesForge.GameCharacter.Rows

  alias TalesForge.Admin
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{AICall, Character, FrontInstance, GameSession, SessionEvent}

  test "stats returns counts" do
    before = Admin.stats()
    {:ok, session} = GameSessions.create_session(%{name: "Stats Test"})
    {:ok, _} = Admin.update_session(session, %{status: "paused"})
    {:ok, _} = GameSessions.create_session(%{name: "Stats Test 2"})
    stats = Admin.stats()

    assert stats.sessions == before.sessions + 2
    assert stats.active_sessions == before.active_sessions + 1
    assert stats.npcs > before.npcs
    assert is_integer(stats.turns)
    assert is_integer(stats.scenes)
  end

  test "list_sessions is newest first" do
    {:ok, older} = GameSessions.create_session(%{name: "Older"})

    Repo.update_all(from(s in GameSession, where: s.id == ^older.id),
      set: [inserted_at: ~U[2020-01-01 00:00:00Z]]
    )

    {:ok, newer} = GameSessions.create_session(%{name: "Newer"})

    ids = Enum.map(Admin.list_sessions(), & &1.session.id)
    assert Enum.find_index(ids, &(&1 == newer.id)) < Enum.find_index(ids, &(&1 == older.id))
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

  test "delete_session cascades turns and NPCs" do
    {:ok, session} = GameSessions.create_session(%{name: "Delete Test"})
    assert length(Rows.list(session.id)) > 0
    assert :ok = Admin.delete_session(session)
    refute Repo.get(TalesForge.Schemas.GameSession, session.id)
    assert Admin.list_turns(session.id) == []
    assert Rows.list(session.id) == []
  end

  test "delete_session removes child rows and keeps ai_calls with a NULL session" do
    {:ok, session} = GameSessions.create_session(%{name: "Cascade Test"})

    Repo.insert!(
      SessionEvent.changeset(%SessionEvent{}, %{
        game_session_id: session.id,
        kind: "test",
        tick: 1
      })
    )

    call =
      Repo.insert!(
        AICall.changeset(%AICall{}, %{
          game_session_id: session.id,
          purpose: "test",
          model: "test-model",
          status: "ok",
          latency_ms: 1,
          call_type: "llm"
        })
      )

    assert :ok = Admin.delete_session(session)

    for schema <- [Character, SessionEvent, FrontInstance] do
      assert Repo.all(from r in schema, where: r.game_session_id == ^session.id) == []
    end

    assert %AICall{game_session_id: nil} = Repo.get!(AICall, call.id)
  end

  test "delete_session on an already deleted session is a no-op" do
    {:ok, session} = GameSessions.create_session(%{name: "Gone Test"})
    assert :ok = Admin.delete_session(session)
    assert :ok = Admin.delete_session(session)
  end

  test "the admin runtime save writes the NPC's columns and runtime, nothing else" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Form Test"})
    [npc | _] = Rows.list(session.id)
    json = Jason.encode!(Map.merge(npc.runtime_state, %{"mood" => "wary", "note" => "admin"}))

    assert {:ok, saved} = Admin.update_npc_runtime_state(npc, json)
    assert saved.runtime_state["mood"] == "wary"

    row = Repo.get!(Character, npc.row.id)
    assert {row.slug, row.mood, row.location_id} == {npc.npc_id, "wary", npc.row.location_id}
    assert row.runtime["note"] == "admin"
    assert row.definition == npc.row.definition

    assert {:error, _} = Admin.update_npc_runtime_state(npc, "not json")
  end

  test "update_npc_runtime_state refuses a copy read before the row changed" do
    {:ok, session} = GameSessions.create_session(%{name: "Stale NPC Edit"})
    [npc | _] = Rows.list(session.id)

    # A turn changes the row after the admin page read it.
    {:ok, _} = TalesForge.NPC.bump_relationship(session.id, npc.npc_id, 0.3)

    json =
      Jason.encode!(Map.merge(npc.runtime_state, %{"mood" => "wary", "coins" => %{"gold" => 9}}))

    assert {:error, :stale} = Admin.update_npc_runtime_state(npc, json)

    row = Rows.get(session.id, npc.npc_id).row
    assert {row.mood, row.coins} == {npc.row.mood, npc.row.coins}

    fresh = Rows.get(session.id, npc.npc_id)
    assert {:ok, saved} = Admin.update_npc_runtime_state(fresh, json)
    assert saved.runtime_state["mood"] == "wary"
  end

  test "get_npc returns nil for an unknown slug" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Lookup Test"})
    [npc | _] = Rows.list(session.id)
    assert Rows.get(session.id, npc.npc_id).row.id == npc.row.id
    assert Rows.get(session.id, "no_such_npc") == nil
  end

  test "reset_session_npcs reseeds the NPC rows" do
    {:ok, session} = GameSessions.create_session(%{name: "Reseed Test"})
    [npc | _] = Rows.list(session.id)
    Rows.update!(npc, Map.put(npc.runtime_state, "mood", "broken"))

    assert {:ok, _} = Admin.reset_session_npcs(session)
    refreshed = Rows.get(session.id, npc.npc_id)
    assert Map.get(refreshed.runtime_state, "mood") != "broken"
    assert TalesForge.Characters.get_by_slug(session.id, "elara_voss")
  end
end
