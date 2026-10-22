defmodule TalesForge.Game.CounterOffer do
  @moduledoc """
  A trader's counter-offer on a sale, kept in the world's open offer: the
  trader is its `"receiver"` (she buys from the player, the giver). Accepting
  it sells the item to her at her price (`TalesForge.Game.Offer.answered/2`).
  """

  alias TalesForge.GameCharacter

  @doc "The trader of a stored offer: the buyer of a counter-offer on a sale, else the giver."
  @spec trader(map()) :: String.t() | nil
  def trader(stored), do: stored["receiver"] || stored["giver"]

  @doc "The buyer of a stored counter-offer on a sale, or nil."
  @spec buyer(map()) :: GameCharacter.t() | nil
  def buyer(%{"receiver" => slug} = stored) when is_binary(slug),
    do: %GameCharacter{slug: slug, name: stored["receiver_name"] || slug}

  def buyer(_stored), do: nil

  @doc "The stored offer with the buyer of a counter-offer on a sale."
  @spec put_buyer(map(), GameCharacter.t() | nil) :: map()
  def put_buyer(stored, %GameCharacter{slug: slug, name: name}),
    do: Map.merge(stored, %{"receiver" => slug, "receiver_name" => name})

  def put_buyer(stored, nil), do: stored

  @doc "The action that accepts a stored offer: a sale to its buyer, else a buy from its giver."
  @spec accepting(map()) :: {:buy | :sell, String.t()}
  def accepting(%{"receiver" => slug}) when is_binary(slug), do: {:sell, slug}
  def accepting(stored), do: {:buy, stored["giver"]}
end
