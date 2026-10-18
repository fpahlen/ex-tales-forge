defmodule TalesForge.NPCHardeningTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.GameSessions
  alias TalesForge.NPC

  test "create_session seeds multiple NPC definitions" do
    assert {:ok, session} = GameSessions.create_session(%{name: "Multi NPC"})

    assert NPC.get_instance(session.id, "marta_kellen")
    assert NPC.get_instance(session.id, "worried_merchant")

    assert ["marta_kellen"] = session.world_state["present_npcs"]
    refute "worried_merchant" in session.world_state["present_npcs"]
  end
end
