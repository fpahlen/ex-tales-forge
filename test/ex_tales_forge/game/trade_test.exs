defmodule TalesForge.Game.TradeTest do
  @moduledoc """
  A trade is one operation (Fredrik's rule, 2026-10-18): the item and its
  price change places between the two characters, both or neither, only
  when both accept, and nothing is made or lost. The GM narrates only the
  outcome the server decided.

  Gentry's playtest sessions on 2026-10-18: 643b8031 (after #446, a cloak
  sold for nothing) and 3d9788e0 (after #466: T7 "I buy a mug of ale from
  Brenna and pay her", T8 "I sell the mug of ale back to Brenna Holt", which
  the server made while the story refused it).
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{Inventory, Trade, TurnProcessor, World}
  alias TalesForge.Game.Schemas.{GMStructuredResponse, HandlerResult, SingleAction}
  alias TalesForge.Game.Turn.{Adapters, Board}
  alias TalesForge.GameCharacter
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, GameSession}

  doctest TalesForge.Game.Trade
  doctest TalesForge.Game.Turn.Board, only: [trade_outcome: 2]

  @cloak %{"id" => "travel_cloak", "name" => "Travel Cloak", "quantity" => 1}
  @ale %{"id" => "ale_mug", "name" => "Mug of Ale", "quantity" => 1}

  describe "Trade.execute/1" do
    setup do
      brenna = %GameCharacter{
        slug: "innkeep",
        name: "Brenna Holt",
        coins: %{"silver" => 10},
        inventory: [Map.merge(@ale, %{"price_copper" => 2, "quantity" => 5})]
      }

      aric = %GameCharacter{
        name: "Aric",
        coins: %{"copper" => 9},
        inventory: [Map.put(@cloak, "copper_value", 40)]
      }

      {:ok, brenna: brenna, aric: aric}
    end

    test "a sale and a purchase are the same trade", %{brenna: brenna, aric: aric} do
      assert {:ok, %Trade{giver: aric, receiver: brenna} = sold} =
               Trade.execute(%Trade{giver: aric, receiver: brenna, item: @cloak, price: 40})

      assert copper(aric) == 49
      assert copper(brenna) == 60
      assert Inventory.item_quantity(brenna.inventory, "travel_cloak") == 1
      assert_same_wealth([sold.giver, sold.receiver], [aric, brenna])

      assert {:ok, %Trade{receiver: back}} =
               Trade.execute(%Trade{giver: brenna, receiver: aric, item: @cloak, price: 40})

      assert copper(back) == 9
      assert Inventory.item_quantity(back.inventory, "travel_cloak") == 1
    end

    test "a receiver who cannot pay, a giver without the item, no price or a refusal: nothing moves",
         %{brenna: brenna, aric: aric} do
      poor = %{brenna | coins: %{"copper" => 39}}

      assert {:error, "Brenna Holt cannot pay 40c for Travel Cloak."} =
               Trade.execute(%Trade{giver: aric, receiver: poor, item: @cloak, price: 40})

      assert {:error, "Aric has no Mug of Ale to give."} =
               Trade.execute(%Trade{giver: aric, receiver: brenna, item: @ale, price: 2})

      assert {:error, "No price for Travel Cloak: nothing changed hands."} =
               Trade.execute(%Trade{giver: aric, receiver: brenna, item: @cloak, price: 0})

      picky = %{brenna | runtime: %{"buys" => ["ale_mug"]}}

      assert {:error, "Brenna Holt does not buy Travel Cloak."} =
               Trade.execute(%Trade{giver: aric, receiver: picky, item: @cloak, price: 40})

      sulking = %{
        brenna
        | runtime: %{"refuses_trade" => "Brenna Holt refuses to trade with you."}
      }

      assert {:error, "Brenna Holt refuses to trade with you."} =
               Trade.execute(%Trade{giver: sulking, receiver: aric, item: @ale, price: 2})
    end
  end

  describe "the inventory step" do
    test "a buy names what is for sale when the item is not" do
      world = World.default_world_state()

      brenna = %GameCharacter{
        slug: "innkeep",
        name: "Brenna Holt",
        inventory: [Map.put(@ale, "price_copper", 2)]
      }

      bread = %SingleAction{
        action_type: :buy,
        target: "innkeep",
        parameters: %{"npc_id" => "innkeep"}
      }

      assert {:error, "That is not sold here. For sale: Mug of Ale (2c)."} =
               Inventory.apply_transaction(world, %{"innkeep" => brenna}, bread)
    end
  end

  # The whole turn (TurnProcessor.run/3: intent → rules → board → prompt →
  # GM → store) with a stubbed GM, against Brenna Holt as the Tin Valley
  # pack seeds her: Mug of Ale x99 at 2c and a purse of 1 gold.
  describe "a trade in a whole turn" do
    setup do
      {:ok, session} = GameSessions.create_session(%{name: "Trade", adventure_id: "tin_valley"})
      session = GameSessions.get_session!(session.id)
      %{"innkeep" => brenna} = NPC.traders(session.id, ["innkeep"])

      assert Inventory.item_quantity(brenna.inventory, "ale_mug") == 99
      assert copper(brenna) == 500

      {:ok, session: session}
    end

    test "T7: a buy pays Brenna and takes the mug from her stock", %{session: session} do
      before = wealth(session)

      {prompt, saved} =
        play(session, "I buy a mug of ale from Brenna and pay her.", buy("ale_mug"))

      assert copper(saved.player) == copper(before.player) - 2
      assert Inventory.item_quantity(saved.player["inventory"], "ale_mug") == 1
      assert copper(saved.brenna) == 502
      assert Inventory.item_quantity(saved.brenna.inventory, "ale_mug") == 98
      assert totals(saved) == totals(before)
      assert prompt =~ "The server made this trade: bought 1x ale_mug for 2c."
    end

    test "T8: a sell-back Brenna accepts is made, and the GM is told it is done",
         %{session: session} do
      {_prompt, _saved} =
        play(session, "I buy a mug of ale from Brenna and pay her.", buy("ale_mug"))

      before = session.id |> GameSessions.get_session!() |> wealth()

      {prompt, saved} =
        play(session, "I sell the mug of ale back to Brenna Holt.", sell("ale_mug"))

      assert Inventory.item_quantity(saved.player["inventory"], "ale_mug") == 0
      assert Inventory.item_quantity(saved.brenna.inventory, "ale_mug") == 99
      assert copper(saved.brenna) == 500
      assert totals(saved) == totals(before)
      assert prompt =~ "The server made this trade: sold 1x ale_mug for 2c."
      assert prompt =~ "the trader does not refuse it"
    end

    test "T8: a refused sell-back changes nothing, and the GM is told no coins moved",
         %{session: session} do
      {_prompt, _saved} =
        play(session, "I buy a mug of ale from Brenna and pay her.", buy("ale_mug"))

      put_innkeep(session, &%{definition: Map.put(&1.definition, "buys", [])})
      before = session.id |> GameSessions.get_session!() |> wealth()
      row_coins = innkeep_row(session).coins

      {prompt, saved} =
        play(session, "I sell the mug of ale back to Brenna Holt.", sell("ale_mug"))

      assert saved.player["inventory"] == before.player["inventory"]
      assert saved.player["coins"] == before.player["coins"]
      assert saved.brenna.inventory == before.brenna.inventory
      assert innkeep_row(session).coins == row_coins
      assert prompt =~ "The server refused this trade: Brenna Holt does not buy Mug of Ale."
      assert prompt =~ "narrate no payment and no handover"
    end

    test "a sale pays the character, and Brenna keeps the cloak", %{session: session} do
      session = carry(session, Map.put(@cloak, "copper_value", 40))
      before = wealth(session)

      {_prompt, saved} =
        play(session, "I sell my travel cloak to Brenna Holt.", sell("travel_cloak"))

      assert copper(saved.player) == copper(before.player) + 40
      assert Inventory.item_quantity(saved.brenna.inventory, "travel_cloak") == 1
      assert copper(saved.brenna) == 460
      assert totals(saved) == totals(before)
    end

    test "an NPC who cannot afford it refuses, and nothing changes", %{session: session} do
      session = carry(session, Map.put(@cloak, "copper_value", 40))
      put_innkeep(session, fn _row -> %{coins: %{"copper" => 39}} end)
      before = wealth(session)

      {prompt, saved} =
        play(session, "I sell my travel cloak to Brenna Holt.", sell("travel_cloak"))

      assert saved.player["inventory"] == before.player["inventory"]
      assert saved.player["coins"] == before.player["coins"]
      assert saved.brenna.inventory == before.brenna.inventory
      assert innkeep_row(session).coins == %{"copper" => 39}

      assert prompt =~
               "The server refused this trade: Brenna Holt cannot pay 40c for Travel Cloak."
    end

    test "a sale with no price is refused, and the GM gets the reason", %{session: session} do
      session = carry(session, @cloak)
      before = wealth(session)

      {prompt, saved} =
        play(session, "I sell my travel cloak to Brenna Holt.", sell("travel_cloak"))

      assert saved.player["inventory"] == before.player["inventory"]
      assert saved.brenna == before.brenna
      assert prompt =~ ~s("reason": "No price for Travel Cloak: nothing changed hands.")
    end
  end

  test "trade_outcome/2 gives the GM a trade that was done" do
    done = %HandlerResult{
      handler: "inventory",
      state_hints: %{"trade" => %{"status" => "done", "detail" => "sold 1x ale_mug for 2c"}}
    }

    assert %HandlerResult{state_hints: %{"trade" => %{"status" => "done"}} = hints} =
             Board.trade_outcome(%HandlerResult{handler: "inventory"}, done)

    refute Map.has_key?(hints, "reason")
  end

  # One turn through TurnProcessor.run/3 with the GM stubbed: the per-turn
  # GM prompt, and the player and Brenna as saved.
  defp play(%GameSession{id: id}, text, action) do
    me = self()

    adapters = %Adapters{
      npc: fn _moment -> [] end,
      stream: fn _id, _chunk -> :ok end,
      gm: fn messages, _action, _handler, _n, _opts ->
        send(me, {:gm_prompt, List.last(messages).content})
        {:ok, %GMStructuredResponse{narrative: "Brenna nods."}}
      end
    }

    player_action = %{"overall_intent" => text, "action" => action}

    assert {:ok, _payload} =
             TurnProcessor.run(id, {text, player_action},
               adapters: adapters,
               flags: %{},
               role: :playtest
             )

    assert_received {:gm_prompt, prompt}
    {prompt, id |> GameSessions.get_session!() |> wealth()}
  end

  defp buy(item_id),
    do: %{"action_type" => "buy", "target" => "innkeep", "parameters" => %{"item_id" => item_id}}

  defp sell(item_id),
    do: %{
      "action_type" => "sell",
      "target" => "innkeep",
      "parameters" => %{"item_id" => item_id, "npc_id" => "innkeep"}
    }

  defp wealth(%GameSession{id: id, world_state: world}) do
    %{"innkeep" => brenna} = NPC.traders(id, ["innkeep"])
    %{player: world["character"], brenna: brenna}
  end

  # The coins and the count of each item, over the player and Brenna.
  defp totals(%{player: player, brenna: brenna}) do
    items =
      (Inventory.normalize_items(player["inventory"]) ++ brenna.inventory)
      |> Enum.group_by(& &1["id"], & &1["quantity"])
      |> Map.new(fn {id, qtys} -> {id, Enum.sum(qtys)} end)

    {copper(player) + copper(brenna), items}
  end

  defp assert_same_wealth(after_trade, before_trade),
    do: assert(totals(pair(after_trade)) == totals(pair(before_trade)))

  defp pair([%GameCharacter{} = a, %GameCharacter{} = b]),
    do: %{
      player: GameCharacter.to_sheet(a),
      brenna: %{b | inventory: Inventory.normalize_items(b.inventory)}
    }

  defp innkeep_row(%GameSession{id: id}),
    do: Repo.get_by!(Character, game_session_id: id, slug: "innkeep")

  defp put_innkeep(session, changes) do
    row = innkeep_row(session)
    row |> Ecto.Changeset.change(changes.(row)) |> Repo.update!()
  end

  defp carry(%GameSession{} = session, item) do
    world = update_in(session.world_state, ["character", "inventory"], &[item | &1])
    session |> GameSession.changeset(%{world_state: world}) |> save_session!()
    GameSessions.get_session!(session.id)
  end

  defp copper(%GameCharacter{coins: coins}), do: Inventory.coin_total_copper(coins)
  defp copper(%{} = sheet), do: Inventory.coin_total_copper(sheet["coins"])
end
