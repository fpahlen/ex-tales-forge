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
  # GM → store) with a stubbed GM, against the traders as the Tin Valley
  # pack seeds them: Brenna Holt with a cask of 72 servings of Ale at 2c,
  # served in a mug she lends, a purse of 2 gold (1000c) and `buys: []`;
  # with INN_WORLD, Hilde Brask the smith, who buys blades, with a purse
  # of 1 gold (500c).
  describe "a trade in a whole turn" do
    setup do
      previous = System.get_env("INN_WORLD")
      System.put_env("INN_WORLD", "on")

      on_exit(fn ->
        if previous,
          do: System.put_env("INN_WORLD", previous),
          else: System.delete_env("INN_WORLD")
      end)

      {:ok, session} = GameSessions.create_session(%{name: "Trade", adventure_id: "tin_valley"})
      session = GameSessions.get_session!(session.id)
      %{"innkeep" => brenna, "smith" => hilde} = NPC.traders(session.id, ["innkeep", "smith"])

      assert Inventory.item_quantity(brenna.inventory, "ale_mug") == 72
      assert copper(brenna) == 1000

      assert brenna.runtime == %{
               "buys" => [],
               "lends" => ["mug"],
               "serves" => ["ale_mug", "stew_bowl", "bread_cheese"]
             }

      assert copper(hilde) == 500
      assert hilde.runtime == %{"buys" => ["hunting_knife", "spearhead", "short_sword"]}

      {:ok, session: session}
    end

    test "T7: a serving of ale is drunk there: Brenna is paid and her cask goes down",
         %{session: session} do
      before = wealth(session, "innkeep")

      {prompt, saved} =
        play(session, "I buy a mug of ale from Brenna and pay her.", buy("ale_mug"), "innkeep")

      assert copper(saved.player) == copper(before.player) - 2
      assert carried(saved.player) == carried(before.player)
      refute Enum.any?(saved.player["inventory"], &(&1["id"] == "ale_mug"))
      assert copper(saved.trader) == 1002
      assert Inventory.item_quantity(saved.trader.inventory, "ale_mug") == 71
      assert copper(saved.player) + copper(saved.trader) == copper(before.player) + 1000
      assert prompt =~ "The server made this trade: bought 1x ale_mug for 2c."
    end

    for {what, item_id, reason} <- [
          {"the mug", "ale_mug",
           "The mug is Brenna Holt's, lent with the drink; it is not for sale."},
          {"the ale", "ale", "Brenna Holt does not buy 'ale'."}
        ] do
      test "T8: selling #{what} back to Brenna is refused, nothing changes, and the GM is told",
           %{session: session} do
        bought(session)
        before = session.id |> GameSessions.get_session!() |> wealth("innkeep")
        row = npc_row(session, "innkeep")

        {prompt, saved} =
          play(
            session,
            "I sell #{unquote(what)} back to Brenna Holt.",
            sell(unquote(item_id)),
            "innkeep"
          )

        assert saved.player["inventory"] == before.player["inventory"]
        assert saved.player["coins"] == before.player["coins"]
        assert saved.trader.inventory == before.trader.inventory
        assert npc_row(session, "innkeep").coins == row.coins
        assert npc_row(session, "innkeep").inventory == row.inventory
        assert prompt =~ "The server refused this trade: #{unquote(reason)}"
        assert prompt =~ "narrate no payment and no handover"
      end
    end

    test "a sale to a trader who buys the item pays the character", %{session: session} do
      session = value(session, "hunting_knife", 15)
      before = wealth(session, "smith")

      {prompt, saved} =
        play(
          session,
          "I sell my hunting knife to Hilde.",
          sell("hunting_knife", "smith"),
          "smith"
        )

      assert copper(saved.player) == copper(before.player) + 15
      assert Inventory.item_quantity(saved.player["inventory"], "hunting_knife") == 0
      assert Inventory.item_quantity(saved.trader.inventory, "hunting_knife") == 4
      assert copper(saved.trader) == 485
      assert totals(saved) == totals(before)
      assert prompt =~ "The server made this trade: sold 1x hunting_knife for 15c."
    end

    test "an NPC who cannot afford it refuses, and nothing changes", %{session: session} do
      session = value(session, "hunting_knife", 15)
      put_npc(session, "smith", fn _row -> %{coins: %{"copper" => 14}} end)
      before = wealth(session, "smith")

      {prompt, saved} =
        play(
          session,
          "I sell my hunting knife to Hilde.",
          sell("hunting_knife", "smith"),
          "smith"
        )

      assert saved.player["inventory"] == before.player["inventory"]
      assert saved.player["coins"] == before.player["coins"]
      assert saved.trader.inventory == before.trader.inventory
      assert npc_row(session, "smith").coins == %{"copper" => 14}

      assert prompt =~
               "The server refused this trade: Hilde Brask cannot pay 15c for hunting knife."
    end

    test "T11 (session 8a9dbde9): a knife with no value sells at Hilde's own price",
         %{session: session} do
      before = wealth(session, "smith")

      {prompt, saved} =
        play(
          session,
          "I sell my hunting knife to Hilde Brask.",
          sell("hunting_knife", "smith"),
          "smith"
        )

      assert copper(saved.player) == copper(before.player) + 15
      assert copper(saved.trader) == copper(before.trader) - 15
      assert Inventory.item_quantity(saved.trader.inventory, "hunting_knife") == 4
      assert prompt =~ "The server made this trade: sold 1x hunting_knife for 15c."
    end

    test "a price question is an offer: the GM gets the quote and nothing moves",
         %{session: session} do
      before = wealth(session, "innkeep")

      {prompt, saved} =
        play(session, "How much for a mug of ale, Brenna?", buy(nil), "innkeep")

      assert saved == before
      assert prompt =~ "The server quotes: Brenna Holt sells Ale for 2c"
    end

    test "the mug is not for sale: refused, and nothing moves that turn", %{session: session} do
      before = wealth(session, "innkeep")

      {prompt, saved} = play(session, "I buy the mug itself from Brenna.", buy(nil), "innkeep")

      assert saved == before
      assert prompt =~ "The server refused this trade"
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
  # GM prompt, and the player and the trader `npc_id` as saved.
  defp play(%GameSession{id: id}, text, action, npc_id) do
    me = self()

    adapters = %Adapters{
      npc: fn _moment -> [] end,
      stream: fn _id, _chunk -> :ok end,
      gm: fn %TalesForge.LLM.GmTurn{messages: messages} ->
        send(me, {:gm_prompt, List.last(messages).content})
        {:ok, %GMStructuredResponse{narrative: "The trader nods."}}
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
    {prompt, id |> GameSessions.get_session!() |> wealth(npc_id)}
  end

  # T7, the mug of ale bought from Brenna.
  defp bought(session),
    do: play(session, "I buy a mug of ale from Brenna and pay her.", buy("ale_mug"), "innkeep")

  defp buy(nil), do: %{"action_type" => "buy", "target" => "innkeep", "parameters" => %{}}

  defp buy(item_id),
    do: %{"action_type" => "buy", "target" => "innkeep", "parameters" => %{"item_id" => item_id}}

  defp sell(item_id, npc_id \\ "innkeep"),
    do: %{
      "action_type" => "sell",
      "target" => npc_id,
      "parameters" => %{"item_id" => item_id, "npc_id" => npc_id}
    }

  defp wealth(%GameSession{id: id, world_state: world}, npc_id) do
    %{^npc_id => trader} = NPC.traders(id, [npc_id])
    %{player: world["character"], trader: trader}
  end

  # The coins and the count of each item, over the player and the trader.
  defp totals(%{player: player, trader: trader}) do
    items =
      (Inventory.normalize_items(player["inventory"]) ++ trader.inventory)
      |> Enum.group_by(& &1["id"], & &1["quantity"])
      |> Map.new(fn {id, qtys} -> {id, Enum.sum(qtys)} end)

    {copper(player) + copper(trader), items}
  end

  defp assert_same_wealth(after_trade, before_trade),
    do: assert(totals(pair(after_trade)) == totals(pair(before_trade)))

  defp pair([%GameCharacter{} = a, %GameCharacter{} = b]),
    do: %{
      player: GameCharacter.to_sheet(a),
      trader: %{b | inventory: Inventory.normalize_items(b.inventory)}
    }

  defp npc_row(%GameSession{id: id}, slug),
    do: Repo.get_by!(Character, game_session_id: id, slug: slug)

  defp put_npc(session, slug, changes) do
    row = npc_row(session, slug)
    row |> Ecto.Changeset.change(changes.(row)) |> Repo.update!()
  end

  # The session with the carried item `item_id` worth `copper`.
  defp value(%GameSession{} = session, item_id, copper) do
    world =
      update_in(session.world_state, ["character", "inventory"], fn items ->
        Enum.map(
          items,
          &if(&1["id"] == item_id, do: Map.put(&1, "copper_value", copper), else: &1)
        )
      end)

    session |> GameSession.changeset(%{world_state: world}) |> save_session!()
    GameSessions.get_session!(session.id)
  end

  defp carried(%{"inventory" => inventory}),
    do: Enum.map(inventory, &{&1["id"], &1["quantity"]})

  defp copper(%GameCharacter{coins: coins}), do: Inventory.coin_total_copper(coins)
  defp copper(%{} = sheet), do: Inventory.coin_total_copper(sheet["coins"])
end
