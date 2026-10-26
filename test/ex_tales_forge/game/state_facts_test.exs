defmodule TalesForge.Game.StateFactsTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.StateFacts

  doctest StateFacts

  # Gentry's character in playtest session 6e3b9541 (card 1, h-qa13/h-qa16).
  @gentry %{
    "name" => "GentryQa1026",
    "coins" => %{"silver" => 49, "copper" => 8},
    "inventory" => [
      %{"id" => "travel_cloak", "name" => "travel cloak"},
      %{"id" => "hunting_knife", "name" => "hunting knife", "quantity" => 1}
    ]
  }

  test "h-qa13/h-qa16: the coins and the pack, as the sheet has them" do
    assert StateFacts.lines(StateFacts.build(@gentry)) == [
             "Coins: 0g 49s 8c",
             "Pack: travel cloak, hunting knife"
           ]
  end

  test "an empty pack and purse are stated, not left out" do
    assert StateFacts.lines(StateFacts.build(%{})) == ["Coins: 0g 0s 0c", "Pack: empty"]
  end

  test "more than one of an item gives the count" do
    character = %{"inventory" => [%{"id" => "torch", "name" => "torch", "quantity" => 3}]}
    assert "Pack: torch (3)" in StateFacts.lines(StateFacts.build(character))
  end
end
