defmodule TalesForge.Game.ClarifyTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.Clarify
  alias TalesForge.Game.Schemas.{IntentExtraction, SingleAction}

  doctest Clarify

  @packs "priv/adventures/tin_valley"

  # An NPC's details as the intent context carries them (Cast.details/1),
  # from the pack's own OCEAN, Maslow level and mood.
  defp from_pack(path) do
    file = path |> File.read!() |> Jason.decode!()

    %{
      "ocean" => get_in(file, ["motivations", "personality_traits"]),
      "maslow" => file["maslow"],
      "disposition" => get_in(file, ["motivations", "mood"])
    }
  end

  defp brenna, do: from_pack("#{@packs}/npcs/innkeep.json")
  defp hilde, do: from_pack("#{@packs}/extensions/inn_world/npcs/smith.json")

  describe "style from the asker's own data" do
    test "Brenna (pack: A 8, C 7, belonging, cheerful) is patient: helpful" do
      assert Clarify.patience(brenna()) == 8.6
      assert Clarify.style(brenna()) == :helpful
    end

    test "Hilde (pack: A 4, C 8, safety, uneasy) is impatient: a brush-off" do
      assert Clarify.patience(hilde()) == 2.6
      assert Clarify.style(hilde()) == :brusque
    end

    test "unmet low needs lower patience" do
      hungry = %{brenna() | "maslow" => "physiological"}
      assert Clarify.patience(hungry) == Clarify.patience(brenna()) - 4.0
      assert Clarify.style(hungry) == :brusque
    end

    test "mood shifts it a little, and a missing mood is neutral" do
      assert Clarify.patience(Map.delete(brenna(), "disposition")) == 7.6
      assert Clarify.patience(%{hilde() | "disposition" => "cheerful"}) == 4.6
    end
  end

  describe "decide/1" do
    defp buy_reading(params, target \\ "innkeep") do
      %{
        action: :buy,
        target: target,
        confidence: 0.95,
        top2: [:buy],
        action_probabilities: %{buy: 0.95},
        extraction: %IntentExtraction{
          overall_intent: "x",
          actions: [%SingleAction{action_type: :buy, target: target, parameters: params}]
        }
      }
    end

    @context %{
      "present_npcs" => ["innkeep"],
      "npc_details" => %{"innkeep" => %{"name" => "Brenna Holt"}},
      "npc_stock" => %{
        "innkeep" => [
          %{"id" => "stew_bowl", "name" => "Bowl of Stew", "price_copper" => 5, "quantity" => 3},
          %{"id" => "ale_mug", "name" => "Mug of Ale", "price_copper" => 2, "quantity" => 9}
        ]
      }
    }

    test "a buy at the seller naming nothing she sells clarifies between her stock" do
      assert {:clarify, c} =
               Clarify.decide(%Clarify.Input{
                 reading: buy_reading(%{}),
                 context: @context,
                 words: "I order a meal."
               })

      assert c.candidates == ["Mug of Ale (2c)", "Bowl of Stew (5c)"]
      assert {c.npc_id, c.npc, c.style} == {"innkeep", "Brenna Holt", :helpful}
    end

    test "a buy whose words name an item, or with an item, acts" do
      assert :act =
               Clarify.decide(%Clarify.Input{
                 reading: buy_reading(%{}),
                 context: @context,
                 words: "An ale, please."
               })

      assert :act =
               Clarify.decide(%Clarify.Input{
                 reading: buy_reading(%{"item_id" => "ale_mug"}),
                 context: @context
               })
    end

    # Live Jev's read of Gentry's v353 Tin Valley T14 (`TalesForge.JevLive`):
    # buy 0.64 or speak 0.36, no target, in the clarify band.
    test "the band's clarify lists the readings" do
      turn = {"tin_valley", 14}
      reading = Map.merge(buy_reading(%{}, nil), TalesForge.JevLive.reading(turn))
      words = TalesForge.JevLive.text(turn)

      assert {:clarify, %Clarify{candidates: ["buy", "talk to them"]}} =
               Clarify.decide(%Clarify.Input{reading: reading, band: :clarify, words: words})
    end

    test "an accept of an offer with options and no pick clarifies between the options" do
      offer = %{
        "giver" => "innkeep",
        "giver_name" => "Brenna Holt",
        "item" => nil,
        "price" => nil,
        "options" => [
          %{"item" => %{"id" => "bread_cheese", "name" => "Bread and Cheese"}, "price" => 2},
          %{"item" => %{"id" => "stew_bowl", "name" => "Bowl of Stew"}, "price" => 5}
        ]
      }

      reading = %{action: :speak, offer_answer: :accept, offer_pick: nil, probabilities: %{}}

      assert {:clarify, %Clarify{candidates: ["Bread and Cheese (2c)", "Bowl of Stew (5c)"]}} =
               Clarify.decide(%Clarify.Input{
                 reading: reading,
                 words: "Yes.",
                 context: %{"open_offer" => offer}
               })

      assert :act =
               Clarify.decide(%Clarify.Input{
                 reading: %{reading | offer_pick: 1},
                 words: "The stew.",
                 context: %{"open_offer" => offer}
               })
    end
  end
end
