defmodule TalesForge.Game.TradeTest do
  @moduledoc """
  A buy or a sale is one exchange between the character and an NPC: the
  item goes one way and its price in coins the other, both or neither, and
  no item or coin is made or lost. Gentry's playtest session 643b8031 on
  2026-10-18 (after #446): "I sell my travel cloak to Brenna Holt" took
  the cloak off the sheet, paid nothing, and the GM narrated four silver.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{ActionHandler, Inventory, TurnProcessor, World}
  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction, SingleAction}
  alias TalesForge.Game.Turn.Board
  alias TalesForge.GameCharacter
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Schemas.GameSession

  doctest TalesForge.Game.Turn.Board, only: [refusal: 2]

  @cloak %{"id" => "travel_cloak", "name" => "Travel Cloak", "quantity" => 1}

  describe "between the character and a trader" do
    setup do
      brenna = %GameCharacter{
        slug: "innkeep",
        name: "Brenna Holt",
        coins: %{"silver" => 10},
        inventory: [
          %{"id" => "ale_mug", "name" => "Mug of Ale", "price_copper" => 2, "quantity" => 5}
        ]
      }

      world =
        World.default_world_state()
        |> put_in(["character", "inventory"], [Map.put(@cloak, "copper_value", 40)])
        |> put_in(["character", "coins"], %{"copper" => 9})

      {:ok, world: world, traders: %{"innkeep" => brenna}}
    end

    test "a sale pays the character and the item joins the buyer's inventory", %{
      world: world,
      traders: traders
    } do
      assert {:ok, after_world, %{applied: ["sold 1x travel_cloak for 40c"]}, [brenna]} =
               Inventory.apply_transaction(world, traders, sell("travel_cloak"))

      assert copper(after_world["character"]) == 49
      assert Inventory.item_quantity(after_world["character"]["inventory"], "travel_cloak") == 0
      assert copper(brenna) == 60

      assert %{"price_copper" => 40, "quantity" => 1} =
               Enum.find(brenna.inventory, &(&1["id"] == "travel_cloak"))

      assert_conserved({world, traders}, {after_world, [brenna]})
    end

    test "a haggled price on the action is the price paid", %{world: world, traders: traders} do
      action = sell("travel_cloak", %{"price_copper" => 25})

      assert {:ok, after_world, _details, [brenna]} =
               Inventory.apply_transaction(world, traders, action)

      assert copper(after_world["character"]) == 34
      assert copper(brenna) == 75
      assert_conserved({world, traders}, {after_world, [brenna]})
    end

    test "a buyer who cannot pay refuses, and nothing moves", %{world: world, traders: traders} do
      poor = put_in(traders, ["innkeep"], %{traders["innkeep"] | coins: %{"copper" => 39}})

      assert {:error, "Insufficient funds: Brenna Holt cannot pay 40c for travel_cloak."} =
               Inventory.apply_transaction(world, poor, sell("travel_cloak"))
    end

    test "an item with no price is not sold", %{world: world, traders: traders} do
      world = put_in(world, ["character", "inventory"], [@cloak])

      assert {:error, "Sell requires a price for 'travel_cloak'."} =
               Inventory.apply_transaction(world, traders, sell("travel_cloak"))
    end

    test "a sale to nobody here who trades is not made", %{world: world} do
      assert {:error, "Nobody here buys 'travel_cloak'."} =
               Inventory.apply_transaction(world, %{}, sell("travel_cloak"))
    end

    test "a purchase pays the trader", %{world: world, traders: traders} do
      action = %SingleAction{
        action_type: :buy,
        target: "innkeep",
        parameters: %{"item_id" => "ale_mug", "quantity" => 2}
      }

      assert {:ok, after_world, _details, [brenna]} =
               Inventory.apply_transaction(world, traders, action)

      assert copper(after_world["character"]) == 5
      assert Inventory.item_quantity(after_world["character"]["inventory"], "ale_mug") == 2
      assert copper(brenna) == 104
      assert Inventory.item_quantity(brenna.inventory, "ale_mug") == 3
      assert_conserved({world, traders}, {after_world, [brenna]})
    end
  end

  describe "a sale in a turn" do
    setup do
      {:ok, session} = GameSessions.create_session(%{name: "Trade", adventure_id: "tin_valley"})
      {:ok, session: GameSessions.get_session!(session.id)}
    end

    test "the cloak and the coins change hands in the saved turn", %{session: session} do
      session = carry(session, Map.put(@cloak, "copper_value", 40))
      before = {session.world_state, NPC.traders(session.id, ["innkeep"])}

      assert {:ok, _payload} = TurnProcessor.simulate!(board(session), "I sell my cloak")

      saved = GameSessions.get_session!(session.id)
      %{"innkeep" => brenna} = NPC.traders(session.id, ["innkeep"])

      assert copper(saved.world_state["character"]) ==
               copper(session.world_state["character"]) + 40

      assert Inventory.item_quantity(brenna.inventory, "travel_cloak") == 1
      assert_conserved(before, {saved.world_state, [brenna]})
    end

    test "a sale with no price moves nothing, and the GM is told why", %{session: session} do
      session = carry(session, @cloak)
      %{"innkeep" => brenna_before} = NPC.traders(session.id, ["innkeep"])

      result = Board.resolve(%{board(session) | character: session.world_state["character"]})

      assert result.world["character"]["inventory"] ==
               session.world_state["character"]["inventory"]

      assert result.world["character"]["coins"] == session.world_state["character"]["coins"]
      assert result.traders == []

      ruled = %HandlerResult{handler: "inventory"}

      assert %HandlerResult{
               state_hints: %{"reason" => "Sell requires a price for 'travel_cloak'."}
             } =
               Board.refusal(ruled, result.handler)

      assert {:ok, _payload} = TurnProcessor.simulate!(board(session), "I sell my cloak")
      saved = GameSessions.get_session!(session.id)

      assert Inventory.item_quantity(saved.world_state["character"]["inventory"], "travel_cloak") ==
               1

      assert NPC.traders(session.id, ["innkeep"]) == %{"innkeep" => brenna_before}
    end

    test "a sale the turn does not save moves nothing at the NPC", %{session: session} do
      session = carry(session, Map.put(@cloak, "copper_value", 40))
      traders_before = NPC.traders(session.id, ["innkeep"])

      %{traders: [_brenna]} =
        Board.resolve(%{board(session) | character: session.world_state["character"]})

      assert NPC.traders(session.id, ["innkeep"]) == traders_before
    end
  end

  defp sell(item_id, params \\ %{}) do
    %SingleAction{
      action_type: :sell,
      target: "innkeep",
      parameters: Map.merge(%{"item_id" => item_id, "npc_id" => "innkeep"}, params)
    }
  end

  defp board(%GameSession{} = session) do
    action = %PlayerAction{
      overall_intent: "I sell my cloak to Brenna",
      action: sell("travel_cloak")
    }

    %Board{
      session: session,
      player_action: action,
      handler: ActionHandler.resolve(action),
      mechanical: %MechanicalResolution{outcome: "none"}
    }
  end

  defp carry(%GameSession{} = session, item) do
    world = update_in(session.world_state, ["character", "inventory"], &[item | &1])
    session |> GameSession.changeset(%{world_state: world}) |> save_session!()
    GameSessions.get_session!(session.id)
  end

  defp copper(%GameCharacter{coins: coins}), do: Inventory.coin_total_copper(coins)
  defp copper(%{} = sheet), do: Inventory.coin_total_copper(sheet["coins"])

  # Coins and every item, counted over the character and the traders,
  # are the same before and after.
  defp assert_conserved({world, traders}, {after_world, changed}) do
    after_traders = Map.merge(traders, Map.new(changed, &{&1.slug, &1}))
    assert wealth(world, traders) == wealth(after_world, after_traders)
  end

  defp wealth(world, traders) do
    people = [world["character"] | Enum.map(Map.values(traders), &GameCharacter.to_sheet/1)]

    items =
      people
      |> Enum.flat_map(&Inventory.normalize_items(&1["inventory"]))
      |> Enum.group_by(& &1["id"], & &1["quantity"])
      |> Map.new(fn {id, qtys} -> {id, Enum.sum(qtys)} end)

    {Enum.sum(Enum.map(people, &Inventory.coin_total_copper(&1["coins"]))), items}
  end
end
