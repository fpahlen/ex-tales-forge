defmodule TalesForge.Locations.ExitsTest do
  @moduledoc """
  Leaving a room with a grid (LOCATION_GRID): a way out goes through the
  door to the place tree's way out; a named place goes there. Includes
  Gentry's intent-eval cases h-qa05 (walk back to the inn), h-qa06 (run out
  of the inn) and h-qa09 (flee out the door) as regressions, read from
  `test/fixtures/intent_eval/items.jsonl`.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.GameSessions
  alias TalesForge.LocationTurns
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Positions

  doctest TalesForge.Locations.Exits

  @items "test/fixtures/intent_eval/items.jsonl"
  # Out of the inn's door (h-qa06/h-qa09 gold: either is acceptable).
  @street ["market_square", "inn_yard"]
  @door %Position{grid_id: "valley_inn", cell: {9, 0, 0}, facing: :s}

  setup do
    # As in the playtest: the grid and the places around the inn (INN_WORLD).
    System.put_env("LOCATION_GRID", "on")
    System.put_env("INN_WORLD", "on")

    on_exit(fn ->
      System.delete_env("LOCATION_GRID")
      System.delete_env("INN_WORLD")
    end)

    {:ok, session} = GameSessions.create_session(%{name: "Exits", adventure_id: "tin_valley"})
    %{id: session.id, pc: session.world_state["character"]["id"]}
  end

  test "flee out the door leaves the inn, whatever Jev aims the move at" do
    for target <- ["main door", nil] do
      {:ok, session} = GameSessions.create_session(%{name: "Flee", adventure_id: "tin_valley"})
      LocationTurns.play(session.id, {"I flee out the door into the street.", :move, target})
      world = GameSessions.get_session!(session.id).world_state
      assert world["location_id"] in @street, "target #{inspect(target)}"
      assert Positions.get(world, world["character"]["id"]) == nil
    end
  end

  test "walking to the main door stays in the inn", %{id: id, pc: pc} do
    LocationTurns.play(id, {"I walk to the hearth", :move, "open hearth"})
    LocationTurns.play(id, {"I walk over to the main door", :move, "main door"})
    world = GameSessions.get_session!(id).world_state
    assert world["location_id"] == "valley_inn"

    assert Position.neighbour(Positions.get(world, pc).cell, Positions.get(world, pc).facing) ==
             @door.cell
  end

  test "walk to the smithy from the inn ends at the smithy", %{id: id} do
    LocationTurns.play(id, {"I walk to the smithy.", :move, "smithy"})
    assert GameSessions.get_session!(id).world_state["location_id"] == "smithy"
  end

  describe "Gentry's eval cases" do
    test "h-qa09 and h-qa06: fleeing or running out of the inn leaves it" do
      for item_id <- ["h-qa09", "h-qa06"] do
        item = item(item_id)
        {:ok, session} = GameSessions.create_session(%{name: item_id, adventure_id: "tin_valley"})
        LocationTurns.play(session.id, {item["text"], :move, item["gold"]["target"]})
        location = GameSessions.get_session!(session.id).world_state["location_id"]
        assert location in item["gold"]["acceptable_targets"], "#{item_id}: #{location}"
      end
    end

    test "h-qa05: walk back to the inn from the square ends at the inn, on its door", %{
      id: id,
      pc: pc
    } do
      LocationTurns.play(id, {"I flee out the door into the street.", :move, nil})
      assert GameSessions.get_session!(id).world_state["location_id"] in @street

      item = item("h-qa05")
      LocationTurns.play(id, {item["text"], :move, item["gold"]["target"]})
      world = GameSessions.get_session!(id).world_state
      assert world["location_id"] == "valley_inn"
      assert Positions.get(world, pc) == @door
    end
  end

  defp item(id) do
    @items
    |> File.stream!()
    |> Enum.map(&Jason.decode!/1)
    |> Enum.find(&(&1["id"] == id))
  end
end
