defmodule TalesForge.Locations.Grid do
  @moduledoc """
  One 20×20 grid at one level `z` (docs/design-locations.md §2–3).

  Parsed from an ASCII block, one character per cell, read through the
  scale's `TalesForge.Locations.Legend`. Row 0 is north; `y` grows south.
  """

  alias TalesForge.Locations.Cell
  alias TalesForge.Locations.Legend

  @size 20

  defstruct id: nil, scale: nil, cell_m: 1, z: 0, cells: %{}

  @type coord :: {integer(), integer(), integer()}
  @type t :: %__MODULE__{
          id: String.t(),
          scale: String.t(),
          cell_m: number(),
          z: integer(),
          cells: %{coord() => Cell.t()}
        }

  @doc "The grid side, in cells."
  @spec size() :: pos_integer()
  def size, do: @size

  @doc """
  A grid from its ASCII block. `meta` has the grid's `:id` and `:z`.

      iex> {:ok, legend} = TalesForge.Locations.Legend.parse(%{"scale" => "room", "items" => %{"." => %{"item" => "floor"}}})
      iex> ascii = String.duplicate(String.duplicate(".", 20) <> "\\n", 20)
      iex> {:ok, grid} = TalesForge.Locations.Grid.parse(ascii, legend, %{id: "yard", z: 0})
      iex> TalesForge.Locations.Grid.at(grid, {0, 0, 0}).item
      "floor"
  """
  @spec parse(String.t(), Legend.t(), %{id: String.t(), z: integer()}) ::
          {:ok, t()} | {:error, term()}
  def parse(ascii, %Legend{} = legend, meta) do
    rows = ascii |> String.split("\n") |> Enum.reject(&(&1 == ""))

    with :ok <- check_size(rows),
         {:ok, cells} <- cells(rows, legend, meta.z) do
      {:ok,
       %__MODULE__{
         id: meta.id,
         scale: legend.scale,
         cell_m: legend.cell_m,
         z: meta.z,
         cells: cells
       }}
    end
  end

  @doc "The cell at `coord`, or nil off the grid."
  @spec at(t(), coord()) :: Cell.t() | nil
  def at(%__MODULE__{} = grid, coord), do: Map.get(grid.cells, coord)

  @doc "The cells holding `item`, in reading order."
  @spec find(t(), String.t()) :: [coord()]
  def find(%__MODULE__{} = grid, item) do
    grid.cells
    |> Enum.filter(fn {_coord, cell} -> cell.item == item end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort_by(fn {x, y, z} -> {z, y, x} end)
  end

  defp check_size(rows) do
    if length(rows) == @size and Enum.all?(rows, &(String.length(&1) == @size)),
      do: :ok,
      else: {:error, :not_20x20}
  end

  defp cells(rows, legend, z) do
    coded = rows |> Enum.with_index() |> Enum.flat_map(&row(&1, z))

    case Enum.find(coded, &unknown?(&1, legend)) do
      nil -> {:ok, Map.new(coded, &cell(&1, legend))}
      {{x, y, _z}, char} -> {:error, {:unknown_char, char, {x, y}}}
    end
  end

  defp row({line, y}, z) do
    line
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, x} -> {{x, y, z}, char} end)
  end

  defp unknown?({_coord, char}, legend), do: not Map.has_key?(legend.items, char)
  defp cell({coord, char}, legend), do: {coord, Cell.new(char, legend)}
end
