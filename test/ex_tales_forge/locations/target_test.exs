defmodule TalesForge.Locations.TargetTest do
  use ExUnit.Case, async: true

  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Target

  doctest TalesForge.Locations.Target

  setup_all do
    %{grid: Pack.grid(Pack.grids("tin_valley"), "valley_inn", 0)}
  end

  for {words, item} <- [
        {"the bar", "bar desk"},
        {"I walk over to the fire", "open hearth"},
        {"hearth", "open hearth"},
        {"go sit in a chair", "chair"},
        {"the kitchen door", "kitchen back door"},
        {"head downstairs to the cellar", "stairs down"},
        {"the main door", "main door"}
      ] do
    test "#{inspect(words)} is the #{item}", %{grid: grid} do
      assert Target.resolve(grid, unquote(words)) == {:ok, unquote(item)}
    end
  end

  test "words for nothing on the grid are unknown", %{grid: grid} do
    assert Target.resolve(grid, "the dragon") == :unknown
    assert Target.resolve(grid, "the smithy") == :unknown
  end

  test "the aliases come from the pack's legend data", %{grid: grid} do
    assert "bar" in TalesForge.Locations.Grid.at(grid, {2, 1, 0}).aliases
    assert TalesForge.Locations.Grid.at(grid, {0, 0, 0}).aliases == []
  end
end
