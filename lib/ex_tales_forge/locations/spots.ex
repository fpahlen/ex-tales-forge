defmodule TalesForge.Locations.Spots do
  @moduledoc """
  The spots in the player character's room: the legend items on its grid
  that it can walk to (docs/design-locations.md, step 2). Put in the intent
  context as `"spots"` only when the character has a grid position
  (`LOCATION_GRID`), with every name of them as `"spot_names"`
  (`TalesForge.Locations.Target.names/1`), so Jev can read "I walk to the hearth" as a move to a
  spot, and contexts without a grid stay as they were.
  """

  alias TalesForge.Config
  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Positions
  alias TalesForge.Locations.Target
  alias TalesForge.Locations.View

  @unlisted ["floor", "wall"]

  @doc "The context with `\"spots\"` when the player character stands in a grid."
  @spec put(map(), map()) :: map()
  def put(context, world) do
    with true <- Config.location_grid?(),
         {grid, _pos} <- world |> placed() |> View.of(get_in(world, ["character", "id"])) do
      Map.merge(context, %{"spots" => names(grid), "spot_names" => Target.names(grid)})
    else
      _none -> context
    end
  end

  # The world with the player character settled on its place's grid.
  defp placed(%{"adventure_id" => adventure_id, "character" => %{"id" => id}} = world),
    do: Positions.settle(world, Pack.grids(adventure_id), {id, world["location_id"]})

  defp placed(world), do: world

  @doc "The distinct items on `grid` a character can walk to, sorted."
  @spec names(Grid.t()) :: [String.t()]
  def names(%Grid{cells: cells}) do
    cells
    |> Map.values()
    |> Enum.map(& &1.item)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in @unlisted))
    |> Enum.sort()
  end
end
