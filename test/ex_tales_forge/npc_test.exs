defmodule TalesForge.NPCTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Schemas.GMStructuredResponse
  alias TalesForge.Game.WorldClock
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.NpcInstance

  setup do
    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
    end)

    :ok
  end

  test "create_session seeds NpcInstance rows from priv/npcs" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Seed"})

    inst =
      NpcInstance
      |> Repo.get_by(game_session_id: session.id, npc_id: "marta_kellen")

    assert inst
    assert inst.personality["name"] == "Marta Kellen"
    assert inst.runtime_state["location_id"] == "weary_pilgrim"
    assert "marta_kellen" in session.world_state["present_npcs"]

    henrik = NPC.get_instance(session.id, "worried_merchant")
    assert henrik.personality["name"] == "Henrik Bale"
    assert henrik.runtime_state["location_id"] == "crossroads_square"
  end

  test "apply_gm_updates appends npc memory" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Memory"})

    gm_result = %GMStructuredResponse{
      narrative: "",
      npc_memory_updates: [
        %{"npc_id" => "marta_kellen", "summary" => "Player asked about chalk marks."}
      ]
    }

    :ok = NPC.apply_gm_updates(session.id, gm_result, WorldClock.default_start_tick())

    inst = NPC.get_instance(session.id, "marta_kellen")
    [memory | _] = Map.get(inst.runtime_state, "memories", [])

    assert memory["summary"] =~ "chalk marks"
    assert memory["tick"] == WorldClock.default_start_tick()
  end

  test "sync_present_npcs only lists NPCs at current location" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Presence"})

    assert ["marta_kellen"] = NPC.sync_present_npcs(session.id, "weary_pilgrim")
    assert ["worried_merchant"] = NPC.sync_present_npcs(session.id, "crossroads_square")

    inst = NPC.get_instance(session.id, "marta_kellen")

    inst
    |> NpcInstance.changeset(%{
      runtime_state: Map.put(inst.runtime_state, "location_id", "crossroads_square")
    })
    |> Repo.update!()

    assert ["marta_kellen", "worried_merchant"] =
             NPC.sync_present_npcs(session.id, "crossroads_square")
             |> Enum.sort()

    assert [] = NPC.sync_present_npcs(session.id, "weary_pilgrim")
  end
end
