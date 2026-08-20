defmodule TalesForge.Game.Fronts do
  @moduledoc """
  Pure pack-front parse and validate. No Repo.

  Fail fast if a portent `spawns_front` is not present in the loaded fronts.
  """

  @required_keys ~w(id status)

  def parse_dir!(fronts_dir) when is_binary(fronts_dir) do
    unless File.dir?(fronts_dir) do
      raise ArgumentError, "fronts directory missing: #{fronts_dir}"
    end

    fronts_dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&parse_file!/1)
    |> validate!()
  end

  def parse_file!(path) when is_binary(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> validate_front!(path)
  end

  def validate!(fronts) when is_list(fronts) do
    Enum.each(fronts, &validate_front!(&1, "pack"))
    ids = MapSet.new(fronts, & &1["id"])

    fronts
    |> Enum.flat_map(fn front -> Enum.map(List.wrap(front["portents"]), &{front, &1}) end)
    |> Enum.each(&assert_spawn_present!(&1, ids))

    fronts
  end

  defp assert_spawn_present!({_front, portent}, ids) do
    spawn = portent["spawns_front"]

    if is_binary(spawn) and spawn != "" and not MapSet.member?(ids, spawn) do
      raise ArgumentError,
            "portent #{inspect(portent["id"])} spawns_front=#{inspect(spawn)} missing from fronts"
    end
  end

  defp validate_front!(front, source) when is_map(front) do
    Enum.each(@required_keys, fn key ->
      if front[key] in [nil, ""] do
        raise ArgumentError, "front #{source} missing #{key}"
      end
    end)

    status = front["status"]

    unless status in ["live", "dormant", "spent"] do
      raise ArgumentError, "front #{front["id"]} invalid status=#{inspect(status)}"
    end

    front
  end

  defp validate_front!(_, source), do: raise(ArgumentError, "front #{source} is not a map")
end
