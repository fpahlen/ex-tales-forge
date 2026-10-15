defmodule TalesForge.Game.Economy do
  @moduledoc """
  World economy values that come from the labour-anchored price formula
  (`priv/rules/economy.md`, "In Our System"): **1c = ~20 minutes of unskilled
  work**. One hour of unskilled labour goes through the formula:
  60 / 20 = **3 copper per hour**.

  The world config holds the value (`unskilled_wage_copper_per_hour` in the
  adventure front matter, copied to `world_state["economy"]`). A world
  without the key uses the formula. Modifiers for skill, danger and region
  come later (`docs/decisions.md`, 2026-10-12).
  """

  @unskilled_minutes_per_copper 20

  @doc """
  The unskilled hourly wage in copper.

      iex> TalesForge.Game.Economy.unskilled_wage(%{})
      3
      iex> TalesForge.Game.Economy.unskilled_wage(%{"economy" => %{"unskilled_wage_copper_per_hour" => 4}})
      4
  """
  @spec unskilled_wage(map()) :: pos_integer()
  def unskilled_wage(world) when is_map(world) do
    case get_in(world, ["economy", "unskilled_wage_copper_per_hour"]) do
      wage when is_integer(wage) and wage > 0 -> wage
      _ -> formula_wage()
    end
  end

  @doc "The wage from the formula: 60 minutes / #{@unskilled_minutes_per_copper} minutes per copper."
  @spec formula_wage() :: pos_integer()
  def formula_wage, do: div(60, @unskilled_minutes_per_copper)
end
