defmodule TalesForge.Game.Offer do
  @moduledoc """
  A price a trader names for an item, before anyone accepts: the `giver`
  would hand over `item` for `price` copper (for the whole quantity). An
  offer moves nothing (`docs/design-trade-offers.md`). Asking a price ("How
  much for a mug of ale?") is an offer, never a purchase (dev lead's call
  on #470's retest, 2026-10-18); a purchase is the offer the `receiver`
  accepts, made the one `TalesForge.Game.Trade` to execute.

  `to_trade/2` makes the accepted offer that trade.

  An unclear buy ("I order a meal") is an offer with no `item` and the
  seller's matching stock as `options` (2-3, cheapest first). The player
  picks one, and the pick is the purchase. A plain yes that picks none
  (`awaits_pick?/2`) buys nothing: the offer stays open as it is, and the
  GM asks which one, as an innkeeper would.

  A session has at most one open offer, kept in its world state
  (`"open_offer"`, `to_world/1`). The player answers it on the next turn
  (`answered/2` makes an accept the purchase); it expires when answered,
  when the player leaves the place or the giver is gone (`expired?/2`),
  after 2 turns with no answer (`aged/1`), or when a new offer replaces it.

      iex> alias TalesForge.Game.Offer
      iex> brenna = %TalesForge.GameCharacter{name: "Brenna Holt"}
      iex> offer = %Offer{giver: brenna, item: %{"id" => "ale_mug", "name" => "Ale", "quantity" => 1}, price: 2}
      iex> Offer.text(offer)
      "Brenna Holt sells Ale for 2c"
      iex> Offer.text(%Offer{giver: brenna, item: nil, price: nil, options: [
      ...>   %{"item" => %{"id" => "stew", "name" => "Stew"}, "price" => 5},
      ...>   %{"item" => %{"id" => "bread", "name" => "Bread and Cheese"}, "price" => 3}]})
      "Brenna Holt has Stew for 5c, or Bread and Cheese for 3c"
      iex> Offer.asked?("How much for a mug of ale, Brenna?")
      true
      iex> Offer.asked?("I buy a mug of ale. Is it cold?")
      false
  """

  alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}
  alias TalesForge.Game.Trade
  alias TalesForge.GameCharacter

  @enforce_keys [:giver, :item, :price]
  defstruct [:giver, :item, :price, receiver: nil, options: [], location_id: nil, age: 0]

  @type option :: %{required(String.t()) => term()}

  @type t :: %__MODULE__{
          giver: GameCharacter.t(),
          receiver: GameCharacter.t() | nil,
          item: %{required(String.t()) => term()} | nil,
          price: non_neg_integer() | nil,
          options: [option()],
          location_id: String.t() | nil,
          age: non_neg_integer()
        }

  # Turns an open offer waits for an answer.
  @max_age 2
  @max_options 3

  # The kinds of goods: the words of an unclear buy, and the item names (pack
  # data) that are of the kind.
  @kinds [
    {"a meal", ~r/\b(meal|food|supper|dinner|lunch|breakfast|something to eat|a bite)\b/iu,
     ~w(stew soup bread cheese pie porridge meal roast sausage)},
    {"a drink", ~r/\b(drink|something to drink|a pint|refreshment)\b/iu,
     ~w(ale beer wine mead cider)}
  ]

  @doc "The trade of the offer `receiver` accepts."
  @spec to_trade(t(), GameCharacter.t()) :: Trade.t()
  def to_trade(%__MODULE__{} = offer, %GameCharacter{} = receiver),
    do: %Trade{giver: offer.giver, receiver: receiver, item: offer.item, price: offer.price}

  @doc """
  `action` as the game plays it: Jev's `ask_price` (a price question) is a
  buy that only asks (`"ask"`), so the board makes the seller's offer and
  nothing moves. Any other action is unchanged.

      iex> alias TalesForge.Game.Schemas.SingleAction
      iex> TalesForge.Game.Offer.asked(%SingleAction{action_type: :ask_price, target: "ale_mug"})
      %SingleAction{action_type: :buy, target: nil, parameters: %{"ask" => true, "item_id" => "ale_mug"}}

  The target is the item, so it becomes the `"item_id"`, and the seller is
  the one who has it in stock.
  """
  @spec asked(SingleAction.t()) :: SingleAction.t()
  def asked(%SingleAction{action_type: :ask_price, target: target} = action) do
    params =
      (action.parameters || %{})
      |> Map.put("ask", true)
      |> put_item(target)

    %{action | action_type: :buy, target: nil, parameters: params}
  end

  def asked(%SingleAction{} = action), do: action

  defp put_item(params, target) when is_binary(target), do: Map.put_new(params, "item_id", target)
  defp put_item(params, _target), do: params

  @doc "True when the buy `action` only asks the price (`asked/1`): it makes an offer, never a trade."
  @spec asks?(SingleAction.t()) :: boolean()
  def asks?(%SingleAction{action_type: :buy, parameters: %{"ask" => true}}), do: true
  def asks?(%SingleAction{}), do: false

  @doc "The offer as the GM quotes it."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{giver: giver, item: nil, options: options}),
    do: "#{giver.name} has #{Enum.map_join(options, ", or ", &priced/1)}"

  def text(%__MODULE__{giver: giver, item: item, price: price}),
    do: "#{giver.name} sells #{name(item)} for #{price}c"

  defp priced(%{"item" => item, "price" => price}), do: "#{name(item)} for #{price}c"

  defp name(item), do: item["name"] || item["id"]

  @doc "True when the words only ask (every sentence a question): a price, not a purchase."
  @spec asked?(String.t() | nil) :: boolean()
  def asked?(text) when is_binary(text) do
    sentences = Regex.split(~r/(?<=[.!?;])\s+/, String.trim(text), trim: true)
    sentences != [] and Enum.all?(sentences, &String.ends_with?(&1, "?"))
  end

  def asked?(_text), do: false

  @doc """
  The options of an unclear buy: the items of `stock` (priced) that the
  words `text` ask for by kind ("a meal": stew, bread and cheese), at most
  3, cheapest first. Empty when the words name no kind or nothing matches.

      iex> stock = [%{"id" => "stew", "name" => "Bowl of Stew", "price_copper" => 5},
      ...>   %{"id" => "ale_mug", "name" => "Ale", "price_copper" => 2},
      ...>   %{"id" => "bread", "name" => "Bread and Cheese", "price_copper" => 3}]
      iex> TalesForge.Game.Offer.options("I order a meal", stock) |> Enum.map(& &1["id"])
      ["bread", "stew"]
      iex> TalesForge.Game.Offer.options("I order a meal", [%{"id" => "ale_mug", "name" => "Ale", "price_copper" => 2}])
      []
  """
  @spec options(String.t() | nil, [map()]) :: [map()]
  def options(text, stock) when is_binary(text) do
    case Enum.find(@kinds, fn {_kind, words, _names} -> Regex.match?(words, text) end) do
      {_kind, _words, names} -> of_kind(stock, names)
      nil -> []
    end
  end

  def options(_text, _stock), do: []

  @doc """
  The kinds of goods in `stock` with more than one item, each with its items
  (at most 3, cheapest first): what a player can ask for without naming an
  item ("a meal"). Jev gets them as targets; the words are its to read.

      iex> stock = [%{"id" => "stew", "name" => "Bowl of Stew", "price_copper" => 5},
      ...>   %{"id" => "ale_mug", "name" => "Ale", "price_copper" => 2},
      ...>   %{"id" => "bread", "name" => "Bread and Cheese", "price_copper" => 2}]
      iex> TalesForge.Game.Offer.kinds(stock) |> Enum.map(fn {kind, items} -> {kind, Enum.map(items, & &1["id"])} end)
      [{"a meal", ["bread", "stew"]}]
  """
  @spec kinds([map()]) :: [{String.t(), [map()]}]
  def kinds(stock) do
    for {kind, _words, names} <- @kinds,
        items = of_kind(stock, names),
        length(items) > 1,
        do: {kind, items}
  end

  defp of_kind(stock, names) do
    stock
    |> Enum.filter(&(kind?(&1, names) and (&1["price_copper"] || 0) > 0))
    |> Enum.sort_by(& &1["price_copper"])
    |> Enum.take(@max_options)
  end

  defp kind?(item, names) do
    ~r/[a-z]+/
    |> Regex.scan(String.downcase(name(item)))
    |> List.flatten()
    |> Enum.any?(&(&1 in names))
  end

  @doc """
  `player_action` with an answer to the open offer of `world` made the
  purchase it accepts: a buy from the giver of the offer's item (or the
  picked option) at the offer's price. A pick or an accept counts as
  proposal plus acceptance; the trader still decides in code
  (`TalesForge.Game.Trade`). A plain yes to an unclear buy
  (`awaits_pick?/2`) picks nothing: a buy it reads becomes words to the
  seller, so nothing moves. Any other player action, or no offer open
  here, is unchanged.
  """
  @spec answered(PlayerAction.t(), map() | nil) :: PlayerAction.t()
  def answered(%PlayerAction{} = player_action, %{"open_offer" => %{} = stored} = world) do
    if awaits_pick?(player_action, world),
      do: ask(player_action, stored["giver"]),
      else: answered_offer(player_action, stored, world)
  end

  def answered(%PlayerAction{} = player_action, _world), do: player_action

  @doc """
  True when `player_action` accepts the open unclear-buy offer of `world`
  (one with `options`, still open here) but picks none of its options: the
  seller must ask which one. That turn does not age the offer; leaving,
  the giver gone or a new offer still end it.

      iex> world = %{"character" => %{"location_id" => "inn"}, "present_npcs" => ["innkeep"],
      ...>   "open_offer" => %{"giver" => "innkeep", "location_id" => "inn", "item" => nil,
      ...>     "options" => [%{"item" => %{"id" => "stew"}, "price" => 5}]}}
      iex> yes = %TalesForge.Game.Schemas.PlayerAction{offer_answer: :accept}
      iex> TalesForge.Game.Offer.awaits_pick?(yes, world)
      true
      iex> TalesForge.Game.Offer.awaits_pick?(%{yes | offer_pick: 0}, world)
      false
  """
  @spec awaits_pick?(PlayerAction.t(), map() | nil) :: boolean()
  def awaits_pick?(
        %PlayerAction{offer_answer: :accept} = player_action,
        %{"open_offer" => %{"item" => nil, "options" => [_ | _] = options} = stored} = world
      ),
      do: is_nil(picked(options, player_action)) and not expired?(stored, world)

  def awaits_pick?(_player_action, _world), do: false

  defp picked(options, %PlayerAction{offer_pick: pick}) when is_integer(pick),
    do: Enum.at(options, pick)

  defp picked(_options, _player_action), do: nil

  # A buy read from a plain yes is the player's words to the seller.
  defp ask(%PlayerAction{action: %SingleAction{action_type: :buy}} = player_action, giver),
    do: %{
      player_action
      | action: %SingleAction{action_type: :speak, target: giver, parameters: %{}}
    }

  defp ask(%PlayerAction{} = player_action, _giver), do: player_action

  defp answered_offer(player_action, stored, world) do
    case chosen(stored, player_action) do
      %{"item" => %{"id" => id} = item, "price" => price} when is_binary(id) ->
        if expired?(stored, world),
          do: player_action,
          else: buy(player_action, stored["giver"], {item, price})

      _ ->
        player_action
    end
  end

  defp chosen(%{"options" => [_ | _] = options}, %PlayerAction{} = player_action),
    do: picked(options, player_action)

  defp chosen(%{"item" => %{}} = stored, %PlayerAction{offer_answer: :accept}), do: stored
  defp chosen(_stored, _player_action), do: nil

  defp buy(%PlayerAction{} = player_action, giver, {item, price}) do
    quantity = max(1, item["quantity"] || 1)

    action = %SingleAction{
      action_type: :buy,
      target: giver,
      parameters: %{
        "item_id" => item["id"],
        "quantity" => quantity,
        "price_copper" => div(price, quantity)
      }
    }

    %{player_action | action: action, offer_answer: :accept}
  end

  @doc """
  True when the stored offer can no longer be answered in `world`: the
  player is not at its place, or its giver is not present.
  """
  @spec expired?(map(), map()) :: boolean()
  def expired?(%{"location_id" => place, "giver" => giver}, world) do
    get_in(world, ["character", "location_id"]) != place or
      giver not in List.wrap(world["present_npcs"])
  end

  def expired?(_stored, _world), do: true

  @doc "The stored offer one unanswered turn older, or nil when it has waited 2 turns."
  @spec aged(map()) :: map() | nil
  def aged(%{"age" => age} = stored) when age + 1 < @max_age, do: %{stored | "age" => age + 1}
  def aged(_stored), do: nil

  @doc "The offer as the world state keeps it (`\"open_offer\"`): ids, item, price, options, place, age."
  @spec to_world(t()) :: map()
  def to_world(%__MODULE__{giver: %GameCharacter{slug: giver}} = offer) do
    %{
      "giver" => giver,
      "giver_name" => offer.giver.name,
      "item" => offer.item,
      "price" => offer.price,
      "options" => offer.options,
      "location_id" => offer.location_id,
      "age" => offer.age
    }
  end

  @doc "The offer kept in the world state (`to_world/1`), for the GM and Jev."
  @spec from_world(map()) :: t()
  def from_world(%{"giver" => giver} = stored) do
    %__MODULE__{
      giver: %GameCharacter{slug: giver, name: stored["giver_name"] || giver},
      item: stored["item"],
      price: stored["price"],
      options: stored["options"] || [],
      location_id: stored["location_id"],
      age: stored["age"] || 0
    }
  end
end
