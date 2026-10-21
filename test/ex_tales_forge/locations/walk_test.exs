defmodule TalesForge.Locations.WalkTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.JevIntent
  alias TalesForge.GameSessions
  alias TalesForge.LocationTurns
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Positions
  alias TalesForge.Locations.Walk

  doctest TalesForge.Locations.Walk

  @door %Position{grid_id: "valley_inn", cell: {9, 0, 0}, facing: :s}

  describe "resolve/3" do
    setup do: %{grid: Pack.grid(Pack.grids("tin_valley"), "valley_inn", 0)}

    test "door to hearth to bar, each time facing the target", %{grid: grid} do
      assert {:moved, at_hearth} = Walk.resolve(grid, @door, "the fire")
      assert TalesForge.Locations.Grid.at(grid, ahead(at_hearth)).item == "open hearth"

      assert {:moved, at_bar} = Walk.resolve(grid, at_hearth, "bar")
      assert TalesForge.Locations.Grid.at(grid, ahead(at_bar)).item == "bar desk"
    end

    test "words for nothing in the room move nothing", %{grid: grid} do
      assert Walk.resolve(grid, @door, "I walk to the dragon") == {:no_move, "dragon"}
    end

    test "an item that can't be reached moves nothing" do
      {:ok, legend} =
        TalesForge.Locations.Legend.parse(%{
          "scale" => "room",
          "items" => %{
            "." => %{"item" => "floor"},
            "#" => %{"item" => "wall", "blocks" => true},
            "X" => %{"item" => "chest", "blocks" => true}
          }
        })

      walled =
        "###" <> String.duplicate(".", 17) <> "\n" <> "#X#" <> String.duplicate(".", 17) <> "\n"

      rest = "###" <> String.duplicate(".", 17) <> "\n"
      rows = walled <> rest <> String.duplicate(String.duplicate(".", 20) <> "\n", 17)
      {:ok, grid} = TalesForge.Locations.Grid.parse(rows, legend, %{id: "room", z: 0})
      start = %Position{grid_id: "room", cell: {10, 10, 0}, facing: :n}
      assert Walk.resolve(grid, start, "the chest") == {:no_move, "chest"}
    end
  end

  describe "turns with LOCATION_GRID" do
    setup do
      System.put_env("LOCATION_GRID", "on")
      on_exit(fn -> System.delete_env("LOCATION_GRID") end)
      {:ok, session} = GameSessions.create_session(%{name: "Walk", adventure_id: "tin_valley"})
      %{id: session.id, pc: session.world_state["character"]["id"]}
    end

    test "door to hearth to bar persists across two turns", %{id: id, pc: pc} do
      LocationTurns.play(id, {"I walk over to the hearth", :move, "open hearth"})
      at_hearth = position(id, pc)
      assert at_hearth.cell != @door.cell
      assert faces?(at_hearth, "open hearth")
      assert GameSessions.get_session!(id).world_state["location_id"] == "valley_inn"

      {_turn, prompt} = LocationTurns.play(id, {"I go to the bar", :move, "bar desk"})
      at_bar = position(id, pc)
      assert faces?(at_bar, "bar desk")
      assert prompt =~ ~r/^ahead: .*bar desk/m
    end

    test "an unknown target moves nothing and the GM is told", %{id: id, pc: pc} do
      LocationTurns.play(id, {"look around", :observe, nil})
      {turn, prompt} = LocationTurns.play(id, {"I walk to the dragon", :move, nil})
      assert position(id, pc) == @door
      assert Enum.any?(turn.premise.findings, &(&1.correction == "You can't see a dragon here."))
      assert prompt =~ "You can't see a dragon here."
    end

    test "Jev is offered the room's spots as move targets", %{id: id} do
      LocationTurns.play(id, {"look around", :observe, nil})
      context = TalesForge.Game.Context.build_intent_context(GameSessions.get_session!(id))
      assert "open hearth" in context["spots"]

      assert Enum.any?(
               JevIntent.candidates(context),
               &(&1.kind == :spot and &1.id == "bar desk")
             )
    end
  end

  defp position(id, pc), do: Positions.get(GameSessions.get_session!(id).world_state, pc)

  defp faces?(pos, item) do
    grid = Pack.grid(Pack.grids("tin_valley"), "valley_inn", 0)
    TalesForge.Locations.Grid.at(grid, ahead(pos)).item == item
  end

  defp ahead(pos), do: Position.neighbour(pos.cell, pos.facing)
end
