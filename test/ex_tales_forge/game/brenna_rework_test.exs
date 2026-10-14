defmodule TalesForge.Game.BrennaReworkTest do
  @moduledoc """
  Brenna rework (decision 2026-10-07, Fredrik via Case): a warm, chatty barkeep
  who enjoys running the tavern, without the default brush-off; a lead by
  turn 2; GM prose cleanup.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{Pack, Prompts}
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.NPC

  setup do
    on_exit(fn -> for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id) end)
    :ok
  end

  defp brenna do
    "tin_valley" |> Pack.load() |> Map.fetch!(:npcs) |> Enum.find(&(&1["id"] == "innkeep"))
  end

  test "Brenna is a warm, chatty host: higher extraversion and agreeableness, calmer" do
    brenna = brenna()
    traits = brenna["motivations"]["personality_traits"]

    assert traits["extraversion"] == 8
    assert traits["agreeableness"] == 8
    assert traits["neuroticism"] == 3
    assert brenna["personality"] =~ "Warm, chatty"
    assert brenna["personality"] =~ "enjoys running the tavern"
    assert brenna["motivations"]["mood"] == "cheerful"
    refute brenna["motivations"]["current_concern"]["focus"] =~ "strangers"
    assert brenna["maslow"] == "belonging"
    assert [%{"focus" => "a lively, safe common room"}] = brenna["concerns"]
    assert length(brenna["hooks"]) == 4
  end

  test "a session's GM sections carry Brenna with her hooks" do
    {:ok, default} = GameSessions.create_session(%{adventure_id: "tin_valley"})

    new = NPC.format_gm_sections(default.id, ["innkeep"])
    assert new =~ ~s("hooks")
    assert new =~ "Osric Vane"
    assert new =~ ~s("mood": "cheerful")
    refute new =~ "armed strangers"
  end

  test "the GM prompt asks for a lead by turn 2 and clean, second-person prose" do
    gm = Prompts.gm_system()

    assert gm =~ "second turn at the latest"
    assert gm =~ ~s(An NPC's "hooks" are ready-made leads)
    assert gm =~ "do not default to suspicion, flat voices or brush-offs"
    assert gm =~ "Always second person"
    # Refined 2026-10-07 (no default echo; a rare deliberate echo is the exception).
    assert gm =~ "React, do not restate"
    assert gm =~ "Gestures and stock lines wear out"

    scene = Prompts.scene_system()
    assert scene =~ "a host greets a newcomer warmly"
  end
end
