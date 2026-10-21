defmodule TalesForge.NPCHardeningTest do
  use TalesForge.DataCase, async: false
  alias TalesForge.NPC.Rows

  alias TalesForge.GameSessions

  test "create_session seeds multiple NPC definitions" do
    assert {:ok, session} = GameSessions.create_session(%{name: "Multi NPC"})

    assert Rows.get(session.id, "marta_kellen")
    assert Rows.get(session.id, "worried_merchant")

    assert ["marta_kellen"] = session.world_state["present_npcs"]
    refute "worried_merchant" in session.world_state["present_npcs"]
  end
end
