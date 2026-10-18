defmodule TalesForge.Game.Offer do
  @moduledoc """
  A price a trader names for an item, before anyone accepts: the `giver`
  would hand over `item` for `price` copper (for the whole quantity). An
  offer moves nothing. Asking a price ("How much for a mug of ale?") is an
  offer, never a purchase (dev lead's call on #470's retest, 2026-10-18);
  a purchase is the offer the `receiver` accepts, which `to_trade/1` makes
  the one `TalesForge.Game.Trade` to execute.

      iex> alias TalesForge.Game.Offer
      iex> brenna = %TalesForge.GameCharacter{name: "Brenna Holt"}
      iex> offer = %Offer{giver: brenna, item: %{"id" => "ale_mug", "name" => "Ale", "quantity" => 1}, price: 2}
      iex> Offer.text(offer)
      "Brenna Holt sells Ale for 2c"
      iex> Offer.asked?("How much for a mug of ale, Brenna?")
      true
      iex> Offer.asked?("I buy a mug of ale. Is it cold?")
      false
  """

  alias TalesForge.Game.Trade
  alias TalesForge.GameCharacter

  @enforce_keys [:giver, :item, :price]
  defstruct [:giver, :item, :price, receiver: nil]

  @type t :: %__MODULE__{
          giver: GameCharacter.t(),
          receiver: GameCharacter.t() | nil,
          item: %{required(String.t()) => term()},
          price: non_neg_integer()
        }

  @doc "The trade of the offer `receiver` accepts."
  @spec to_trade(t(), GameCharacter.t()) :: Trade.t()
  def to_trade(%__MODULE__{} = offer, %GameCharacter{} = receiver),
    do: %Trade{giver: offer.giver, receiver: receiver, item: offer.item, price: offer.price}

  @doc "The offer as the GM quotes it."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{giver: giver, item: item, price: price}),
    do: "#{giver.name} sells #{item["name"] || item["id"]} for #{price}c"

  @doc "True when the words only ask (every sentence a question): a price, not a purchase."
  @spec asked?(String.t() | nil) :: boolean()
  def asked?(text) when is_binary(text) do
    sentences = Regex.split(~r/(?<=[.!?;])\s+/, String.trim(text), trim: true)
    sentences != [] and Enum.all?(sentences, &String.ends_with?(&1, "?"))
  end

  def asked?(_text), do: false
end
