defmodule TalesForge.NPCGoodsTest do
  @moduledoc """
  Only a trade writes an NPC's goods (`NPC.put_inventories/2`,
  `NPC.Rows.put_goods!/2`). The world-sim tick saves people it read before
  the trade, and the memory, relationship, concern and initiative writes
  save the rest of the NPC's state: none of them writes the stock or the
  coins, whatever order the turn's steps run in.
  """
  use TalesForge.DataCase, async: false
  alias TalesForge.NPC.Rows

  alias TalesForge.Game.Inventory
  alias TalesForge.GameSessions
  alias TalesForge.NPC

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Goods", adventure_id: "tin_valley"})
    {:ok, session: session}
  end

  # Brenna sells three ales for 6c: her stock and purse after the trade.
  defp sold(session_id) do
    %{"innkeep" => brenna} = NPC.traders(session_id, ["innkeep"])

    %{
      brenna
      | inventory: Inventory.remove_item(brenna.inventory, "ale_mug", 3),
        coins: Inventory.add_coins(brenna.coins, 6)
    }
  end

  defp trade_step(multi, session_id, trader),
    do:
      Ecto.Multi.run(multi, :traders, fn _, _ ->
        {:ok, NPC.put_inventories(session_id, [trader])}
      end)

  # The tick's people, read before the trade; the tick moved Brenna.
  defp tick(session_id) do
    people =
      for %{npc_id: "innkeep"} = person <- NPC.sim_people(session_id),
          do: put_in(person, [:runtime_state, "location_id"], "tin_valley_square")

    %{people: people}
  end

  for order <- [:tick_first, :trade_first] do
    test "the tick does not write back the goods it read before the trade (#{order})",
         %{session: session} do
      sim = tick(session.id)
      trader = sold(session.id)

      steps =
        case unquote(order) do
          :tick_first ->
            [&NPC.persist_tick_multi(&1, session.id, sim), &trade_step(&1, session.id, trader)]

          :trade_first ->
            [&trade_step(&1, session.id, trader), &NPC.persist_tick_multi(&1, session.id, sim)]
        end

      assert {:ok, _} = steps |> Enum.reduce(Ecto.Multi.new(), & &1.(&2)) |> Repo.transaction()

      brenna = Rows.get(session.id, "innkeep")
      assert brenna.row.coins == trader.coins
      assert brenna.runtime_state["stock"] == trader.inventory
      assert brenna.runtime_state["location_id"] == "tin_valley_square"
    end
  end

  test "the state writes leave the goods as the trade wrote them", %{session: session} do
    trader = sold(session.id)
    :ok = NPC.put_inventories(session.id, [trader])

    NPC.record_memory(%NPC.Note{
      session_id: session.id,
      npc_id: "innkeep",
      summary: "Sold ale.",
      tick: 1
    })

    {:ok, _} = NPC.bump_relationship(session.id, "innkeep", 0.1)
    NPC.adjust_concern(session.id, "innkeep", 1)
    :ok = session.id |> Rows.get("innkeep") |> NPC.mark_initiative_emitted(2)

    brenna = Rows.get(session.id, "innkeep")
    Rows.update!(brenna, %{brenna.runtime_state | "stock" => [], "coins" => %{"gold" => 99}})

    brenna = Rows.get(session.id, "innkeep")
    assert brenna.row.coins == trader.coins
    assert brenna.runtime_state["stock"] == trader.inventory
    assert brenna.runtime_state["initiative_emitted"]
    assert Enum.any?(brenna.runtime_state["memories"], &(&1["summary"] == "Sold ale."))
  end

  test "a state write's changeset has no goods in it", %{session: session} do
    brenna = Rows.get(session.id, "innkeep")

    changes =
      NPC.Rows.changeset(brenna, %{brenna.runtime_state | "stock" => [], "coins" => %{}}).changes

    refute Map.has_key?(changes, :inventory)
    refute Map.has_key?(changes, :coins)
  end
end
