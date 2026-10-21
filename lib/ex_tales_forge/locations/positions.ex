defmodule TalesForge.Locations.Positions do
  @moduledoc """
  Where each character stands in its place's grid (docs/design-locations.md,
  step 2): `world_state["positions"]`, a `%Position{}` per character id (the
  player character and the GM characters alike). Pure.

  The positions are `%Position{}` structs everywhere inside the app; they
  are parsed and written only at the world_state boundary
  (`TalesForge.Locations.Positions.Json`).

  A character whose place has a grid and that has no position there yet
  stands on the main door, facing in (`settle/3`); a character whose place
  has no grid has no position.
  """

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Position

  @key "positions"

  @typedoc "Positions by character id."
  @type t :: %{String.t() => Position.t()}

  @doc "Where character `id` stands, or nil."
  @spec get(map(), String.t()) :: Position.t() | nil
  def get(world, id), do: world |> Map.get(@key, %{}) |> Map.get(id)

  @doc "The world with character `id` at `pos`, or without a position (nil)."
  @spec put(map(), String.t(), Position.t() | nil) :: map()
  def put(world, id, nil), do: Map.update(world, @key, %{}, &Map.delete(&1, id))

  def put(world, id, %Position{} = pos),
    do: Map.update(world, @key, %{id => pos}, &Map.put(&1, id, pos))

  @doc """
  The world with character `id` placed in `location_id`: its stored position
  when it is on that place's grid, else the grid's start (the main door,
  facing in), else no position.
  """
  @spec settle(map(), %{String.t() => [Grid.t()]}, {String.t(), String.t() | nil}) :: map()
  def settle(world, grids, {id, location_id}) do
    case get(world, id) do
      %Position{grid_id: ^location_id} -> world
      _other -> put(world, id, start(grids, location_id))
    end
  end

  defp start(grids, location_id) do
    case Pack.grid(grids, location_id, 0) do
      %Grid{} = grid -> Position.start(grid)
      nil -> nil
    end
  end
end
