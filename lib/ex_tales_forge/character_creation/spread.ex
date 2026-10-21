defmodule TalesForge.CharacterCreation.Spread do
  @moduledoc """
  A suggested spread build while `TalesForge.CharacterCreation` raises it:
  the skill `levels` so far, the `candidates` being raised, the fillers that
  may still join (`rest`), the skill points `left` and the creation skill
  rules (`sk`).
  """

  defstruct levels: %{}, candidates: [], rest: [], left: 0, sk: %{}

  @type t :: %__MODULE__{
          levels: %{String.t() => non_neg_integer()},
          candidates: [String.t()],
          rest: [String.t()],
          left: integer(),
          sk: map()
        }

  @doc "Puts each candidate at its free level (0 without one)."
  @spec start(t(), %{String.t() => non_neg_integer()}) :: t()
  def start(%__MODULE__{candidates: candidates} = spread, free),
    do: %{spread | levels: Map.new(candidates, &{&1, Map.get(free, &1, 0)})}

  @doc """
  Raises the lowest candidate one level step at a time, up to the normal cap,
  while points are left; when none can rise and points are left, the next
  filler joins at 0.
  """
  @spec raise_lowest(t()) :: t()
  def raise_lowest(%__MODULE__{left: left} = spread) do
    case {next(spread), spread.rest} do
      {nil, [filler | rest]} when left > 0 -> spread |> add(filler, rest) |> raise_lowest()
      {nil, _rest} -> spread
      {skill, _rest} -> spread |> step_up(skill) |> raise_lowest()
    end
  end

  defp next(%__MODULE__{levels: levels, candidates: candidates, left: left, sk: sk}) do
    step = Map.get(sk, "level_step", 1)

    candidates
    |> Enum.filter(&(levels[&1] < sk["cap"] and cost(sk, levels[&1], levels[&1] + step) <= left))
    |> Enum.min_by(&levels[&1], fn -> nil end)
  end

  defp add(%__MODULE__{levels: levels, candidates: candidates} = spread, filler, rest),
    do: %{
      spread
      | levels: Map.put(levels, filler, 0),
        candidates: candidates ++ [filler],
        rest: rest
    }

  defp step_up(%__MODULE__{levels: levels, left: left, sk: sk} = spread, skill) do
    step = Map.get(sk, "level_step", 1)
    price = cost(sk, levels[skill], levels[skill] + step)
    %{spread | levels: Map.update!(levels, skill, &(&1 + step)), left: left - price}
  end

  @doc "The skill points to go from level `from` to level `to` under the skill rules `sk`."
  @spec cost(map(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def cost(sk, from, to) when to > from do
    step = Map.get(sk, "level_step", 1)
    costs = sk["level_costs"]
    last = List.last(costs)

    Enum.sum(for l <- (from + 1)..to//1, do: Enum.at(costs, div(l - 1, step), last))
  end

  def cost(_sk, _from, _to), do: 0
end
