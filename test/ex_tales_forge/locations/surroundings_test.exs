defmodule TalesForge.Locations.SurroundingsTest do
  use ExUnit.Case, async: true

  alias TalesForge.Locations.Move
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Surroundings

  doctest TalesForge.Locations.Surroundings

  defp inn, do: Pack.grid(Pack.grids("tin_valley"), "valley_inn", 0)
  defp find(seen, item), do: Enum.filter(seen, &(&1.item == item))

  test "from the main door: the hearth ahead, the kitchen hidden behind the brickwork" do
    seen = Surroundings.of(inn(), Position.start(inn()))

    assert %{distance_m: 6.0, cell: {9, 6, 0}} =
             Enum.find(seen, &(&1.item == "open hearth" and &1.dir == :ahead))

    assert [%{dir: :left}] = find(seen, "stairs up")
    assert [%{dir: :right}] = find(seen, "barrels")
    assert [%{dir: :ahead}] = find(seen, "hearth brickwork")
    assert [_ | _] = find(seen, "inner door")
    assert find(seen, "kitchen hearth") == []
    assert find(seen, "storeroom") == []
    assert find(seen, "stairs down") == []
    assert find(seen, "wall") == [] and find(seen, "floor") == []
  end

  test "turning around swaps ahead and behind" do
    grid = inn()
    {:ok, at_hearth, _steps} = Move.approach(grid, Position.start(grid), "open hearth")

    facing = Surroundings.of(grid, at_hearth)
    turned = Surroundings.of(grid, Move.turn(at_hearth, :around))

    assert %{distance_m: 1.0} =
             Enum.find(facing, &(&1.item == "open hearth" and &1.dir == :ahead))

    assert %{distance_m: 1.0} =
             Enum.find(turned, &(&1.item == "open hearth" and &1.dir == :behind))

    assert [%{dir: :behind}] = find(facing, "main door")
    assert [%{dir: :ahead}] = find(turned, "main door")
    assert Enum.any?(find(facing, "bar desk"), &(&1.dir == :behind))
  end

  test "each item is listed once per direction, nearest first" do
    seen = Surroundings.of(inn(), Position.start(inn()))
    keys = Enum.map(seen, &{&1.item, &1.dir})
    assert keys == Enum.uniq(keys)

    assert Surroundings.text(seen) =~ ~r/^ahead: .*open hearth 6 m/
  end

  test "an opaque cell stops the view, a blocking but clear one does not" do
    grid = inn()

    window = %{
      grid
      | cells: Map.update!(grid.cells, {9, 6, 0}, &%{&1 | item: "window", opaque: false})
    }

    wall = %{
      grid
      | cells:
          Map.update!(grid.cells, {9, 1, 0}, &%{&1 | item: "wall", opaque: true, blocks: true})
    }

    assert [_] = find(Surroundings.of(window, Position.start(grid)), "window")
    assert Surroundings.of(wall, Position.start(grid)) == []
  end
end
