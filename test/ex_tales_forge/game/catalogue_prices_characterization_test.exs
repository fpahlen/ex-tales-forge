defmodule TalesForge.Game.CataloguePricesCharacterizationTest do
  # Pins Catalogue give and Prices by_amount before refactor round 2 PR 11.
  use ExUnit.Case, async: true

  alias TalesForge.Game.Catalogue
  alias TalesForge.Game.Catalogue.Act
  alias TalesForge.World.Prices

  @world %{
    "character" => %{
      "coins" => %{"copper" => 5, "silver" => 1},
      "inventory" => [
        %{"id" => "rope", "name" => "Coil of rope"},
        %{"id" => "apple", "name" => "Apple"}
      ]
    },
    "present_npcs" => ["mara"]
  }

  @gives [
    {"mara", "I give her the coil of rope", nil,
     {%{
        "character" => %{
          "coins" => %{"copper" => 5, "silver" => 1},
          "inventory" => [
            %{"copper_value" => 0, "id" => "apple", "name" => "Apple", "quantity" => 1}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:ok, %{applied: [%{"item_id" => "rope", "kind" => "give", "to" => "mara"}]}}}},
    {"mara", "I hand Mara the apple and 3c", nil,
     {%{
        "character" => %{
          "coins" => %{"copper" => 5, "silver" => 1},
          "inventory" => [
            %{"copper_value" => 0, "id" => "rope", "name" => "Coil of rope", "quantity" => 1}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:ok, %{applied: [%{"item_id" => "apple", "kind" => "give", "to" => "mara"}]}}}},
    {"mara", "I give her 12 copper", nil,
     {%{
        "character" => %{
          "coins" => %{"copper" => 3},
          "inventory" => [
            %{"id" => "rope", "name" => "Coil of rope"},
            %{"id" => "apple", "name" => "Apple"}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:ok, %{applied: [%{"copper" => 12, "kind" => "give", "to" => "mara"}]}}}},
    {"mara", "I give her 16c", nil,
     {%{
        "character" => %{
          "coins" => %{"copper" => 5, "silver" => 1},
          "inventory" => [
            %{"id" => "rope", "name" => "Coil of rope"},
            %{"id" => "apple", "name" => "Apple"}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:error, "The character does not have 16c."}}},
    {"mara", "I give her a hug", nil,
     {%{
        "character" => %{
          "coins" => %{"copper" => 5, "silver" => 1},
          "inventory" => [
            %{"id" => "rope", "name" => "Coil of rope"},
            %{"id" => "apple", "name" => "Apple"}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:error, "The character does not carry that."}}},
    {"mara", "I give her 0c", nil,
     {%{
        "character" => %{
          "coins" => %{"copper" => 5, "silver" => 1},
          "inventory" => [
            %{"id" => "rope", "name" => "Coil of rope"},
            %{"id" => "apple", "name" => "Apple"}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:error, "The character does not carry that."}}},
    {"bran", "I give him the apple", nil,
     {%{
        "character" => %{
          "coins" => %{"copper" => 5, "silver" => 1},
          "inventory" => [
            %{"id" => "rope", "name" => "Coil of rope"},
            %{"id" => "apple", "name" => "Apple"}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:error, "Nobody by that name is here to take it."}}},
    {"mara", "I give her the apple", %{"name" => "Mara", "relationship_score" => -5},
     {%{
        "character" => %{
          "coins" => %{"copper" => 5, "silver" => 1},
          "inventory" => [
            %{"copper_value" => 0, "id" => "rope", "name" => "Coil of rope", "quantity" => 1}
          ]
        },
        "present_npcs" => ["mara"]
      }, {:ok, %{applied: [%{"item_id" => "apple", "kind" => "give", "to" => "mara"}]}}}}
  ]

  test "give: items, coins, refusals and errors" do
    for {npc_id, text, npc, expected} <- @gives do
      act = %Act{handler: %{handler: "give", target: npc_id}, text: text, npc: npc}
      assert Catalogue.apply(@world, act) == expected, text
    end
  end

  @agents [
    %{
      role: :here,
      facts: [
        %{"aliases" => ["stew"], "copper" => 5, "item" => "Bowl of stew", "kind" => "price"},
        %{"aliases" => ["ale"], "copper" => 2, "item" => "Mug of ale", "kind" => "price"},
        %{"aliases" => ["room"], "copper" => 30, "item" => "Private room", "kind" => "price"},
        %{"aliases" => ["bread"], "copper" => 1, "item" => "Bread", "kind" => "price"}
      ]
    }
  ]
  @purse %{"character" => %{"coins" => %{"silver" => 5}}}

  @paid [
    {"I pay five copper for the stew",
     {%{"character" => %{"coins" => %{"copper" => 5, "silver" => 4}}},
      ["Purchase: Bowl of stew, 5 copper, paid (server)"]}},
    {"I place five copper coins on the bar",
     {%{"character" => %{"coins" => %{"copper" => 5, "silver" => 4}}},
      ["Purchase: Bowl of stew, 5 copper, paid (server)"]}},
    {"I pay seven copper for the stew",
     {%{"character" => %{"coins" => %{"copper" => 3, "silver" => 4}}},
      [
        "Purchase: Bowl of stew, 5 copper, paid (server)",
        "Purchase: Mug of ale, 2 copper, paid (server)"
      ]}},
    {"Two copper it is for the ale, and the stew sounds good.",
     {%{"character" => %{"coins" => %{"copper" => 8, "silver" => 4}}},
      ["Purchase: Mug of ale, 2 copper, paid (server)"]}},
    {"I pay three silver and five copper for the room and the stew",
     {%{"character" => %{"coins" => %{"copper" => 5, "silver" => 1}}},
      [
        "Purchase: Bowl of stew, 5 copper, paid (server)",
        "Purchase: Private room, 3 silver, paid (server)"
      ]}},
    {"I pay for the room",
     {%{"character" => %{"coins" => %{"silver" => 2}}},
      ["Purchase: Private room, 3 silver, paid (server)"]}},
    {"How much is the ale?",
     {%{"character" => %{"coins" => %{"silver" => 5}}}, ["Price: Mug of ale, 2 copper"]}},
    {"I pay nine copper for the ale and the stew",
     {%{"character" => %{"coins" => %{"copper" => 3, "silver" => 4}}},
      [
        "Purchase: Bowl of stew, 5 copper, paid (server)",
        "Purchase: Mug of ale, 2 copper, paid (server)"
      ]}},
    {"I pay three copper for the ale",
     {%{"character" => %{"coins" => %{"copper" => 7, "silver" => 4}}},
      [
        "Purchase: Mug of ale, 2 copper, paid (server)",
        "Purchase: Bread, 1 copper, paid (server)"
      ]}},
    {"I pay one gold for the bread",
     {%{"character" => %{"coins" => %{"copper" => 9, "silver" => 4}}},
      ["Purchase: Bread, 1 copper, paid (server)"]}},
    {"I pay 3 copper for the ale and bread and stew",
     {%{"character" => %{"coins" => %{"copper" => 7, "silver" => 4}}},
      [
        "Purchase: Mug of ale, 2 copper, paid (server)",
        "Purchase: Bread, 1 copper, paid (server)"
      ]}},
    {"I pay four copper for the bread",
     {%{"character" => %{"coins" => %{"copper" => 9, "silver" => 4}}},
      ["Purchase: Bread, 1 copper, paid (server)"]}},
    {"I pay 40 copper for the stew",
     {%{"character" => %{"coins" => %{"copper" => 5, "silver" => 4}}},
      ["Purchase: Bowl of stew, 5 copper, paid (server)"]}}
  ]

  test "prices: the amount handed over picks what is paid for" do
    for {text, expected} <- @paid do
      turn = %Prices.Turn{world_before: @purse, raw_action: text}
      assert Prices.resolve(@agents, @purse, turn) == expected, text
    end
  end
end
