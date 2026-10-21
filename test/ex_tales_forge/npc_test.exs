defmodule TalesForge.NPCTest do
  use TalesForge.DataCase, async: false
  alias TalesForge.NPC.Rows

  alias TalesForge.Game.Schemas.GMStructuredResponse
  alias TalesForge.Game.WorldClock
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.Character

  doctest TalesForge.NPC.Person
  doctest TalesForge.Characters.Attrs

  test "create_session seeds the NPCs' character rows from priv/npcs" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Seed"})

    row = Repo.get_by(Character, game_session_id: session.id, slug: "marta_kellen")
    assert row.controller == "gm"
    assert row.origin == %{"source" => "pack", "definition_id" => "marta_kellen"}
    assert row.location_id == "weary_pilgrim"
    assert row.relationships == %{"elara_voss" => 0.0}
    assert row.runtime["memories"] == []

    inst = Rows.get(session.id, "marta_kellen")
    assert inst.personality["name"] == "Marta Kellen"
    assert inst.runtime_state["location_id"] == "weary_pilgrim"
    assert "marta_kellen" in session.world_state["present_npcs"]

    henrik = Rows.get(session.id, "worried_merchant")
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

    inst = Rows.get(session.id, "marta_kellen")
    [memory | _] = Map.get(inst.runtime_state, "memories", [])

    assert memory["summary"] =~ "chalk marks"
    assert memory["tick"] == WorldClock.default_start_tick()
  end

  test "sync_present_npcs only lists NPCs at current location" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Presence"})

    assert ["marta_kellen"] = NPC.sync_present_npcs(session.id, "weary_pilgrim")
    assert ["worried_merchant"] = NPC.sync_present_npcs(session.id, "crossroads_square")

    inst = Rows.get(session.id, "marta_kellen")

    Rows.update!(inst, Map.put(inst.runtime_state, "location_id", "crossroads_square"))

    assert ["marta_kellen", "worried_merchant"] =
             NPC.sync_present_npcs(session.id, "crossroads_square")
             |> Enum.sort()

    assert [] = NPC.sync_present_npcs(session.id, "weary_pilgrim")
  end
end
