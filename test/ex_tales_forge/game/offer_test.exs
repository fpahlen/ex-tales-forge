defmodule TalesForge.Game.OfferTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.{Offer, Trade}
  alias TalesForge.GameCharacter

  doctest Offer

  test "an accepted offer is the trade, with nothing reworked" do
    brenna = %GameCharacter{name: "Brenna Holt", coins: %{"gold" => 2}}
    aric = %GameCharacter{name: "Aric", coins: %{"copper" => 9}}
    offer = %Offer{giver: brenna, item: %{"id" => "ale_mug"}, price: 2}

    assert %Trade{giver: ^brenna, receiver: ^aric, item: %{"id" => "ale_mug"}, price: 2} =
             Offer.to_trade(offer, aric)
  end
end
