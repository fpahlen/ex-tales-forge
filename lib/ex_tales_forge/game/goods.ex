defmodule TalesForge.Game.Goods do
  @moduledoc """
  Items and coins as the characters carry them: counting, adding and
  removing items by id, and coins counted in copper (10 copper is 1
  silver, 500 copper is 1 gold). The inventory step and
  `TalesForge.Game.Trade` (one trade) both move goods with these. Pure.
  """

  @copper_per_silver 10
  @copper_per_gold 500

  def item_quantity(items, item_id) do
    case find_item_index(items, item_id) do
      nil -> 0
      index -> int_field(Enum.at(items, index), ["quantity"], 0)
    end
  end

  def add_item(items, item) when is_map(item) do
    item_id = Map.fetch!(item, "id")
    qty = max(1, int_field(item, ["quantity"], 1))

    case find_item_index(items, item_id) do
      nil ->
        items ++ [Map.put(item, "quantity", qty)]

      index ->
        current = int_field(Enum.at(items, index), ["quantity"], 0)
        List.replace_at(items, index, Map.put(Enum.at(items, index), "quantity", current + qty))
    end
  end

  def remove_item(items, item_id, quantity \\ 1) do
    index = find_item_index(items, item_id)

    if is_nil(index) do
      raise ArgumentError, "Item '#{item_id}' not found."
    end

    current = int_field(Enum.at(items, index), ["quantity"], 0)

    if current < quantity do
      raise ArgumentError, "Not enough '#{item_id}' (have #{current}, need #{quantity})."
    end

    remaining = current - quantity

    if remaining <= 0 do
      List.delete_at(items, index)
    else
      List.replace_at(items, index, Map.put(Enum.at(items, index), "quantity", remaining))
    end
  end

  def coin_total_copper(coins) when is_map(coins) do
    gold = int_field(coins, ["gold"], 0)
    silver = int_field(coins, ["silver"], 0)
    copper = int_field(coins, ["copper"], 0)
    gold * @copper_per_gold + silver * @copper_per_silver + copper
  end

  def coin_total_copper(_), do: 0

  def deduct_coins(coins, amount_copper) do
    total = coin_total_copper(coins)

    if total < amount_copper do
      raise ArgumentError, "Insufficient funds (have #{total}c, need #{amount_copper}c)."
    end

    copper_to_coins(total - amount_copper)
  end

  def add_coins(coins, amount_copper) do
    copper_to_coins(coin_total_copper(coins) + amount_copper)
  end

  @doc false
  def find_item_index(items, item_id) do
    Enum.find_index(items, &(&1["id"] == item_id))
  end

  defp copper_to_coins(total) do
    total = max(0, total)
    gold = div(total, @copper_per_gold)
    after_gold = rem(total, @copper_per_gold)
    silver = div(after_gold, @copper_per_silver)
    copper = rem(after_gold, @copper_per_silver)

    %{}
    |> maybe_put("gold", gold)
    |> maybe_put("silver", silver)
    |> maybe_put("copper", copper)
  end

  defp maybe_put(map, _key, 0), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc false
  # The integer at the first of `keys` in `map` that has one, else `default`.
  def int_field(map, keys, default) when is_map(map) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        nil -> nil
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
        value when is_float(value) -> trunc(value)
        _ -> nil
      end
    end) || default
  end

  def int_field(_, _, default), do: default
end
