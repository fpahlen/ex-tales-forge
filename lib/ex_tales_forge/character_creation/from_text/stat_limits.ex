defmodule TalesForge.CharacterCreation.FromText.StatLimits do
  @moduledoc """
  The point-buy limits for stats read from a description: the budget, the
  lowest and highest stat, and the race modifiers (a stat stays within the
  limits after its modifier).
  """
  alias TalesForge.Characters.RulesCheck

  defstruct budget: 0, lo: 0, hi: 0, modifiers: %{}

  @type stats :: %{optional(String.t()) => integer()}
  @type t :: %__MODULE__{budget: integer(), lo: integer(), hi: integer(), modifiers: stats()}

  @doc "The limits from the point-buy rules and the race modifiers."
  @spec new(map(), stats()) :: t()
  def new(%{"budget" => budget, "min" => lo, "max" => hi}, modifiers),
    do: %__MODULE__{budget: budget, lo: lo, hi: hi, modifiers: modifiers}

  @doc """
  The six stats: `wanted` where given, else `base`, each kept within the
  limits after its modifier, then fitted to the budget.
  """
  @spec fit(t(), stats(), stats()) :: stats()
  def fit(%__MODULE__{} = limits, wanted, base) do
    RulesCheck.stats()
    |> Map.new(&{&1, clamp(limits, &1, Map.get(wanted, &1, base[&1]))})
    |> fit_budget(limits)
  end

  defp clamp(%__MODULE__{lo: lo, hi: hi, modifiers: modifiers}, stat, value) do
    mod = Map.get(modifiers, stat, 0)
    value |> max(lo) |> max(lo - mod) |> min(hi) |> min(hi - mod)
  end

  # Lowers the highest stat by one until the stats fit the budget.
  defp fit_budget(stats, %__MODULE__{budget: budget} = limits) do
    if stats |> Map.values() |> Enum.sum() <= budget,
      do: stats,
      else: lower_highest(stats, limits)
  end

  defp lower_highest(stats, %__MODULE__{lo: lo, modifiers: modifiers} = limits) do
    stats
    |> Enum.filter(fn {stat, v} -> v > max(lo, lo - Map.get(modifiers, stat, 0)) end)
    |> Enum.max_by(fn {_stat, v} -> v end, fn -> nil end)
    |> case do
      nil -> stats
      {stat, v} -> fit_budget(Map.put(stats, stat, v - 1), limits)
    end
  end
end
