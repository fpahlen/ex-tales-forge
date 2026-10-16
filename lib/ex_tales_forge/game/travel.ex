defmodule TalesForge.Game.Travel do
  @moduledoc """
  Game time for a move from the place tree (board card 7aba0394, PR 2; flag
  HIERARCHICAL_LOCATIONS, session feature `"hierarchical_locations"`).

  A place can carry three optional keys in its frontmatter:

  - `at: [x, y]`: its position in its parent, in cells of the parent;
  - `cell_m`: the size of one of its own cells in metres;
  - `scale`: `building`, `settlement` or `region`. It gives the default
    `cell_m` (#{inspect(%{"building" => 2, "settlement" => 20, "region" => 200})}).

  The distance between two places is measured in their lowest common
  ancestor: each place is replaced by its ancestor that is a child of that
  ancestor, and the distance is the straight line between those `at`
  positions times the ancestor's `cell_m`. A move into or out of a place
  (child and parent) has distance 0. The walk speed is #{80} m a minute.

  The game time is the walk time rounded to the nearest 15-minute tick
  (`TalesForge.Game.WorldClock`). Thus a step inside a building or a village
  costs no tick, and travel at region scale costs ticks by distance.

  Pure: no Repo, no LLM.
  """

  alias TalesForge.Game.{Movement, WorldClock}

  @cell_m %{"building" => 2, "settlement" => 20, "region" => 200}
  @walk_m_per_minute 80

  @doc """
  The walk time in minutes from `from` to `to`, or nil when a place on the
  way has no position (the caller keeps the old cost).

      iex> world = %{"locations" => %{
      ...>   "region" => %{"scale" => "region"},
      ...>   "village" => %{"parent" => "region", "at" => [0, 0], "scale" => "settlement"},
      ...>   "mine" => %{"parent" => "region", "at" => [6, 8]},
      ...>   "inn" => %{"parent" => "village", "at" => [1, 1]},
      ...>   "square" => %{"parent" => "village", "at" => [2, 1]}}}
      iex> TalesForge.Game.Travel.minutes(world, "inn", "square")
      0
      iex> TalesForge.Game.Travel.minutes(world, "inn", "mine")
      25
      iex> TalesForge.Game.Travel.minutes(world, "inn", "village")
      0
  """
  @spec minutes(map(), String.t() | nil, String.t() | nil) :: non_neg_integer() | nil
  def minutes(world, from, to) when is_binary(from) and is_binary(to) do
    case meters(world, from, to) do
      nil -> nil
      m -> round(m / @walk_m_per_minute)
    end
  end

  def minutes(_world, _from, _to), do: nil

  @doc """
  The ticks a move costs: the walk time rounded to the nearest tick, or nil
  when the feature is off or a position is missing.

      iex> world = %{"features" => ["hierarchical_locations"], "locations" => %{
      ...>   "region" => %{"cell_m" => 500},
      ...>   "village" => %{"parent" => "region", "at" => [0, 0]},
      ...>   "mine" => %{"parent" => "region", "at" => [3, 4]}}}
      iex> TalesForge.Game.Travel.ticks(world, "village", "mine")
      2
      iex> TalesForge.Game.Travel.ticks(Map.delete(world, "features"), "village", "mine")
      nil
  """
  @spec ticks(map(), String.t() | nil, String.t() | nil) :: non_neg_integer() | nil
  def ticks(world, from, to) do
    with true <- Movement.tree?(world),
         minutes when is_integer(minutes) <- minutes(world, from, to) do
      round(minutes / WorldClock.minutes_per_tick())
    else
      _ -> nil
    end
  end

  @doc "The distance in metres between `from` and `to`, or nil (see the moduledoc)."
  @spec meters(map(), String.t(), String.t()) :: float() | nil
  def meters(world, from, to) do
    a = chain(world, from)
    b = chain(world, to)

    case Enum.find(a, &(&1 in b)) do
      nil ->
        nil

      common ->
        with {:ok, pa} <- position_in(world, a, common),
             {:ok, pb} <- position_in(world, b, common),
             cell when is_number(cell) <- cell_m(world, common) do
          distance(pa, pb) * cell
        else
          _ -> nil
        end
    end
  end

  # The place and its ancestors, nearest first.
  defp chain(world, id) do
    Stream.unfold(id, fn
      nil -> nil
      current -> {current, Movement.parent(world, current)}
    end)
    |> Enum.take(6)
  end

  # The position, in `common`, of the ancestor of the chain that is a child
  # of `common`. The common place itself stands at its entry, [0, 0].
  defp position_in(world, chain, common) do
    case Enum.take_while(chain, &(&1 != common)) do
      [] -> {:ok, {0, 0}}
      below -> at(world, List.last(below))
    end
  end

  defp at(world, id) do
    case get_in(Movement.places(world), [id, "at"]) do
      [x, y] when is_number(x) and is_number(y) -> {:ok, {x, y}}
      _ -> :error
    end
  end

  defp distance({x1, y1}, {x2, y2}), do: :math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2)

  @doc """
  The size of one cell of `id` in metres: its `cell_m`, else the default of
  its `scale`, else nil.

      iex> TalesForge.Game.Travel.cell_m(%{"locations" => %{"inn" => %{"scale" => "building"}}}, "inn")
      2
  """
  @spec cell_m(map(), String.t()) :: number() | nil
  def cell_m(world, id) do
    place = Map.get(Movement.places(world), id, %{})

    case place["cell_m"] do
      m when is_number(m) and m > 0 -> m
      _ -> Map.get(@cell_m, place["scale"])
    end
  end
end
