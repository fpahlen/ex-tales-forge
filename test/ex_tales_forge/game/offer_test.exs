defmodule TalesForge.Game.OfferTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.{Offer, Trade}
  alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}
  alias TalesForge.GameCharacter

  doctest Offer

  test "an accepted offer is the trade, with nothing reworked" do
    brenna = %GameCharacter{name: "Brenna Holt", coins: %{"gold" => 2}}
    aric = %GameCharacter{name: "Aric", coins: %{"copper" => 9}}
    offer = %Offer{giver: brenna, item: %{"id" => "ale_mug"}, price: 2}

    assert %Trade{giver: ^brenna, receiver: ^aric, item: %{"id" => "ale_mug"}, price: 2} =
             Offer.to_trade(offer, aric)
  end

  describe "the open offer in the world state" do
    @stored %{
      "giver" => "innkeep",
      "giver_name" => "Brenna Holt",
      "item" => %{"id" => "ale_mug", "name" => "Ale", "quantity" => 1},
      "price" => 2,
      "options" => [],
      "location_id" => "valley_inn",
      "age" => 0
    }
    @here %{"character" => %{"location_id" => "valley_inn"}, "present_npcs" => ["innkeep"]}

    test "round-trips through to_world/1 and from_world/1" do
      assert @stored
             |> Offer.from_world()
             |> Map.put(:giver, %GameCharacter{slug: "innkeep", name: "Brenna Holt"})
             |> Offer.to_world() == @stored
    end

    test "expires when the player leaves its place or the giver is gone" do
      refute Offer.expired?(@stored, @here)
      assert Offer.expired?(@stored, put_in(@here, ["character", "location_id"], "smithy"))
      assert Offer.expired?(@stored, %{@here | "present_npcs" => []})
    end

    test "waits 2 unanswered turns" do
      assert %{"age" => 1} = aged = Offer.aged(@stored)
      assert Offer.aged(aged) == nil
    end

    test "an accept is the buy at the offer's price; other answers change nothing" do
      world = Map.put(@here, "open_offer", @stored)

      said = %PlayerAction{
        overall_intent: "Yes, one please.",
        action: %SingleAction{action_type: :speak}
      }

      assert %PlayerAction{
               offer_answer: :accept,
               action: %SingleAction{
                 action_type: :buy,
                 target: "innkeep",
                 parameters: %{"item_id" => "ale_mug", "quantity" => 1, "price_copper" => 2}
               }
             } = Offer.answered(%{said | offer_answer: :accept}, world)

      assert Offer.answered(%{said | offer_answer: :decline}, world).action.action_type == :speak
      assert Offer.answered(%{said | offer_answer: :other}, world).action.action_type == :speak
      left = put_in(world, ["character", "location_id"], "smithy")
      assert Offer.answered(%{said | offer_answer: :accept}, left).action.action_type == :speak
    end

    test "an unclear buy: a pick is that option, a plain accept the default, no pick nothing" do
      options = [
        %{"item" => %{"id" => "bread", "quantity" => 1}, "price" => 3},
        %{"item" => %{"id" => "stew", "quantity" => 1}, "price" => 5}
      ]

      world =
        Map.put(@here, "open_offer", %{
          @stored
          | "item" => nil,
            "price" => nil,
            "options" => options
        })

      said = %PlayerAction{
        overall_intent: "The stew.",
        action: %SingleAction{action_type: :speak}
      }

      assert Offer.answered(%{said | offer_pick: 1}, world).action.parameters["item_id"] == "stew"

      assert Offer.answered(%{said | offer_answer: :accept}, world).action.parameters["item_id"] ==
               "bread"

      assert Offer.answered(%{said | offer_answer: :other}, world).action.action_type == :speak
    end
  end
end
