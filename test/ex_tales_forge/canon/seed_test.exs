defmodule TalesForge.Canon.SeedTest do
  use ExUnit.Case, async: true

  alias TalesForge.Canon.Seed

  doctest Seed

  test "the Tin Valley seed has the pack places, the pack NPCs and the world_agents facts" do
    seed = Seed.load(%{"adventure_id" => "tin_valley"})

    assert %{name: "Valley Inn"} = seed.places["valley_inn"]
    assert seed.places["valley_inn"].exits == Enum.sort(seed.places["valley_inn"].exits)
    assert Enum.any?(seed.entities, fn {_id, e} -> e.kind == :npc end)
    assert Enum.any?(seed.entities["tin_valley_region"].facts, &(&1 =~ "orc nest"))
  end

  test "the Crossroads seed reads the built-in places" do
    seed = Seed.load(%{"adventure_id" => "crossroads_ledger"})
    assert Map.has_key?(seed.places, "weary_pilgrim")
    assert Map.has_key?(seed.entities, "marta_kellen")
  end

  test "an unknown adventure gives an empty seed" do
    assert %Seed{places: places, entities: entities} = Seed.load(%{"adventure_id" => "nope"})
    assert places == %{}
    assert entities == %{}
  end
end
