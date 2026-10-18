defmodule TalesForge.Game.InventoryTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Inventory
  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Game.World
  alias TalesForge.GameCharacter
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.Turn

  describe "coin and item primitives" do
    test "coin math" do
      assert Inventory.coin_total_copper(%{"gold" => 1, "silver" => 1, "copper" => 1}) == 511
      assert Inventory.deduct_coins(%{"copper" => 10}, 3) == %{"copper" => 7}
      assert Inventory.coin_total_copper(Inventory.add_coins(%{"copper" => 10}, 5)) == 15
    end

    test "stackable items merge on add and remove" do
      items =
        Inventory.normalize_items([%{"id" => "ale_mug", "name" => "Mug of Ale", "quantity" => 1}])

      items =
        Inventory.add_item(items, %{"id" => "ale_mug", "name" => "Mug of Ale", "quantity" => 2})

      assert Inventory.item_quantity(items, "ale_mug") == 3
      items = Inventory.remove_item(items, "ale_mug", 2)
      assert Inventory.item_quantity(items, "ale_mug") == 1
    end

    test "validate drop requires inventory" do
      character = %GameCharacter{inventory: [], coins: %{"copper" => 10}}

      assert {:error, _} =
               Inventory.validate_transaction(%Inventory.Transaction{
                 world_state: %{"character" => GameCharacter.to_sheet(character)},
                 location_id: "here",
                 action: %SingleAction{
                   action_type: :drop,
                   target: "wooden_shield",
                   parameters: %{"item_id" => "wooden_shield"}
                 },
                 character: character
               })
    end
  end

  describe "apply_transaction/3" do
    setup do
      world = sample_world()

      {:ok, world: world}
    end

    test "drop moves item from inventory to ground", %{world: world} do
      action = %SingleAction{
        action_type: :drop,
        target: "wooden_shield",
        parameters: %{"item_id" => "wooden_shield", "quantity" => 1}
      }

      assert {:ok, updated, %{applied: applied}, []} =
               Inventory.apply_transaction(world, %{}, action)

      assert "dropped 1x wooden_shield" in applied

      assert Inventory.item_quantity(get_in(updated, ["character", "inventory"]), "wooden_shield") ==
               0

      ground =
        updated
        |> get_in(["locations", "weary_pilgrim", "ground_items"])
        |> Inventory.normalize_items()

      assert Inventory.item_quantity(ground, "wooden_shield") == 1
    end

    test "pickup moves item from ground to inventory", %{world: world} do
      drop = %SingleAction{
        action_type: :drop,
        target: "wooden_shield",
        parameters: %{"item_id" => "wooden_shield", "quantity" => 1}
      }

      {:ok, dropped, _, []} = Inventory.apply_transaction(world, %{}, drop)

      pickup = %SingleAction{
        action_type: :pickup,
        target: "wooden_shield",
        parameters: %{"item_id" => "wooden_shield", "quantity" => 1}
      }

      assert {:ok, updated, %{applied: applied}, []} =
               Inventory.apply_transaction(dropped, %{}, pickup)

      assert "picked up 1x wooden_shield" in applied

      assert Inventory.item_quantity(get_in(updated, ["character", "inventory"]), "wooden_shield") ==
               1
    end

    test "spend deducts coins only", %{world: world} do
      action = %SingleAction{
        action_type: :spend,
        target: "marta_kellen",
        parameters: %{"amount_copper" => 2}
      }

      before = Inventory.coin_total_copper(get_in(world, ["character", "coins"]))

      assert {:ok, updated, %{applied: applied}, []} =
               Inventory.apply_transaction(world, %{}, action)

      assert applied == ["spent 2c"]

      after_total = Inventory.coin_total_copper(get_in(updated, ["character", "coins"]))
      assert after_total == before - 2
      assert length(get_in(updated, ["character", "inventory"])) == 2
    end

    test "failed drop leaves world unchanged", %{world: world} do
      action = %SingleAction{
        action_type: :drop,
        target: "missing_sword",
        parameters: %{"item_id" => "missing_sword", "quantity" => 1}
      }

      assert {:error, _} = Inventory.apply_transaction(world, %{}, action)
    end

    test "ground trade exchanges items", %{world: world} do
      world =
        put_in(
          world,
          ["locations", "weary_pilgrim", "ground_items"],
          [
            %{
              "id" => "common_wine",
              "name" => "Bottle of Common Wine",
              "copper_value" => 15,
              "quantity" => 1
            }
          ]
        )

      action = %SingleAction{
        action_type: :trade,
        parameters: %{
          "give" => [%{"id" => "hunting_knife", "quantity" => 1}],
          "receive" => [%{"id" => "common_wine", "quantity" => 1}],
          "counterparty" => "ground"
        }
      }

      assert {:ok, updated, %{applied: applied}, []} =
               Inventory.apply_transaction(world, %{}, action)

      assert Enum.any?(applied, &String.contains?(&1, "gave"))
      assert Enum.any?(applied, &String.contains?(&1, "received"))

      inventory = get_in(updated, ["character", "inventory"]) |> Inventory.normalize_items()

      ground =
        get_in(updated, ["locations", "weary_pilgrim", "ground_items"])
        |> Inventory.normalize_items()

      assert Inventory.item_quantity(inventory, "hunting_knife") == 0
      assert Inventory.item_quantity(inventory, "common_wine") == 1
      assert Inventory.item_quantity(ground, "hunting_knife") == 1
      assert Inventory.item_quantity(ground, "common_wine") == 0
    end
  end

  describe "buy with NPC stock" do
    test "buy deducts coins and adds item" do
      {:ok, session} = GameSessions.create_session(%{name: "Inventory Buy"})
      world = session.world_state

      action = %SingleAction{
        action_type: :buy,
        target: "marta_kellen",
        parameters: %{
          "item_id" => "ale_mug",
          "quantity" => 1,
          "price_copper" => 2,
          "npc_id" => "marta_kellen"
        }
      }

      before = Inventory.coin_total_copper(get_in(world, ["character", "coins"]))

      traders =
        NPC.traders(session.id, Inventory.trader_ids(action, world["present_npcs"] || []))

      assert {:ok, updated, %{applied: applied}, [trader]} =
               Inventory.apply_transaction(world, traders, action)

      assert Enum.any?(applied, &String.contains?(&1, "bought"))

      after_total = Inventory.coin_total_copper(get_in(updated, ["character", "coins"]))
      assert after_total == before - 2

      inventory = get_in(updated, ["character", "inventory"]) |> Inventory.normalize_items()
      assert Inventory.item_quantity(inventory, "ale_mug") == 1

      assert %GameCharacter{slug: "marta_kellen"} = trader
      assert Inventory.item_quantity(trader.inventory, "ale_mug") == 98
    end

    test "a serving of ale from the innkeep costs 2c and is drunk there" do
      {:ok, session} =
        GameSessions.create_session(%{name: "Tin Valley Mug", adventure_id: "tin_valley"})

      world = session.world_state

      action = %SingleAction{
        action_type: :buy,
        target: "innkeep",
        parameters: %{
          "item_id" => "ale_mug",
          "quantity" => 1,
          "price_copper" => 2,
          "npc_id" => "innkeep"
        }
      }

      before = Inventory.coin_total_copper(get_in(world, ["character", "coins"]))

      traders =
        NPC.traders(session.id, Inventory.trader_ids(action, world["present_npcs"] || []))

      assert {:ok, updated, %{applied: applied}, [trader]} =
               Inventory.apply_transaction(world, traders, action)

      assert Enum.any?(applied, &String.contains?(&1, "bought"))

      after_total = Inventory.coin_total_copper(get_in(updated, ["character", "coins"]))
      assert after_total == before - 2

      inventory = get_in(updated, ["character", "inventory"]) |> Inventory.normalize_items()
      assert Inventory.item_quantity(inventory, "ale_mug") == 0

      assert %GameCharacter{slug: "innkeep"} = trader
      assert Inventory.item_quantity(trader.inventory, "ale_mug") == 71
    end
  end

  describe "trades between two GameCharacters" do
    setup do
      trader = %GameCharacter{
        slug: "smith",
        name: "Smith",
        inventory: [
          %{"id" => "rope", "name" => "Rope", "price_copper" => 7, "quantity" => 2},
          %{"id" => "lantern", "name" => "Lantern", "price_copper" => 30, "quantity" => 1}
        ]
      }

      {:ok, world: sample_world(), traders: %{"smith" => trader}}
    end

    test "a buy moves the item out of the trader's inventory", %{world: world, traders: traders} do
      action = %SingleAction{
        action_type: :buy,
        target: "smith",
        parameters: %{"item_id" => "rope"}
      }

      assert {:ok, updated, %{applied: ["bought 1x rope for 7c"]}, [smith]} =
               Inventory.apply_transaction(world, traders, action)

      assert smith.slug == "smith"
      assert Inventory.item_quantity(smith.inventory, "rope") == 1
      assert Inventory.item_quantity(smith.inventory, "lantern") == 1
      assert Inventory.coin_total_copper(updated["character"]["coins"]) == 43

      assert %{"id" => "rope", "copper_value" => 7, "quantity" => 1} =
               Enum.find(updated["character"]["inventory"], &(&1["id"] == "rope"))
    end

    test "a buy finds the trader by item when the words name none", %{
      world: world,
      traders: traders
    } do
      action = %SingleAction{action_type: :buy, parameters: %{"item_id" => "lantern"}}

      assert {:error, "Elara Voss cannot pay 30c for Lantern."} =
               Inventory.apply_transaction(
                 put_in(world, ["character", "coins"], %{"copper" => 5}),
                 traders,
                 action
               )

      assert {:ok, _updated, _details, [%GameCharacter{slug: "smith"} = smith]} =
               Inventory.apply_transaction(world, traders, action)

      assert Inventory.item_quantity(smith.inventory, "lantern") == 0
    end

    test "a trade takes the receive legs out of the counterparty's inventory", %{
      world: world,
      traders: traders
    } do
      action = %SingleAction{
        action_type: :trade,
        parameters: %{
          "give" => [%{"id" => "wooden_shield", "quantity" => 1}],
          "receive" => [%{"id" => "rope", "quantity" => 2}],
          "counterparty" => "smith"
        }
      }

      assert {:ok, updated, _details, [smith]} =
               Inventory.apply_transaction(world, traders, action)

      assert Inventory.item_quantity(smith.inventory, "rope") == 0
      assert Inventory.item_quantity(updated["character"]["inventory"], "rope") == 2
      assert Inventory.item_quantity(updated["character"]["inventory"], "wooden_shield") == 0
    end

    test "a sell puts the item in the buyer's inventory and the buyer pays", %{
      world: world,
      traders: traders
    } do
      traders = put_in(traders, ["smith"], %{traders["smith"] | coins: %{"silver" => 5}})

      action = %SingleAction{
        action_type: :sell,
        target: "smith",
        parameters: %{"item_id" => "wooden_shield", "price_copper" => 40}
      }

      assert {:ok, updated, %{applied: ["sold 1x wooden_shield for 40c"]}, [smith]} =
               Inventory.apply_transaction(world, traders, action)

      assert Inventory.coin_total_copper(updated["character"]["coins"]) == 90
      assert Inventory.coin_total_copper(smith.coins) == 10
      assert Inventory.item_quantity(smith.inventory, "wooden_shield") == 1
    end

    test "the rest of the character's sheet is kept", %{world: world, traders: traders} do
      world = put_in(world, ["character", "class"], "warrior")

      action = %SingleAction{
        action_type: :buy,
        target: "smith",
        parameters: %{"item_id" => "rope"}
      }

      assert {:ok, updated, _details, _changed} =
               Inventory.apply_transaction(world, traders, action)

      assert Map.drop(updated["character"], ~w(inventory coins)) ==
               Map.drop(world["character"], ~w(inventory coins))
    end
  end

  describe "NPC traders" do
    test "an NPC's stock is its inventory, and put_inventories/2 saves it" do
      {:ok, session} =
        GameSessions.create_session(%{name: "Tin Valley Trader", adventure_id: "tin_valley"})

      assert %{"innkeep" => %GameCharacter{slug: "innkeep"} = innkeep} =
               NPC.traders(session.id, ["innkeep", "nobody"])

      assert Enum.all?(innkeep.inventory, &is_integer(&1["price_copper"]))
      ale = Enum.find(innkeep.inventory, &(&1["id"] == "ale_mug"))

      sold = %{innkeep | inventory: Inventory.remove_item(innkeep.inventory, "ale_mug", 3)}
      assert :ok = NPC.put_inventories(session.id, [sold])

      assert %{"innkeep" => reloaded} = NPC.traders(session.id, ["innkeep"])
      assert reloaded.inventory == sold.inventory

      assert Inventory.item_quantity(reloaded.inventory, "ale_mug") ==
               ale["quantity"] - 3
    end
  end

  describe "turn integration" do
    test "submit drop action updates ground items in persisted world state" do
      {:ok, session} = GameSessions.create_session(%{name: "Inventory Drop"})

      assert {:ok, %{status: :processing}} =
               GameSessions.submit_message(session.id, "drop my hunting knife")

      session = GameSessions.get_session!(session.id)

      inventory =
        get_in(session.world_state, ["character", "inventory"]) |> Inventory.normalize_items()

      ground =
        get_in(session.world_state, ["locations", "weary_pilgrim", "ground_items"])
        |> Inventory.normalize_items()

      assert Inventory.item_quantity(inventory, "hunting_knife") == 0
      assert Inventory.item_quantity(ground, "hunting_knife") == 1

      [turn] = Turn |> Repo.all() |> Enum.filter(&(&1.game_session_id == session.id))
      assert turn.player_action == "drop my hunting knife"
    end
  end

  defp sample_world do
    World.default_world_state()
    |> put_in(
      ["character", "inventory"],
      [
        %{
          "id" => "wooden_shield",
          "name" => "Wooden Shield",
          "copper_value" => 80,
          "quantity" => 1
        },
        %{
          "id" => "hunting_knife",
          "name" => "Hunting Knife",
          "copper_value" => 100,
          "quantity" => 1
        }
      ]
    )
    |> put_in(["character", "coins"], %{"copper" => 50})
  end
end
