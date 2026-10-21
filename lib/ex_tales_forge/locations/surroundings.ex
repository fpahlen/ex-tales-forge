defmodule TalesForge.Locations.Surroundings do
  @moduledoc """
  What a character sees around it in its grid (docs/design-locations.md,
  step 1). Pure.

  The view is the area reachable from the character's cell through cells
  that aren't `opaque`, plus the opaque cells on its edge (so a wall or a
  closed door stops the view, a table or a window doesn't). No line of
  sight yet. Each item is placed ahead, right, behind or left of the facing
  by its larger offset, with the straight-line distance in metres rounded
  to 0.5 m; the nearest cell of each item in each direction is kept.
  Floor and wall are not listed.
  """

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Seen

  @unlisted ["floor", "wall"]
  @order %{ahead: 0, right: 1, behind: 2, left: 3}
  @forward %{n: {0, -1}, e: {1, 0}, s: {0, 1}, w: {-1, 0}}
  @right %{n: {1, 0}, e: {0, 1}, s: {-1, 0}, w: {0, -1}}

  @doc "The items the character at `pos` sees, nearest first in each direction."
  @spec of(Grid.t(), Position.t()) :: [Seen.t()]
  def of(%Grid{} = grid, %Position{} = pos) do
    grid
    |> view(pos.cell)
    |> Enum.filter(&listed?(grid, pos, &1))
    |> Enum.map(&seen(grid, pos, &1))
    |> nearest(pos)
  end

  defp listed?(grid, pos, cell),
    do: cell != pos.cell and Grid.at(grid, cell).item not in @unlisted

  defp nearest(seen, pos) do
    seen
    |> Enum.group_by(&{&1.item, &1.dir})
    |> Enum.map(fn {_key, all} -> Enum.min_by(all, &{squared(pos.cell, &1.cell), &1.cell}) end)
    |> Enum.sort_by(&{@order[&1.dir], &1.distance_m, &1.item})
  end

  @doc """
  The surroundings as prompt lines.

      iex> TalesForge.Locations.Surroundings.text([%TalesForge.Locations.Seen{item: "open hearth", dir: :ahead, distance_m: 6.0}])
      "ahead: open hearth 6 m"
  """
  @spec text([Seen.t()]) :: String.t()
  def text(seen) do
    seen
    |> Enum.chunk_by(& &1.dir)
    |> Enum.map_join("\n", fn [first | _] = same ->
      "#{first.dir}: " <> Enum.map_join(same, ", ", &item_text/1)
    end)
  end

  defp item_text(seen), do: "#{seen.item} #{metres(seen.distance_m)} m"

  defp metres(m) when m == trunc(m), do: Integer.to_string(trunc(m))
  defp metres(m), do: Float.to_string(m)

  defp seen(grid, pos, {x, y, _z} = cell) do
    {px, py, _pz} = pos.cell
    {dx, dy} = {x - px, y - py}
    distance = Float.round(:math.sqrt(dx * dx + dy * dy) * grid.cell_m * 2) / 2

    %Seen{
      item: Grid.at(grid, cell).item,
      dir: dir(pos.facing, dx, dy),
      distance_m: distance,
      cell: cell
    }
  end

  defp squared({px, py, _pz}, {x, y, _z}), do: (x - px) * (x - px) + (y - py) * (y - py)

  defp dir(facing, dx, dy) do
    {fx, fy} = @forward[facing]
    {rx, ry} = @right[facing]
    ahead = dx * fx + dy * fy
    right = dx * rx + dy * ry

    cond do
      abs(ahead) >= abs(right) and ahead > 0 -> :ahead
      abs(ahead) >= abs(right) -> :behind
      right > 0 -> :right
      true -> :left
    end
  end

  # Flood fill through cells that aren't opaque; opaque cells on the edge are seen.
  defp view(grid, start), do: flood(grid, [start], MapSet.new([start]))

  defp flood(_grid, [], seen), do: MapSet.to_list(seen)

  defp flood(grid, [cell | rest], seen) do
    new = Enum.filter(neighbours(grid, cell), &(not MapSet.member?(seen, &1)))
    seen = Enum.reduce(new, seen, &MapSet.put(&2, &1))
    flood(grid, rest ++ Enum.reject(new, &Grid.at(grid, &1).opaque), seen)
  end

  defp neighbours(grid, cell) do
    Position.compass()
    |> Enum.map(&Position.neighbour(cell, &1))
    |> Enum.filter(&Grid.at(grid, &1))
  end
end
