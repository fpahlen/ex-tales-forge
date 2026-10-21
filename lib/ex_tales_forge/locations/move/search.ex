defmodule TalesForge.Locations.Move.Search do
  @moduledoc """
  The state of `TalesForge.Locations.Move.approach/3`'s breadth-first
  search: the cells still to visit, the cells seen and the next layer.
  """

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Position

  defstruct grid: nil, targets: MapSet.new(), queue: [], seen: MapSet.new(), next: []

  @type t :: %__MODULE__{}

  @doc "Lines up the free, unseen neighbours of `cell`, `steps` away, and marks them seen."
  @spec expand(t(), Grid.coord(), [Position.facing()]) :: t()
  def expand(%__MODULE__{} = search, cell, steps) do
    found =
      Enum.filter(
        Enum.map(Position.compass(), &{Position.neighbour(cell, &1), &1}),
        &open?(search, &1)
      )

    seen = Enum.reduce(found, search.seen, fn {to, _facing}, acc -> MapSet.put(acc, to) end)
    %__MODULE__{search | seen: seen, next: Enum.map(found, fn {to, f} -> {to, steps ++ [f]} end)}
  end

  @doc "Appends the lined-up layer to the queue."
  @spec push(t()) :: t()
  def push(%__MODULE__{} = search),
    do: %__MODULE__{search | queue: search.queue ++ search.next, next: []}

  defp open?(search, {to, _facing}),
    do: not MapSet.member?(search.seen, to) and free?(Grid.at(search.grid, to))

  defp free?(%{blocks: false}), do: true
  defp free?(_cell), do: false
end
