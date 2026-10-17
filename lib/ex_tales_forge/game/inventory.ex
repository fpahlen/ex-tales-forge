defmodule TalesForge.Game.Inventory do
  @moduledoc false

  defmodule Transaction do
    # One inventory action on its way through the inventory steps: the
    # world, the session, the location, the resolved action, the character,
    # and the inventory, ground items, coins and NPC stock that the steps
    # change. `applied` is the log of what happened and `npc_updates` the
    # NPC stock to save.
    @moduledoc false

    @enforce_keys [:world_state, :session_id, :location_id, :action, :character]
    defstruct [
      :world_state,
      :session_id,
      :location_id,
      :action,
      :character,
      inventory: [],
      ground_items: [],
      coins: %{},
      npc_stock: %{},
      applied: [],
      npc_updates: %{}
    ]

    @type t :: %__MODULE__{
            world_state: map(),
            session_id: String.t(),
            location_id: String.t(),
            action: TalesForge.Game.Schemas.SingleAction.t(),
            character: map(),
            inventory: [map()],
            ground_items: [map()],
            coins: map(),
            npc_stock: map(),
            applied: [String.t()],
            npc_updates: map()
          }
  end

  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Game.World
  alias TalesForge.NPC

  @inventory_actions ~w(pickup drop buy sell trade spend)a

  @copper_per_silver 10
  @copper_per_gold 500

  def inventory_actions, do: @inventory_actions

  def apply_server_inventory(world_state, session_id, action, handler) do
    if handler.handler == "inventory" and action.action_type in @inventory_actions do
      apply_transaction(world_state, session_id, action)
    else
      {:ok, world_state, nil}
    end
  end

  def apply_transaction(world_state, session_id, %SingleAction{} = action) do
    location_id = get_in(world_state, ["character", "location_id"]) || "weary_pilgrim"
    character = Map.get(world_state, "character", %{})
    present_npcs = Map.get(world_state, "present_npcs", [])

    transaction =
      resolve_action(%Transaction{
        world_state: world_state,
        session_id: session_id,
        location_id: location_id,
        action: action,
        character: character,
        inventory: normalize_items(Map.get(character, "inventory", [])),
        ground_items: ground_items_for(world_state, location_id),
        coins: Map.get(character, "coins", %{}),
        npc_stock: NPC.stock_map(session_id, npc_stock_keys(action, present_npcs))
      })

    with :ok <- validate_transaction(transaction), do: do_apply(transaction)
  end

  def validate_transaction(%Transaction{action: %SingleAction{action_type: type} = action} = t),
    do: validate(type, action, t)

  defp validate(:drop, action, %Transaction{inventory: inventory}) do
    with item_id when item_id != "" <- item_ref(action),
         true <- item_quantity(inventory, item_id) >= action_quantity(params(action)) do
      :ok
    else
      "" -> {:error, "Drop requires an item_id target."}
      false -> {:error, "Cannot drop '#{item_ref(action)}' — not in inventory."}
    end
  end

  defp validate(:pickup, action, %Transaction{ground_items: ground_items}) do
    with item_id when item_id != "" <- item_ref(action),
         true <- item_quantity(ground_items, item_id) >= action_quantity(params(action)) do
      :ok
    else
      "" -> {:error, "Pickup requires an item_id target."}
      false -> {:error, "Cannot pick up '#{item_ref(action)}' — not on the ground here."}
    end
  end

  defp validate(:buy, action, %Transaction{character: character, npc_stock: npc_stock}) do
    params = params(action)
    item_id = Map.get(params, "item_id", "") |> to_string() |> String.trim()
    qty = action_quantity(params)
    npc_id = resolve_buy_npc_id(action, params, npc_stock)
    stock = normalize_stock(Map.get(npc_stock, npc_id, []))
    stock_item = Enum.find(stock, &(&1["id"] == item_id))

    cond do
      item_id == "" ->
        {:error, "Buy requires parameters.item_id."}

      npc_id == "" or is_nil(stock_item) ->
        {:error, "'#{item_id}' is not sold here."}

      item_quantity(stock, item_id) < qty ->
        {:error, "Not enough '#{item_id}' in stock."}

      coin_total_copper(Map.get(character, "coins", %{})) <
          price_copper(params, stock_item) * qty ->
        {:error,
         "Insufficient funds for #{item_id} (#{price_copper(params, stock_item) * qty}c needed)."}

      true ->
        :ok
    end
  end

  defp validate(:sell, action, %Transaction{inventory: inventory}) do
    params = params(action)
    item_id = Map.get(params, "item_id", "") |> to_string() |> String.trim()

    cond do
      item_id == "" ->
        {:error, "Sell requires parameters.item_id."}

      npc_ref(action, "") == "" ->
        {:error, "Sell requires an NPC target."}

      item_quantity(inventory, item_id) < action_quantity(params) ->
        {:error, "Cannot sell '#{item_id}' — not in inventory."}

      true ->
        :ok
    end
  end

  defp validate(:spend, action, %Transaction{character: character}) do
    amount = spend_amount(action)

    cond do
      amount <= 0 ->
        {:error, "Spend requires parameters.amount_copper."}

      coin_total_copper(Map.get(character, "coins", %{})) < amount ->
        {:error, "Insufficient funds (need #{amount}c)."}

      true ->
        :ok
    end
  end

  defp validate(:trade, action, %Transaction{inventory: inventory} = t) do
    with {:ok, give_items, receive_items, counterparty} <- trade_legs(params(action)),
         :ok <- validate_trade_give(inventory, give_items) do
      validate_trade_receive(receive_items, counterparty, t)
    end
  end

  defp validate(_type, _action, _t), do: {:error, "Not an inventory action."}

  defp params(%SingleAction{parameters: params}), do: params || %{}

  def normalize_stock(raw) when is_list(raw) do
    Enum.flat_map(raw, fn
      %{} = entry ->
        item_id = entry |> Map.get("id", "") |> to_string() |> String.trim()

        if item_id == "" do
          []
        else
          [
            %{
              "id" => item_id,
              "name" => default_name(entry, item_id),
              "price_copper" => int_field(entry, ["price_copper", "copper_value"], 0),
              "quantity" => max(1, int_field(entry, ["quantity"], 1))
            }
          ]
        end

      _ ->
        []
    end)
  end

  def normalize_stock(_), do: []

  def normalize_items(raw) when is_list(raw) do
    Enum.flat_map(raw, fn
      %{} = entry ->
        item_id = entry |> Map.get("id", "") |> to_string() |> String.trim()

        if item_id == "" do
          []
        else
          [
            %{
              "id" => item_id,
              "name" => default_name(entry, item_id),
              "copper_value" => int_field(entry, ["copper_value"], 0),
              "quantity" => max(1, int_field(entry, ["quantity"], 1))
            }
          ]
        end

      _ ->
        []
    end)
  end

  def normalize_items(_), do: []

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

  @doc """
  The same coins converted up: 10 copper is 1 silver and 500 copper is 1 gold.
  The total stays the same; gold, silver and copper are always present.

      iex> TalesForge.Game.Inventory.normalize_coins(%{"gold" => 0, "silver" => 20, "copper" => 300})
      %{"gold" => 1, "silver" => 0, "copper" => 0}
      iex> TalesForge.Game.Inventory.normalize_coins(%{"silver" => 100, "copper" => 505})
      %{"gold" => 3, "silver" => 0, "copper" => 5}
  """
  @spec normalize_coins(map() | nil) :: %{String.t() => non_neg_integer()}
  def normalize_coins(coins) do
    total = max(0, coin_total_copper(coins || %{}))

    %{
      "gold" => div(total, @copper_per_gold),
      "silver" => div(rem(total, @copper_per_gold), @copper_per_silver),
      "copper" => rem(total, @copper_per_silver)
    }
  end

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

  def resolve_item_id(hint, items) when is_binary(hint) do
    hint = String.trim(hint)
    normalized = String.downcase(hint)

    cond do
      hint == "" -> nil
      match = Enum.find(items, &(&1["id"] == normalized)) -> match["id"]
      true -> Enum.find_value(items, &matching_item_id(normalized, &1))
    end
  end

  def resolve_item_id(_, _), do: nil

  defp matching_item_id(normalized, item) do
    id = item["id"]
    name = String.downcase(Map.get(item, "name", id))
    readable = String.replace(String.downcase(id), "_", " ")

    if item_name_matches?(normalized, readable, name), do: id
  end

  defp item_name_matches?(normalized, readable, name) do
    String.contains?(normalized, readable) or String.contains?(readable, normalized) or
      String.contains?(normalized, name) or String.contains?(name, normalized)
  end

  defp do_apply(%Transaction{} = t) do
    t = step(t, t.action.action_type, t.action.parameters || %{})
    :ok = NPC.persist_stock_updates(t.session_id, t.npc_updates)

    character =
      t.character
      |> Map.put("inventory", t.inventory)
      |> Map.put("coins", t.coins)

    world_state =
      t.world_state
      |> put_in(["character"], character)
      |> put_ground_items(t.location_id, t.ground_items)

    {:ok, world_state, %{applied: t.applied}}
  rescue
    error in ArgumentError ->
      {:error, Exception.message(error)}
  end

  # One step per action type: each changes the inventory, ground items,
  # coins or NPC stock of the transaction and sets what it applied.
  defp step(t, :drop, params) do
    item_id = item_ref(t.action)
    qty = action_quantity(params)
    source = Enum.at(t.inventory, find_item_index(t.inventory, item_id))

    %{
      t
      | inventory: remove_item(t.inventory, item_id, qty),
        ground_items: add_item(t.ground_items, carried(source, item_id, qty)),
        applied: ["dropped #{qty}x #{item_id}"]
    }
  end

  defp step(t, :pickup, params) do
    item_id = item_ref(t.action)
    qty = action_quantity(params)
    source = Enum.at(t.ground_items, find_item_index(t.ground_items, item_id))

    %{
      t
      | inventory: add_item(t.inventory, carried(source, item_id, qty)),
        ground_items: remove_item(t.ground_items, item_id, qty),
        applied: ["picked up #{qty}x #{item_id}"]
    }
  end

  defp step(t, :buy, params) do
    item_id = Map.get(params, "item_id", "") |> to_string() |> String.trim()
    qty = action_quantity(params)
    npc_id = resolve_buy_npc_id(t.action, params, t.npc_stock)
    stock = normalize_stock(Map.get(t.npc_stock, npc_id, []))
    stock_item = Enum.find(stock, &(&1["id"] == item_id))
    price = price_copper(params, stock_item)
    total = price * qty

    %{
      t
      | inventory:
          add_item(t.inventory, %{
            "id" => item_id,
            "name" => stock_item["name"],
            "copper_value" => price,
            "quantity" => qty
          }),
        coins: deduct_coins(t.coins, total),
        applied: ["bought #{qty}x #{item_id} for #{total}c"],
        npc_updates: %{npc_id => remove_item(stock, item_id, qty)}
    }
  end

  defp step(t, :sell, params) do
    item_id = Map.get(params, "item_id", "") |> to_string() |> String.trim()
    qty = action_quantity(params)
    price = int_field(params, ["price_copper"], 0)

    %{
      t
      | inventory: remove_item(t.inventory, item_id, qty),
        coins: add_coins(t.coins, price * qty),
        applied: ["sold #{qty}x #{item_id} for #{price * qty}c"]
    }
  end

  defp step(t, :spend, _params) do
    amount = spend_amount(t.action)
    %{t | coins: deduct_coins(t.coins, amount), applied: ["spent #{amount}c"]}
  end

  defp step(t, :trade, params) do
    {:ok, give_items, receive_items, counterparty} = trade_legs(params)

    t
    |> give(give_items, counterparty)
    |> apply_trade(receive_items, counterparty)
  end

  # An item as carried: its id, name, copper value and quantity.
  defp carried(source, item_id, qty) do
    %{
      "id" => item_id,
      "name" => source["name"],
      "copper_value" => Map.get(source, "copper_value", 0),
      "quantity" => qty
    }
  end

  # The give legs of a trade: out of the inventory, onto the ground when
  # the counterparty is the ground.
  defp give(t, give_items, counterparty) do
    Enum.reduce(give_items, %{t | applied: []}, fn leg, t ->
      source = Enum.at(t.inventory, find_item_index(t.inventory, leg["id"]))

      ground =
        if counterparty == "ground",
          do: add_item(t.ground_items, carried(source, leg["id"], leg["quantity"])),
          else: t.ground_items

      %{
        t
        | inventory: remove_item(t.inventory, leg["id"], leg["quantity"]),
          ground_items: ground,
          applied: t.applied ++ ["gave #{leg["quantity"]}x #{leg["id"]}"]
      }
    end)
  end

  # The receive legs of a trade: from the ground, or from the
  # counterparty's stock (saved as its NPC update).
  defp apply_trade(t, receive_items, "ground") do
    Enum.reduce(receive_items, t, fn leg, t ->
      source = Enum.at(t.ground_items, find_item_index(t.ground_items, leg["id"]))

      %{
        t
        | inventory: add_item(t.inventory, carried(source, leg["id"], leg["quantity"])),
          ground_items: remove_item(t.ground_items, leg["id"], leg["quantity"]),
          applied: t.applied ++ ["received #{leg["quantity"]}x #{leg["id"]} from ground"]
      }
    end)
  end

  defp apply_trade(t, receive_items, counterparty) do
    from = normalize_stock(Map.get(t.npc_stock, counterparty, []))

    {t, stock} =
      Enum.reduce(receive_items, {t, from}, fn leg, {t, stk} ->
        source = Enum.at(stk, find_item_index(stk, leg["id"]))

        inventory =
          add_item(t.inventory, %{
            "id" => leg["id"],
            "name" => source["name"],
            "copper_value" => price_copper(%{}, source),
            "quantity" => leg["quantity"]
          })

        {%{
           t
           | inventory: inventory,
             applied:
               t.applied ++ ["received #{leg["quantity"]}x #{leg["id"]} from #{counterparty}"]
         }, remove_item(stk, leg["id"], leg["quantity"])}
      end)

    %{t | npc_updates: %{counterparty => stock}}
  end

  # The action with its item, NPC and amount filled in from the inventory,
  # the ground and the NPC stock.
  defp resolve_action(%Transaction{action: %SingleAction{action_type: type} = action} = t) do
    params = params(action)
    resolved = resolve_params(type, params, t)
    %{t | action: %{action | parameters: resolved, target: resolved_target(action, params)}}
  end

  defp resolve_params(type, params, %Transaction{action: action, inventory: inventory})
       when type in [:drop, :sell],
       do: put_item_id(params, action, inventory)

  defp resolve_params(:pickup, params, %Transaction{action: action, ground_items: ground_items}),
    do: put_item_id(params, action, ground_items)

  defp resolve_params(:buy, params, %Transaction{action: action, npc_stock: npc_stock}) do
    named_npc = npc_ref(action, "")
    item_id = item_id_in(params, action, buy_stock(npc_stock, named_npc))

    params
    |> Map.put("item_id", item_id || "")
    |> Map.put("npc_id", buy_npc(npc_stock, named_npc, item_id))
  end

  defp resolve_params(:spend, params, %Transaction{action: action}),
    do: Map.put(params, "amount_copper", spend_amount(%{action | parameters: params}))

  defp resolve_params(_type, params, _t), do: params

  defp put_item_id(params, action, items),
    do: Map.put(params, "item_id", item_id_in(params, action, items) || "")

  defp item_id_in(params, action, items),
    do: Map.get(params, "item_id") || resolve_item_id(to_string(action.target || ""), items)

  # The stock to buy from: the named NPC's, or every present NPC's.
  defp buy_stock(npc_stock, ""),
    do: npc_stock |> Map.values() |> List.flatten() |> normalize_stock()

  defp buy_stock(npc_stock, named_npc), do: normalize_stock(Map.get(npc_stock, named_npc, []))

  defp buy_npc(npc_stock, "", item_id), do: seller_for_item(npc_stock, item_id || "") || ""
  defp buy_npc(_npc_stock, named_npc, _item_id), do: named_npc

  defp resolved_target(%SingleAction{action_type: type} = action, params)
       when type in [:drop, :pickup],
       do: Map.get(params, "item_id") || action.target

  defp resolved_target(%SingleAction{target: target}, _params), do: target

  defp ground_items_for(world_state, location_id) do
    world_state
    |> World.runtime_location(location_id)
    |> Map.get("ground_items", [])
    |> normalize_items()
  end

  defp put_ground_items(world_state, location_id, ground_items) do
    location = World.runtime_location(world_state, location_id)
    updated = Map.put(location, "ground_items", ground_items)
    put_in(world_state, ["locations", location_id], updated)
  end

  defp item_ref(%SingleAction{} = action) do
    params = action.parameters || %{}

    (Map.get(params, "item_id") || action.target || "")
    |> to_string()
    |> String.trim()
  end

  defp npc_ref(%SingleAction{} = action, default) do
    params = action.parameters || %{}

    (Map.get(params, "npc_id") || action.target || default)
    |> to_string()
    |> String.trim()
  end

  defp resolve_buy_npc_id(action, params, npc_stock) do
    case npc_ref(%{action | parameters: params}, "") do
      "" ->
        item_id = params |> Map.get("item_id", "") |> to_string() |> String.trim()
        seller_for_item(npc_stock, item_id) || ""

      npc_id ->
        npc_id
    end
  end

  defp seller_for_item(_npc_stock, ""), do: nil

  defp seller_for_item(npc_stock, item_id) when is_map(npc_stock) and is_binary(item_id) do
    Enum.find_value(npc_stock, fn {npc_id, stock} ->
      if item_quantity(normalize_stock(stock), item_id) > 0, do: to_string(npc_id)
    end)
  end

  defp seller_for_item(_, _), do: nil

  defp action_quantity(params) do
    max(1, int_field(params, ["quantity"], 1))
  end

  defp spend_amount(%SingleAction{} = action) do
    params = action.parameters || %{}

    case int_field(params, ["amount_copper"], 0) do
      amount when amount > 0 ->
        amount

      _ ->
        parse_copper_hint(to_string(action.target || ""))
    end
  end

  def parse_copper_hint(text) when is_binary(text) do
    case Regex.run(~r/(\d+)\s*c(?:opper)?\b/i, text) do
      [_, digits] -> String.to_integer(digits)
      _ -> 0
    end
  end

  defp price_copper(params, stock_item) do
    case int_field(params, ["price_copper"], 0) do
      0 -> int_field(stock_item, ["price_copper", "copper_value"], 0)
      price -> price
    end
  end

  defp trade_legs(params) do
    give = Map.get(params, "give", [])
    receive = Map.get(params, "receive", [])
    counterparty = Map.get(params, "counterparty", "ground") |> to_string() |> String.trim()

    cond do
      not is_list(give) or not is_list(receive) ->
        {:error, "Trade requires give and receive item lists."}

      give == [] or receive == [] ->
        {:error, "Trade requires at least one item to give and one to receive."}

      true ->
        {:ok, normalize_items(give), normalize_items(receive), counterparty}
    end
  end

  defp validate_trade_give(inventory, give_items) do
    Enum.reduce_while(give_items, :ok, fn leg, _acc ->
      if item_quantity(inventory, leg["id"]) < leg["quantity"] do
        {:halt, {:error, "Cannot trade away '#{leg["id"]}' — not in inventory."}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_trade_receive(receive_items, "ground", %Transaction{ground_items: ground_items}) do
    Enum.reduce_while(receive_items, :ok, fn leg, _acc ->
      if item_quantity(ground_items, leg["id"]) < leg["quantity"] do
        {:halt, {:error, "Cannot receive '#{leg["id"]}' — not on the ground here."}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_trade_receive(receive_items, counterparty, %Transaction{npc_stock: npc_stock}) do
    stock = normalize_stock(Map.get(npc_stock, counterparty, []))

    Enum.reduce_while(receive_items, :ok, fn leg, _acc ->
      if item_quantity(stock, leg["id"]) < leg["quantity"] do
        {:halt, {:error, "Cannot receive '#{leg["id"]}' from #{counterparty}."}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp npc_stock_keys(%SingleAction{action_type: :buy} = action, present_npcs) do
    case npc_ref(action, "") do
      "" -> present_npcs
      npc_id -> Enum.uniq([npc_id | List.wrap(present_npcs)])
    end
  end

  defp npc_stock_keys(%SingleAction{action_type: :trade} = action, _present_npcs) do
    params = action.parameters || %{}
    counterparty = params |> Map.get("counterparty", "ground") |> to_string() |> String.trim()

    if counterparty in ["", "ground"], do: [], else: [counterparty]
  end

  defp npc_stock_keys(_action, _present_npcs), do: []

  defp find_item_index(items, item_id) do
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

  defp default_name(entry, item_id) do
    case Map.get(entry, "name") do
      name when is_binary(name) and name != "" -> name
      _ -> item_id |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp int_field(map, keys, default) when is_map(map) do
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

  defp int_field(_, _, default), do: default
end
