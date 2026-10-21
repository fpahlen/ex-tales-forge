defmodule TalesForge.Locations.View do
  @moduledoc """
  The grid a character stands in and its stored position there
  (`TalesForge.Locations.Positions`), read from the pack of the world's
  adventure.
  """

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Positions

  @doc "The grid character `id` stands in and its position there, or nil."
  @spec of(map(), String.t() | nil) :: {Grid.t(), Position.t()} | nil
  def of(world, id) do
    with %Position{grid_id: grid_id, cell: {_x, _y, z}} = pos <- Positions.get(world, id),
         adventure_id when is_binary(adventure_id) <- world["adventure_id"],
         %Grid{} = grid <- adventure_id |> Pack.grids() |> Pack.grid(grid_id, z) do
      {grid, pos}
    end
  end
end
