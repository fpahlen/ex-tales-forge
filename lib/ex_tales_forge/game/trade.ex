defmodule TalesForge.Game.Trade do
  @moduledoc """
  One trade between two characters (Fredrik's rule, 2026-10-18): the
  `giver` hands over `item` and the `receiver` pays `price` (copper, for
  the whole quantity) for it. A sale is item for coins, and a purchase is
  the same trade seen from the other side; a player character and an NPC
  are both `TalesForge.GameCharacter`s, so either can be either side.

  `execute/1` is the one decision: both sides accept, the giver has the
  item and the receiver the coins, or it is `{:error, reason}` and nothing
  moved. Then the item and the coins change places: nothing is made or
  lost. It is pure; the caller saves both parties in one transaction (the
  turn's, `TalesForge.Game.Turn.Store`).

  A character's `runtime` sets how it trades: `"refuses_trade"` (a
  reason) refuses any trade; `"buys"` (item ids) is all it buys;
  `"lends"` (words, such as "mug") names what it only lends with what it
  serves, never for sale; `"serves"` (item ids) is what it serves to be
  eaten or drunk on the spot, so the receiver pays and carries nothing
  away. A character without them accepts any trade it can make.

      iex> alias TalesForge.Game.Trade
      iex> brenna = %TalesForge.GameCharacter{name: "Brenna Holt", coins: %{"gold" => 2},
      ...>   inventory: [%{"id" => "ale_mug", "name" => "Ale", "price_copper" => 2, "quantity" => 72}],
      ...>   runtime: %{"serves" => ["ale_mug"], "lends" => ["mug"], "buys" => []}}
      iex> aric = %TalesForge.GameCharacter{name: "Aric", coins: %{"silver" => 1}, inventory: []}
      iex> {:ok, trade} = Trade.execute(%Trade{giver: brenna, receiver: aric, price: 2,
      ...>   item: %{"id" => "ale_mug", "name" => "Ale", "quantity" => 1}})
      iex> {trade.giver.coins, hd(trade.giver.inventory)["quantity"], trade.receiver.coins, trade.receiver.inventory}
      {%{"gold" => 2, "copper" => 2}, 71, %{"copper" => 8}, []}
      iex> Trade.execute(%Trade{giver: aric, receiver: brenna, price: 2,
      ...>   item: %{"id" => "ale_mug", "name" => "Ale", "quantity" => 1}})
      {:error, "The mug is Brenna Holt's, lent with the drink; it is not for sale."}
  """

  alias TalesForge.Game.Goods
  alias TalesForge.GameCharacter

  @enforce_keys [:giver, :receiver, :item, :price]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          giver: GameCharacter.t(),
          receiver: GameCharacter.t(),
          item: %{required(String.t()) => term()},
          price: integer()
        }

  @doc "The trade done, or `{:error, reason}` with nothing moved."
  @spec execute(t()) :: {:ok, t()} | {:error, String.t()}
  def execute(%__MODULE__{} = trade) do
    with :ok <- accepts(trade.giver, trade),
         :ok <- accepts(trade.receiver, trade),
         :ok <- priced(trade),
         :ok <- delivers(trade),
         :ok <- pays(trade),
         do: {:ok, exchange(trade)}
  end

  defp priced(%__MODULE__{price: price, item: item}) when price <= 0,
    do: {:error, "No price for #{name(item)}: nothing changed hands."}

  defp priced(%__MODULE__{}), do: :ok

  defp accepts(%GameCharacter{runtime: %{"refuses_trade" => reason}}, _trade)
       when is_binary(reason),
       do: {:error, reason}

  defp accepts(%GameCharacter{} = receiver, %__MODULE__{receiver: receiver, item: item}) do
    with :ok <- not_lent(receiver, item), do: buys(receiver, item)
  end

  defp accepts(%GameCharacter{}, %__MODULE__{}), do: :ok

  # A thing the receiver only lends (the inn's mug) is never bought back.
  defp not_lent(%GameCharacter{runtime: runtime, name: name}, %{"id" => id}) do
    case Enum.find(Map.get(runtime || %{}, "lends", []), &String.contains?(id, &1)) do
      nil -> :ok
      word -> {:error, "The #{word} is #{name}'s, lent with the drink; it is not for sale."}
    end
  end

  defp buys(%GameCharacter{runtime: %{"buys" => buys}} = receiver, %{"id" => id} = item)
       when is_list(buys) do
    if id in buys,
      do: :ok,
      else: {:error, "#{receiver.name} does not buy #{name(item)}."}
  end

  defp buys(%GameCharacter{}, _item), do: :ok

  defp delivers(%__MODULE__{giver: giver, item: %{"id" => id} = item}) do
    if Goods.item_quantity(giver.inventory, id) >= quantity(item),
      do: :ok,
      else: {:error, "#{giver.name} has no #{name(item)} to give."}
  end

  defp pays(%__MODULE__{receiver: receiver, price: price, item: item}) do
    if Goods.coin_total_copper(receiver.coins) >= price,
      do: :ok,
      else: {:error, "#{receiver.name} cannot pay #{price}c for #{name(item)}."}
  end

  # The item to the receiver, valued at the price paid; the coins to the
  # giver.
  defp exchange(%__MODULE__{giver: giver, receiver: receiver, item: item, price: price} = trade) do
    qty = quantity(item)
    moved = Map.merge(item, %{"quantity" => qty, "copper_value" => div(price, qty)})

    %{
      trade
      | giver: %{
          giver
          | inventory: Goods.remove_item(giver.inventory, item["id"], qty),
            coins: Goods.add_coins(giver.coins, price)
        },
        receiver: %{
          receiver
          | inventory: carried_away(giver, receiver.inventory, moved),
            coins: Goods.deduct_coins(receiver.coins, price)
        }
    }
  end

  # What the receiver carries away: nothing for a serving (eaten or drunk
  # where it is bought), else the item.
  defp carried_away(%GameCharacter{runtime: %{"serves" => served}} = giver, inventory, moved)
       when is_list(served) do
    if moved["id"] in served,
      do: inventory,
      else: carried_away(%{giver | runtime: %{}}, inventory, moved)
  end

  defp carried_away(%GameCharacter{}, inventory, moved), do: Goods.add_item(inventory, moved)

  defp quantity(item), do: max(1, item["quantity"] || 1)

  defp name(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp name(%{"id" => id}), do: "'#{id}'"
end
