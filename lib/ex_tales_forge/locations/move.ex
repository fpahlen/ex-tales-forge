defmodule TalesForge.Locations.Move do
  @moduledoc """
  Neighbour steps inside one grid (docs/design-locations.md §5). Pure.

  A step goes one cell ahead, back, left or right of the facing and turns
  the character that way. Cells whose legend item `blocks` (walls, tables,
  the hearth) can't be entered; chairs, doors and stairs can.
  """

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Move.Search
  alias TalesForge.Locations.Position

  @type dir :: :ahead | :back | :left | :right

  @turns %{ahead: 0, right: 1, back: 2, left: 3}

  @doc "One step toward `dir`; `{:blocked, item}` into a blocking cell or off the grid (`\"edge\"`)."
  @spec step(Grid.t(), Position.t(), dir()) :: {:ok, Position.t()} | {:blocked, String.t()}
  def step(%Grid{} = grid, %Position{} = pos, dir) do
    facing = rotate(pos.facing, Map.fetch!(@turns, dir))
    to = Position.neighbour(pos.cell, facing)

    case Grid.at(grid, to) do
      nil -> {:blocked, "edge"}
      %{blocks: true} = cell -> {:blocked, cell.item}
      _cell -> {:ok, %Position{pos | cell: to, facing: facing}}
    end
  end

  @doc "Turns in place."
  @spec turn(Position.t(), :left | :right | :around) :: Position.t()
  def turn(%Position{} = pos, :left), do: %Position{pos | facing: rotate(pos.facing, 3)}
  def turn(%Position{} = pos, :right), do: %Position{pos | facing: rotate(pos.facing, 1)}
  def turn(%Position{} = pos, :around), do: %Position{pos | facing: rotate(pos.facing, 2)}

  @doc """
  Walks the shortest way to the nearest free cell next to `item` and faces
  it. Returns the end position and the compass steps taken, or
  `:unreachable`.
  """
  @spec approach(Grid.t(), Position.t(), String.t()) ::
          {:ok, Position.t(), [Position.facing()]} | :unreachable
  def approach(%Grid{} = grid, %Position{} = pos, item) do
    targets = MapSet.new(Grid.find(grid, item))

    search = %Search{
      grid: grid,
      targets: targets,
      queue: [{pos.cell, []}],
      seen: MapSet.new([pos.cell])
    }

    case search(search) do
      {cell, steps, facing} -> {:ok, %Position{pos | cell: cell, facing: facing}, steps}
      nil -> :unreachable
    end
  end

  # Breadth-first over free cells; the first cell with a target next to it wins.
  defp search(%Search{queue: []}), do: nil

  defp search(%Search{queue: [{cell, steps} | queue]} = search) do
    case Enum.find(Position.compass(), &(Position.neighbour(cell, &1) in search.targets)) do
      nil ->
        search
        |> Search.expand(cell, steps)
        |> Map.put(:queue, queue)
        |> Search.push()
        |> search()

      facing ->
        {cell, steps, facing}
    end
  end

  defp rotate(facing, quarter_turns) do
    compass = Position.compass()
    index = Enum.find_index(compass, &(&1 == facing))
    Enum.at(compass, rem(index + quarter_turns, 4))
  end
end
