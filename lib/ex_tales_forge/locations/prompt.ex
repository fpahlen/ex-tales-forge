defmodule TalesForge.Locations.Prompt do
  @moduledoc """
  The surroundings line block for the GM prompt (`LOCATION_GRID`, step 1 of
  docs/design-locations.md). The place tree still says where the character
  is (`location_id`); when that place has a grid, the character stands on
  its main door, facing in, until a later step moves it.
  """

  alias TalesForge.Game.Context
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Surroundings

  @doc "What the character sees, as prompt lines; nil when its place has no grid."
  @spec surroundings(map()) :: String.t() | nil
  def surroundings(world) when is_map(world) do
    grids = world |> Context.adventure_id() |> Pack.grids()

    with %{} = grid <- Pack.grid(grids, world["location_id"], 0),
         %Position{} = pos <- Position.start(grid) do
      grid |> Surroundings.of(pos) |> Surroundings.text()
    end
  end
end
