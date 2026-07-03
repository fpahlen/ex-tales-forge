defmodule TalesForge.Game.IntentTest do
  use ExUnit.Case, async: false

  alias TalesForge.Game.Intent

  @context %{
    "exits" => ["crossroads_square", "pilgrim_cellar"],
    "exit_names" => %{
      "crossroads_square" => "Crossroads Square",
      "pilgrim_cellar" => "Pilgrim Cellar"
    },
    "present_npcs" => ["marta_kellen"],
    "npc_details" => %{
      "marta_kellen" => %{"name" => "Marta Kellen", "role" => "barkeep"}
    }
  }

  setup do
    on_exit(fn -> System.delete_env("XAI_API_KEY") end)
    System.put_env("XAI_API_KEY", "test-key")
    :ok
  end

  test "resolve_bundle uses heuristic for clear observe action" do
    {bundle, source} = Intent.resolve_bundle("look around the tavern", @context)

    assert source == :heuristic
    assert bundle.confidence >= 0.85
    assert hd(bundle.actions).action_type == :observe
  end

  test "resolve_bundle uses heuristic for speak to NPC" do
    {bundle, source} =
      Intent.resolve_bundle("I ask Marta what the chalk marks mean", @context)

    assert source == :heuristic
    assert hd(bundle.actions).action_type == :speak
  end
end
