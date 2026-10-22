defmodule TalesForge.Game.Inventory do
  @moduledoc false

  defmodule Transaction do
    # One inventory action between two GameCharacters (refactor plan step
    # 10d): the acting `character` and, for a buy, a sale or a trade with an
    # NPC, one of the `traders`, whose stock is their inventory with
    # `price_copper` set; a buy or a sale is one `TalesForge.Game.Trade`
    # with them. It also has the world, the location, the resolved
    # action and the ground items the steps change. `applied` is the log of
    # what happened and `changed` the ids of the traders whose inventory
    # changed.
    @moduledoc false

    @enforce_keys [:world_state, :location_id, :action, :character]
    defstruct [
      :world_state,
      :location_id,
      :action,
      :character,
      ground_items: [],
      traders: %{},
      applied: [],
      changed: []
    ]

    @type t :: %__MODULE__{
            world_state: map(),
            location_id: String.t(),
            action: TalesForge.Game.Schemas.SingleAction.t(),
            character: TalesForge.GameCharacter.t(),
            ground_items: [map()],
            traders: %{String.t() => TalesForge.GameCharacter.t()},
            applied: [String.t()],
            changed: [String.t()]
          }
  end

  import TalesForge.Game.Goods, only: [find_item_index: 2, int_field: 3]

  alias TalesForge.Game.Goods
  alias TalesForge.Game.ItemWords
  alias TalesForge.Game.NamedPrice
  alias TalesForge.Game.Offer
  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Game.Trade
  alias TalesForge.Game.World
  alias TalesForge.GameCharacter

  @inventory_actions ~w(pickup drop buy sell trade spend)a

  @copper_per_silver 10
  @copper_per_gold 500

  def inventory_actions, do: @inventory_actions

  @doc false
  # True when the inventory step runs for this handler and action.
  @spec applies?(map(), SingleAction.t()) :: boolean()
  def applies?(handler, %SingleAction{action_type: type}),
    do: handler.handler == "inventory" and type in @inventory_actions

  @doc false
  # Pure: the acting character is the world's `"character"`, and `traders`
  # are the GameCharacters `trader_ids/2` names (`TalesForge.GameCharacter.Roster.traders/2`).
  # Returns the world with the character's new inventory and coins, and the
  # traders whose inventory and coins changed, which the caller saves
  # (`TalesForge.GameCharacter.Roster.put_inventories/2`). All of it or, on an error, none.
  @spec apply_transaction(map(), %{String.t() => GameCharacter.t()}, SingleAction.t()) ::
          {:ok, map(), %{applied: [String.t()]}, [GameCharacter.t()]} | {:error, String.t()}
  def apply_transaction(world_state, traders, %SingleAction{} = action) when is_map(traders) do
    with {:ok, %Transaction{} = done} <- world_state |> transaction(traders, action) |> decide(),
         do: finish(done)
  end

  @doc false
  # Pure: what the trader the buy `action` names asks for the item, as an
  # `TalesForge.Game.Offer`, or `{:error, reason}` when nothing here is for
  # sale by those words. Nothing moves.
  @spec offer(map(), %{String.t() => GameCharacter.t()}, SingleAction.t()) ::
          {:ok, Offer.t()} | {:error, String.t()}
  def offer(world_state, traders, %SingleAction{action_type: :buy} = action) do
    with {:ok, _npc_id, %Offer{} = offer} <-
           world_state |> transaction(traders, action) |> purchase_offer(),
         do: {:ok, offer}
  end

  @doc false
  # The buy `action` with the item its words `text` name from its seller's
  # stock (every trader's when it names no seller), when it has none. An
  # unclear buy ("I order a meal") already has its `"options"` from Jev's
  # kind target (`goods:<kind>`, `TalesForge.Game.JevIntent`).
  # Playtest session 8a9dbde9 (#470 retest): "I buy a mug of ale from
  # Brenna" had no item, and it became a 2c payment nobody received.
  @spec named_item(SingleAction.t(), %{String.t() => GameCharacter.t()}, String.t() | nil) ::
          SingleAction.t()
  def named_item(%SingleAction{action_type: :buy} = action, traders, text) do
    params = action.parameters || %{}

    stock = seller_stock(traders, npc_ref(action, ""))

    with "" <- param_item_id(params),
         id when is_binary(id) and id != "" <- item_named(text, stock) do
      %{action | parameters: Map.put(params, "item_id", id)}
    else
      _ -> action
    end
  end

  @doc false
  # True when the buy `action` is unclear: it names no item and lists options (`named_item/3`).
  @spec unclear?(SingleAction.t()) :: boolean()
  def unclear?(%SingleAction{parameters: %{"options" => [_ | _]} = params}),
    do: param_item_id(params) == ""

  def unclear?(%SingleAction{}), do: false

  @doc """
  The id of the item of `stock` that the words `text` name (its id, its
  name, or the last word of its name: "an ale" names Mug of Ale), or nil.
  """
  @spec item_named(String.t() | nil, [map()]) :: String.t() | nil
  def item_named(text, stock),
    do: resolve_item_id(to_string(text), stock) || head_noun(text, stock)

  # The item whose name ends in a word of `text` ("an ale": Mug of Ale).
  defp head_noun(text, stock) do
    words = ~r/[a-z]+/ |> Regex.scan(String.downcase(to_string(text))) |> List.flatten()

    Enum.find_value(stock, fn item ->
      noun = item["name"] |> String.downcase() |> String.split() |> List.last()
      if noun in words, do: item["id"]
    end)
  end

  defp seller_stock(traders, npc_id) do
    case Map.fetch(traders, npc_id) do
      {:ok, trader} -> normalize_stock(trader.inventory)
      :error -> traders |> Map.values() |> Enum.flat_map(&normalize_stock(&1.inventory))
    end
  end

  defp transaction(world_state, traders, action) when is_map(traders) do
    character = GameCharacter.from_sheet(Map.get(world_state, "character", %{}))
    location_id = character.location_id || "weary_pilgrim"

    resolve_action(%Transaction{
      world_state: world_state,
      location_id: location_id,
      action: action,
      character: %{character | inventory: normalize_items(character.inventory)},
      ground_items: ground_items_for(world_state, location_id),
      traders: Map.new(traders, fn {id, gc} -> {id, stocked(gc)} end)
    })
  end

  # The one decision of an action: it is done, or `{:error, reason}` and
  # nothing moved. A buy or a sale is one `TalesForge.Game.Trade`.
  defp decide(%Transaction{action: %SingleAction{action_type: type}} = t)
       when type in [:buy, :sell] do
    with {:ok, npc_id, %Trade{} = trade} <- to_trade(type, t),
         {:ok, %Trade{} = done} <- Trade.execute(trade),
         do: {:ok, traded(type, t, {npc_id, done})}
  end

  defp decide(%Transaction{action: %SingleAction{action_type: type} = action} = t) do
    with :ok <- validate_transaction(t), do: {:ok, step(t, type, params(action))}
  rescue
    error in ArgumentError ->
      {:error, Exception.message(error)}
  end

  # A price the player names is settled against the trader's
  # (`NamedPrice.settle/3`): the trade at it, or her price as an open offer.
  defp to_trade(:buy, t) do
    with {:ok, npc_id, %Offer{item: %{}} = offer} <- purchase_offer(t),
         do:
           settled(
             npc_id,
             NamedPrice.deal(:buy, Offer.to_trade(offer, t.character), named_price(t))
           )
  end

  defp to_trade(:sell, t), do: sale_trade(t)

  # A purchase: the trader offers the stock item for its price.
  defp purchase_offer(%Transaction{action: action} = t) do
    params = params(action)
    npc_id = resolve_buy_npc_id(action, params, t)

    case stock_offer(Map.get(t.traders, npc_id), stock(t, npc_id), params) do
      {:ok, offer} -> {:ok, npc_id, offer}
      :error -> {:error, not_for_sale(t, param_item_id(params))}
    end
  end

  defp stock_offer(%GameCharacter{} = trader, stock, params) do
    case param_item_id(params) do
      "" -> options_offer(trader, listed(stock, params["options"]), params)
      id -> item_offer(trader, Enum.find(stock, &(&1["id"] == id)), params)
    end
  end

  defp stock_offer(nil, _stock, _params), do: :error

  defp item_offer(trader, %{} = item, params),
    do: {:ok, %Offer{giver: trader, item: goods(item, params), price: total(params, item)}}

  defp item_offer(_trader, nil, _params), do: :error

  # An unclear buy: the trader's options from stock, in the listed order,
  # each with its price, and no item yet.
  defp options_offer(_trader, [], _params), do: :error

  defp options_offer(trader, items, params) do
    options = Enum.map(items, &%{"item" => goods(&1, params), "price" => total(params, &1)})
    {:ok, %Offer{giver: trader, item: nil, price: nil, options: options}}
  end

  defp listed(stock, ids),
    do: ids |> List.wrap() |> Enum.flat_map(fn id -> Enum.filter(stock, &(&1["id"] == id)) end)

  # A sale: the character gives the carried item, and the price is the one
  # on the action (a haggle's), else the item's value, else what the buyer
  # sells it for (Hilde's hunting knife, 15c: playtest session 8a9dbde9).
  defp sale_trade(%Transaction{character: character, action: action} = t) do
    params = params(action)
    item_id = param_item_id(params)
    npc_id = npc_ref(action, "")
    carried = Enum.find(character.inventory, &(&1["id"] == item_id))

    case {item_id, Map.get(t.traders, npc_id)} do
      {"", _trader} ->
        {:error, "Sell requires parameters.item_id."}

      {_item_id, nil} ->
        {:error, "Nobody here buys '#{item_id}'."}

      {_item_id, %GameCharacter{} = trader} ->
        settled(npc_id, NamedPrice.deal(:sell, sale_to(trader, carried, t), named_price(t)))
    end
  end

  # The sale to `trader` at her price: her stock price, else the item's value.
  defp sale_to(trader, carried, %Transaction{character: character, action: action}) do
    params = params(action)
    item_id = param_item_id(params)
    stocked = Enum.find(trader.inventory, &(&1["id"] == item_id))

    %Trade{
      giver: character,
      receiver: trader,
      item: goods(carried || %{"id" => item_id}, params),
      price: total(params, valued(carried, stocked))
    }
  end

  # Her stock price, else the item's own value (Fredrik, 2026-10-22).
  defp valued(_carried, %{"price_copper" => price} = stocked) when price > 0, do: stocked
  defp valued(carried, stocked), do: carried || stocked

  defp named_price(%Transaction{action: action}), do: params(action)["named_price"]

  defp settled(npc_id, {:trade, %Trade{} = trade}), do: {:ok, npc_id, trade}
  defp settled(_npc_id, counter_offer), do: counter_offer

  defp total(params, item), do: price_copper(params, item) * action_quantity(params)

  defp goods(item, params),
    do: %{"id" => item["id"], "name" => item["name"], "quantity" => action_quantity(params)}

  # Why a purchase found nothing to buy, with what is for sale here, so the
  # GM offers no goods the traders do not have (Gentry's playtest session
  # 3d9788e0 on 2026-10-18: "I buy a loaf of bread" at an inn that sells ale).
  defp not_for_sale(%Transaction{} = t, item_id) do
    asked = if item_id == "", do: "That is", else: "'#{item_id}' is"

    case all_stock(t) do
      [] -> "#{asked} not sold here. Nothing is for sale here."
      stock -> "#{asked} not sold here. For sale: #{Enum.map_join(stock, ", ", &offer/1)}."
    end
  end

  defp offer(%{"name" => name, "price_copper" => price}), do: "#{name} (#{price}c)"

  # The transaction after the trade `done` with the trader `npc_id`.
  defp traded(:buy, t, {npc_id, %Trade{giver: trader, receiver: character} = done}),
    do: put_trade(t, {npc_id, trader, character}, applied("bought", done))

  defp traded(:sell, t, {npc_id, %Trade{giver: character, receiver: trader} = done}),
    do: put_trade(t, {npc_id, trader, character}, applied("sold", done))

  defp applied(verb, %Trade{item: item, price: price}),
    do: "#{verb} #{item["quantity"]}x #{item["id"]} for #{price}c"

  defp put_trade(%Transaction{} = t, {npc_id, trader, character}, applied) do
    %{
      t
      | character: character,
        traders: Map.put(t.traders, npc_id, trader),
        changed: Enum.uniq(t.changed ++ [npc_id]),
        applied: [applied]
    }
  end

  # A trader with its inventory as stock: every item priced.
  defp stocked(%GameCharacter{} = trader),
    do: %{trader | inventory: normalize_stock(trader.inventory)}

  defp stock(%Transaction{traders: traders}, npc_id) do
    case Map.get(traders, npc_id) do
      %GameCharacter{inventory: inventory} -> inventory
      nil -> []
    end
  end

  defp all_stock(%Transaction{traders: traders}),
    do: traders |> Map.values() |> Enum.flat_map(& &1.inventory)

  def validate_transaction(%Transaction{action: %SingleAction{action_type: type} = action} = t),
    do: validate(type, action, t)

  defp validate(:drop, action, %Transaction{character: character}) do
    with item_id when item_id != "" <- item_ref(action),
         true <- item_quantity(character.inventory, item_id) >= action_quantity(params(action)) do
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

  defp validate(:spend, action, %Transaction{character: character}) do
    amount = spend_amount(action)

    cond do
      amount <= 0 ->
        {:error, "Spend requires parameters.amount_copper."}

      coin_total_copper(character.coins) < amount ->
        {:error, "Insufficient funds (need #{amount}c)."}

      true ->
        :ok
    end
  end

  defp validate(:trade, action, %Transaction{character: character} = t) do
    with {:ok, give_items, receive_items, counterparty} <- trade_legs(params(action)),
         :ok <- validate_trade_give(character.inventory, give_items) do
      validate_trade_receive(receive_items, counterparty, t)
    end
  end

  defp validate(_type, _action, _t), do: {:error, "Not an inventory action."}

  defp params(%SingleAction{parameters: params}), do: params || %{}

  defp param_item_id(params), do: params |> Map.get("item_id", "") |> to_string() |> String.trim()

  defdelegate item_quantity(items, item_id), to: Goods
  defdelegate add_item(items, item), to: Goods
  defdelegate remove_item(items, item_id, quantity \\ 1), to: Goods
  defdelegate coin_total_copper(coins), to: Goods
  defdelegate deduct_coins(coins, amount_copper), to: Goods
  defdelegate add_coins(coins, amount_copper), to: Goods

  # A sold-out entry (quantity 0) is no stock: it was read as 1, so a
  # trader sold an item it did not have (trade offers, PR B).
  def normalize_stock(raw) when is_list(raw) do
    Enum.flat_map(raw, fn
      %{} = entry ->
        item_id = entry |> Map.get("id", "") |> to_string() |> String.trim()
        quantity = int_field(entry, ["quantity"], 1)

        if item_id == "" or quantity < 1 do
          []
        else
          [
            %{
              "id" => item_id,
              "name" => default_name(entry, item_id),
              "price_copper" => int_field(entry, ["price_copper", "copper_value"], 0),
              "quantity" => quantity
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

  defdelegate resolve_item_id(hint, items), to: ItemWords

  @doc """
  The sale of a carried item, as a purchase takes its item and price from
  the stock: `"item_id"` is the item of `inventory` whose id is `item`, else
  the one `text` names. Empty when no carried item matches. The price is
  the buyer's (her stock price, else the item's value, `sale_trade/1`).

  Playtest v319 on 2026-10-18 (drift session 464229eb): "I sell my mug of
  ale to Brenna" was a sale with no item.

      iex> inventory = [%{"id" => "ale_mug", "name" => "Mug of Ale", "copper_value" => 2}]
      iex> TalesForge.Game.Inventory.sale(nil, "I sell my mug of ale to Brenna", inventory)
      %{"item_id" => "ale_mug"}
      iex> TalesForge.Game.Inventory.sale("ale_mug", "I sell it", inventory)
      %{"item_id" => "ale_mug"}
      iex> TalesForge.Game.Inventory.sale(nil, "I sell my boots", inventory)
      %{}
  """
  @spec sale(String.t() | nil, String.t() | nil, [map()] | nil) :: map()
  def sale(item, text, inventory) do
    items = normalize_items(inventory)

    case Enum.find(items, &(&1["id"] == item)) || named_item(text, items) do
      nil -> %{}
      %{"id" => id} -> %{"item_id" => id}
    end
  end

  defp named_item(text, items) do
    case resolve_item_id(to_string(text || ""), items) do
      nil -> nil
      id -> Enum.find(items, &(&1["id"] == id))
    end
  end

  defp finish(%Transaction{character: %GameCharacter{inventory: inventory, coins: coins}} = t) do
    character = GameCharacter.put(t.character, inventory: inventory, coins: coins)

    world_state =
      t.world_state
      |> put_in(["character"], GameCharacter.to_sheet(character))
      |> put_ground_items(t.location_id, t.ground_items)

    {:ok, world_state, %{applied: t.applied}, Enum.map(t.changed, &Map.fetch!(t.traders, &1))}
  end

  # One step per action type: each changes the character's inventory or
  # coins, the ground items or a trader's inventory, and sets what it
  # applied.
  defp step(%Transaction{character: character} = t, :drop, params) do
    item_id = item_ref(t.action)
    qty = action_quantity(params)
    source = Enum.at(character.inventory, find_item_index(character.inventory, item_id))

    %{
      t
      | character: %{character | inventory: remove_item(character.inventory, item_id, qty)},
        ground_items: add_item(t.ground_items, carried(source, item_id, qty)),
        applied: ["dropped #{qty}x #{item_id}"]
    }
  end

  defp step(%Transaction{character: character} = t, :pickup, params) do
    item_id = item_ref(t.action)
    qty = action_quantity(params)
    source = Enum.at(t.ground_items, find_item_index(t.ground_items, item_id))

    %{
      t
      | character: %{
          character
          | inventory: add_item(character.inventory, carried(source, item_id, qty))
        },
        ground_items: remove_item(t.ground_items, item_id, qty),
        applied: ["picked up #{qty}x #{item_id}"]
    }
  end

  defp step(%Transaction{character: character} = t, :spend, _params) do
    amount = spend_amount(t.action)

    %{
      t
      | character: %{character | coins: deduct_coins(character.coins, amount)},
        applied: ["spent #{amount}c"]
    }
  end

  defp step(t, :trade, params) do
    {:ok, give_items, receive_items, counterparty} = trade_legs(params)

    t
    |> give(give_items, counterparty)
    |> apply_trade(receive_items, counterparty)
  end

  # The trader `npc_id` with `stock` as its inventory, marked as changed.
  defp put_stock(%Transaction{traders: traders} = t, npc_id, stock) do
    trader = Map.fetch!(traders, npc_id)

    %{
      t
      | traders: Map.put(traders, npc_id, %{trader | inventory: stock}),
        changed: Enum.uniq(t.changed ++ [npc_id])
    }
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
    Enum.reduce(give_items, %{t | applied: []}, fn leg, %Transaction{character: character} = t ->
      inventory = character.inventory
      source = Enum.at(inventory, find_item_index(inventory, leg["id"]))

      ground =
        if counterparty == "ground",
          do: add_item(t.ground_items, carried(source, leg["id"], leg["quantity"])),
          else: t.ground_items

      %{
        t
        | character: %{character | inventory: remove_item(inventory, leg["id"], leg["quantity"])},
          ground_items: ground,
          applied: t.applied ++ ["gave #{leg["quantity"]}x #{leg["id"]}"]
      }
    end)
  end

  # The receive legs of a trade: from the ground, or out of the
  # counterparty's inventory.
  defp apply_trade(t, receive_items, "ground") do
    Enum.reduce(receive_items, t, fn leg, %Transaction{character: character} = t ->
      source = Enum.at(t.ground_items, find_item_index(t.ground_items, leg["id"]))
      received = carried(source, leg["id"], leg["quantity"])

      %{
        t
        | character: %{character | inventory: add_item(character.inventory, received)},
          ground_items: remove_item(t.ground_items, leg["id"], leg["quantity"]),
          applied: t.applied ++ ["received #{leg["quantity"]}x #{leg["id"]} from ground"]
      }
    end)
  end

  defp apply_trade(t, receive_items, counterparty),
    do: Enum.reduce(receive_items, t, &receive(&2, &1, counterparty))

  # One receive leg out of the counterparty's inventory.
  defp receive(%Transaction{character: character} = t, leg, counterparty) do
    stock = stock(t, counterparty)
    source = Enum.at(stock, find_item_index(stock, leg["id"]))

    received = %{
      "id" => leg["id"],
      "name" => source["name"],
      "copper_value" => price_copper(%{}, source),
      "quantity" => leg["quantity"]
    }

    %{
      put_stock(t, counterparty, remove_item(stock, leg["id"], leg["quantity"]))
      | character: %{character | inventory: add_item(character.inventory, received)},
        applied: t.applied ++ ["received #{leg["quantity"]}x #{leg["id"]} from #{counterparty}"]
    }
  end

  # The action with its item, NPC and amount filled in from the inventory,
  # the ground and the traders' stock.
  defp resolve_action(%Transaction{action: %SingleAction{action_type: type} = action} = t) do
    params = params(action)
    resolved = resolve_params(type, params, t)
    %{t | action: %{action | parameters: resolved, target: resolved_target(action, params)}}
  end

  defp resolve_params(type, params, %Transaction{action: action, character: character})
       when type in [:drop, :sell],
       do: put_item_id(params, action, character.inventory)

  defp resolve_params(:pickup, params, %Transaction{action: action, ground_items: ground_items}),
    do: put_item_id(params, action, ground_items)

  defp resolve_params(:buy, params, %Transaction{action: action} = t) do
    named_npc = npc_ref(action, "")
    item_id = item_id_in(params, action, buy_stock(t, named_npc))

    params
    |> Map.put("item_id", item_id || "")
    |> Map.put("npc_id", buy_npc(t, named_npc, item_id))
  end

  defp resolve_params(:spend, params, %Transaction{action: action}),
    do: Map.put(params, "amount_copper", spend_amount(%{action | parameters: params}))

  defp resolve_params(_type, params, _t), do: params

  defp put_item_id(params, action, items),
    do: Map.put(params, "item_id", item_id_in(params, action, items) || "")

  defp item_id_in(params, action, items),
    do: Map.get(params, "item_id") || resolve_item_id(to_string(action.target || ""), items)

  # The stock to buy from: the named trader's, or every present trader's.
  defp buy_stock(t, ""), do: all_stock(t)
  defp buy_stock(t, named_npc), do: stock(t, named_npc)

  defp buy_npc(t, "", item_id), do: seller_for_item(t, item_id || "") || ""
  defp buy_npc(_t, named_npc, _item_id), do: named_npc

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

  defp resolve_buy_npc_id(action, params, t) do
    case npc_ref(%{action | parameters: params}, "") do
      "" ->
        item_id = param_item_id(params)
        seller_for_item(t, item_id) || ""

      npc_id ->
        npc_id
    end
  end

  defp seller_for_item(_t, ""), do: nil

  defp seller_for_item(%Transaction{traders: traders}, item_id) when is_binary(item_id) do
    Enum.find_value(traders, fn {npc_id, trader} ->
      if item_quantity(trader.inventory, item_id) > 0, do: to_string(npc_id)
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

  defp validate_trade_receive(receive_items, counterparty, %Transaction{} = t) do
    stock = stock(t, counterparty)

    Enum.reduce_while(receive_items, :ok, fn leg, _acc ->
      if item_quantity(stock, leg["id"]) < leg["quantity"] do
        {:halt, {:error, "Cannot receive '#{leg["id"]}' from #{counterparty}."}}
      else
        {:cont, :ok}
      end
    end)
  end

  @doc false
  # The traders `apply_transaction/3` needs for `action`.
  @spec trader_ids(SingleAction.t(), [String.t()]) :: [String.t()]
  def trader_ids(%SingleAction{action_type: type} = action, present_npcs)
      when type in [:buy, :sell] do
    case npc_ref(action, "") do
      "" -> present_npcs
      npc_id -> Enum.uniq([npc_id | List.wrap(present_npcs)])
    end
  end

  def trader_ids(%SingleAction{action_type: :trade} = action, _present_npcs) do
    params = action.parameters || %{}
    counterparty = params |> Map.get("counterparty", "ground") |> to_string() |> String.trim()

    if counterparty in ["", "ground"], do: [], else: [counterparty]
  end

  def trader_ids(_action, _present_npcs), do: []

  defp default_name(entry, item_id) do
    case Map.get(entry, "name") do
      name when is_binary(name) and name != "" -> name
      _ -> item_id |> String.replace("_", " ") |> String.capitalize()
    end
  end
end
