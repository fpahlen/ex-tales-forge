defmodule TalesForge.Locations.Position do
  @moduledoc """
  Where a character stands in a grid and which way it faces
  (docs/design-locations.md §5). Compass facing; row 0 is north.
  """

  alias TalesForge.Locations.Grid

  defstruct grid_id: nil, cell: nil, facing: :s

  @type facing :: :n | :e | :s | :w
  @type t :: %__MODULE__{grid_id: String.t(), cell: Grid.coord(), facing: facing()}

  @start_char "D"
  @offsets %{n: {0, -1}, e: {1, 0}, s: {0, 1}, w: {-1, 0}}

  @doc """
  The start position: on the main door (`D`), facing into the grid, away
  from the edge the door is on. Nil when the grid has no `D`.
  """
  @spec start(Grid.t()) :: t() | nil
  def start(%Grid{} = grid) do
    case Enum.find(Enum.sort(grid.cells), fn {_coord, cell} -> cell.char == @start_char end) do
      {coord, _cell} -> %__MODULE__{grid_id: grid.id, cell: coord, facing: inward(coord)}
      nil -> nil
    end
  end

  @doc "The neighbour of `coord` one cell toward `facing`."
  @spec neighbour(Grid.coord(), facing()) :: Grid.coord()
  def neighbour({x, y, z}, facing) do
    {dx, dy} = Map.fetch!(@offsets, facing)
    {x + dx, y + dy, z}
  end

  @doc "The four compass directions, in a fixed order."
  @spec compass() :: [facing()]
  def compass, do: [:n, :e, :s, :w]

  defp inward({_x, 0, _z}), do: :s
  defp inward({_x, 19, _z}), do: :n
  defp inward({0, _y, _z}), do: :e
  defp inward({_x, _y, _z}), do: :w
end
