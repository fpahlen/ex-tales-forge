defmodule TalesForge.Locations.Pack do
  @moduledoc """
  The grids of an adventure pack (docs/design-locations.md §10).

  A grid file is `world/grids/<scale>/<location_id>_z<z>.txt`, read through
  `world/legends/<scale>.json`. The location id ties it to the place tree
  (`TalesForge.Game.Pack`); a pack with no `world/grids/` has no grids.
  """

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Legend

  @doc "The grids of `adventure_id`, by location id. Raises on bad grid data."
  @spec grids(String.t()) :: %{String.t() => [Grid.t()]}
  def grids(adventure_id) when is_binary(adventure_id) do
    adventure_id |> world_dir() |> grids_in()
  end

  @doc "The grids under a pack's `world/` directory, by location id."
  @spec grids_in(Path.t()) :: %{String.t() => [Grid.t()]}
  def grids_in(world_dir) do
    world_dir
    |> Path.join("grids/*/*.txt")
    |> Path.wildcard()
    |> Enum.map(&load!(&1, world_dir))
    |> Enum.sort_by(& &1.z)
    |> Enum.group_by(& &1.id)
  end

  @doc "The grid of `location_id` at level `z`, or nil."
  @spec grid(%{String.t() => [Grid.t()]}, String.t(), integer()) :: Grid.t() | nil
  def grid(grids, location_id, z) do
    grids |> Map.get(location_id, []) |> Enum.find(&(&1.z == z))
  end

  defp load!(path, world_dir) do
    scale = path |> Path.dirname() |> Path.basename()
    meta = meta!(path)

    with {:ok, legend} <- legend(world_dir, scale),
         {:ok, grid} <- Grid.parse(File.read!(path), legend, meta) do
      grid
    else
      {:error, reason} -> raise ArgumentError, "bad grid #{path}: #{inspect(reason)}"
    end
  end

  defp meta!(path) do
    case Regex.run(~r/^(.+)_z(-?\d+)$/, Path.basename(path, ".txt")) do
      [_all, id, z] -> %{id: id, z: String.to_integer(z)}
      nil -> raise ArgumentError, "grid file #{path} is not <location_id>_z<z>.txt"
    end
  end

  defp legend(world_dir, scale) do
    [world_dir, "legends", scale <> ".json"]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
    |> Legend.parse()
  end

  defp world_dir(adventure_id),
    do: Path.join([:code.priv_dir(:ex_tales_forge), "adventures", adventure_id, "world"])
end
