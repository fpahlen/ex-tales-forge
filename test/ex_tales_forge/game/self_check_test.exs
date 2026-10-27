defmodule TalesForge.Game.SelfCheckTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.{SelfCheck, StateFacts}
  alias TalesForge.Game.SelfCheck.Result

  doctest SelfCheck

  describe "asks/1 reads a question about the player's own coins or pack" do
    for {text, asks} <- [
          # h-qa13, h-qa16, h-o03: the playtest questions the GM missed
          {"What did I order earlier and what does my pack contain?", [:pack]},
          {"I check: how many coins do I have exactly, and did I just sell anything?", [:coins]},
          {"Can you remind me what's in my inventory?", [:pack]},
          # h-qa19..24
          {"How much money do I have left?", [:coins]},
          {"What's in my bag?", [:pack]},
          {"I buy an ale and count my coins", [:coins]},
          {"Hur mycket pengar har jag?", [:coins]},
          {"I search my pack for rope", [:pack]},
          {"How much gold do I have, and what am I carrying?", [:coins, :pack]},
          {"I check my purse.", [:coins]},
          {"Vad har jag i packningen?", [:pack]}
        ] do
      test "#{inspect(text)} -> #{inspect(asks)}" do
        assert SelfCheck.asks(unquote(text)) == unquote(asks)
      end
    end
  end

  describe "asks/1 misses rather than misfires" do
    for text <- [
          "Marta, what's in your stock?",
          "Did anyone mention a road toll? Do I owe anyone money?",
          "How much for a mug of ale?",
          "I pay two copper for the ale.",
          "I sell my hunting knife to Brenna.",
          "I put the rope in my pack and leave.",
          "How much money does Henrik owe the guild?",
          "What's in the chest?",
          "I give Marta my coins.",
          "I order a mug of ale from the barkeep and pay for it.",
          # An action, not a question (Case, PR 2 review)
          "Empty my pockets onto the table."
        ] do
      test "#{inspect(text)} -> []" do
        assert SelfCheck.asks(unquote(text)) == []
      end
    end

    test "blank or non-text input asks nothing" do
      assert SelfCheck.asks("") == []
      assert SelfCheck.asks(nil) == []
    end
  end

  describe "the Jev question" do
    test "has one label per eval label, and each reads back as its asks" do
      {_text, labels} = SelfCheck.question()

      assert labels |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort() ==
               Enum.sort(SelfCheck.labels())

      assert SelfCheck.from_label(:none) == []
      assert SelfCheck.from_label(:coins) == [:coins]
      assert SelfCheck.from_label(:pack) == [:pack]
      assert SelfCheck.from_label(:both) == [:coins, :pack]
      assert SelfCheck.from_label(nil) == nil
    end
  end

  describe "resolve/2 answers from the sheet facts" do
    setup do
      facts =
        StateFacts.build(%{
          "coins" => %{"silver" => 49, "copper" => 8},
          "inventory" => [%{"id" => "travel_cloak", "name" => "travel cloak"}]
        })

      %{facts: facts}
    end

    test "only what was asked is filled in", %{facts: facts} do
      assert SelfCheck.resolve(facts, [:coins]) == %Result{coins: "no gold, 49 silver, 8 copper"}
      assert SelfCheck.resolve(facts, [:pack]) == %Result{pack: "travel cloak"}

      assert SelfCheck.resolve(facts, [:coins, :pack]) ==
               %Result{coins: "no gold, 49 silver, 8 copper", pack: "travel cloak"}
    end

    test "nothing asked resolves to the empty result", %{facts: facts} do
      assert SelfCheck.resolve(facts, []) == %Result{}
    end

    test "zero amounts are words, not 0c (h-qa16, h-qa19)" do
      coins = fn c -> SelfCheck.resolve(StateFacts.build(%{"coins" => c}), [:coins]).coins end

      assert coins.(%{"gold" => 2, "silver" => 10}) == "2 gold, 10 silver, no copper"
      assert coins.(%{"gold" => 2, "silver" => 9, "copper" => 8}) == "2 gold, 9 silver, 8 copper"
      assert coins.(%{"copper" => 0}) == "no coins"
      assert coins.(%{}) == "no coins"
    end

    test "an empty pack is stated, not left out" do
      assert SelfCheck.resolve(StateFacts.build(%{}), [:pack]) == %Result{pack: "empty"}
    end
  end

  test "label/1 names the eval gold: none, coins, pack or both" do
    assert Enum.map([[], [:coins], [:pack], [:coins, :pack]], &SelfCheck.label/1) ==
             ~w(none coins pack both)

    assert SelfCheck.labels() == ~w(none coins pack both)
  end
end
