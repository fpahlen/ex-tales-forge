defmodule TalesForge.Locations.Positions.Json do
  @moduledoc """
  The JSON form of `world_state["positions"]` (`TalesForge.Locations.Positions`),
  used only at the world_state boundary (`TalesForge.Schemas.WorldState`
  load and dump). Inside the app a position is always a `%Position{}`; a
  stored position with a missing or bad field fails loudly here.
  """

  alias TalesForge.Locations.Position

  @key "positions"
  @facings %{"n" => :n, "e" => :e, "s" => :s, "w" => :w}

  @doc """
  A stored world with its positions parsed into `%Position{}` structs.
  Raises on a bad position.

      iex> TalesForge.Locations.Positions.Json.parse(%{"positions" => %{"pc" => %{"grid_id" => "inn", "cell" => [9, 1, 0], "facing" => "s"}}})
      %{"positions" => %{"pc" => %TalesForge.Locations.Position{grid_id: "inn", cell: {9, 1, 0}, facing: :s}}}
  """
  @spec parse(map()) :: map()
  def parse(%{@key => %{} = stored} = world),
    do: %{world | @key => Map.new(stored, fn {id, pos} -> {id, from_map(pos)} end)}

  def parse(world), do: world

  @doc "A world with its positions in their JSON form (the inverse of `parse/1`)."
  @spec json(map()) :: map()
  def json(%{@key => %{} = positions} = world),
    do: %{world | @key => Map.new(positions, fn {id, pos} -> {id, to_map(pos)} end)}

  def json(world), do: world

  @doc "The JSON form of one position."
  @spec to_map(Position.t()) :: map()
  def to_map(%Position{grid_id: grid_id, cell: {x, y, z}, facing: facing}),
    do: %{"grid_id" => grid_id, "cell" => [x, y, z], "facing" => Atom.to_string(facing)}

  defp from_map(%{"grid_id" => grid_id, "cell" => [x, y, z], "facing" => facing})
       when is_binary(grid_id) and is_integer(x) and is_integer(y) and is_integer(z),
       do: %Position{grid_id: grid_id, cell: {x, y, z}, facing: Map.fetch!(@facings, facing)}

  defp from_map(other), do: raise(ArgumentError, "bad stored position: #{inspect(other)}")
end

defimpl Jason.Encoder, for: TalesForge.Locations.Position do
  def encode(pos, opts),
    do: Jason.Encode.map(TalesForge.Locations.Positions.Json.to_map(pos), opts)
end
