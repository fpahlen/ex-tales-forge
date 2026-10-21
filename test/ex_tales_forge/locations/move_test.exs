defmodule TalesForge.Locations.MoveTest do
  use ExUnit.Case, async: true

  alias TalesForge.Locations.Move
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Position

  defp inn, do: Pack.grid(Pack.grids("tin_valley"), "valley_inn", 0)

  defp walk(grid, pos, dirs) do
    Enum.reduce(dirs, pos, fn dir, at ->
      {:ok, next} = Move.step(grid, at, dir)
      next
    end)
  end

  test "a character starts on the main door, facing into the inn" do
    assert %Position{grid_id: "valley_inn", cell: {9, 0, 0}, facing: :s} = Position.start(inn())
  end

  test "walking from the door to the hearth ends at the hearth, facing it" do
    grid = inn()
    start = Position.start(grid)

    assert {:ok, %Position{cell: {9, 5, 0}, facing: :s} = at, steps} =
             Move.approach(grid, start, "open hearth")

    assert steps == [:s, :s, :s, :s, :s]
    assert walk(grid, start, List.duplicate(:ahead, 5)) == at
    assert Move.step(grid, at, :ahead) == {:blocked, "open hearth"}
  end

  test "walls and tables block; chairs do not" do
    grid = inn()
    door = Position.start(grid)

    assert Move.step(grid, door, :left) == {:blocked, "wall"}
    assert Move.step(grid, door, :back) == {:blocked, "edge"}

    at_table = %Position{door | cell: {4, 2, 0}, facing: :s}
    assert Move.step(grid, at_table, :ahead) == {:blocked, "table"}

    assert {:ok, %Position{cell: {6, 3, 0}}} =
             Move.step(grid, %Position{at_table | cell: {6, 2, 0}}, :ahead)
  end

  test "turning changes only the facing" do
    pos = Position.start(inn())
    assert Move.turn(pos, :left).facing == :e
    assert Move.turn(pos, :right).facing == :w
    assert Move.turn(pos, :around).facing == :n
    assert Move.turn(pos, :around).cell == pos.cell
  end

  test "an item behind walls with no way in is unreachable" do
    assert Move.approach(inn(), Position.start(inn()), "dragon") == :unreachable
  end
end
