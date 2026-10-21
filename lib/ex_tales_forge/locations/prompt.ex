defmodule TalesForge.Locations.Prompt do
  @moduledoc """
  The surroundings line block for the GM prompt (`LOCATION_GRID`,
  docs/design-locations.md): what the player character sees from its stored
  position (`TalesForge.Locations.Positions`), recomputed every turn.
  """

  alias TalesForge.Locations.Positions
  alias TalesForge.Locations.Surroundings

  @doc "What the player character sees, as prompt lines; nil when it has no position."
  @spec surroundings(map()) :: String.t() | nil
  def surroundings(world) do
    case Positions.view(world, get_in(world, ["character", "id"])) do
      {grid, pos} -> grid |> Surroundings.of(pos) |> Surroundings.text()
      nil -> nil
    end
  end
end
