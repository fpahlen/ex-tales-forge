defmodule TalesForge.Game.EconomyTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.Economy
  alias TalesForge.Game.Pack

  doctest TalesForge.Game.Economy

  test "the world config of each adventure holds the formula wage" do
    for adventure <- ~w(tin_valley) do
      world = Pack.materialize(adventure)
      assert world["economy"]["unskilled_wage_copper_per_hour"] == Economy.formula_wage()
      assert Economy.unskilled_wage(world) == 3
    end
  end
end
