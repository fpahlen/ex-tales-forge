defmodule TalesForge.Game.NamedPrice do
  @moduledoc """
  The price the player names for a buy or a sale, in copper, from their own
  words: "for 12 copper", "for twelve copper", "at 12c", "for a silver"
  (Fredrik's rule, 2026-10-22; Gentry's session 89bfac5d T9, "I offer to
  sell Hilde my hunting knife for 12 copper", paid 15c). A count with no
  coin word is not a price. `settle/3` decides it.

      iex> TalesForge.Game.NamedPrice.of("I sell Hilde my hunting knife for 12 copper.")
      12
      iex> TalesForge.Game.NamedPrice.of("I offer twelve copper for it, no, for twelve copper")
      12
      iex> TalesForge.Game.NamedPrice.of("I buy the spearhead at 25c")
      25
      iex> TalesForge.Game.NamedPrice.of("I sell it for a silver")
      10
      iex> TalesForge.Game.NamedPrice.of("I sell my two knives to Hilde")
      nil
  """

  alias TalesForge.Game.{Offer, Trade}

  @words %{
    "a" => 1,
    "an" => 1,
    "one" => 1,
    "two" => 2,
    "three" => 3,
    "four" => 4,
    "five" => 5,
    "six" => 6,
    "seven" => 7,
    "eight" => 8,
    "nine" => 9,
    "ten" => 10,
    "eleven" => 11,
    "twelve" => 12,
    "fifteen" => 15,
    "twenty" => 20,
    "thirty" => 30,
    "forty" => 40,
    "fifty" => 50,
    "hundred" => 100
  }

  @coins %{
    "c" => 1,
    "copper" => 1,
    "coppers" => 1,
    "silver" => 10,
    "silvers" => 10,
    "gold" => 500
  }

  @number @words |> Map.keys() |> Enum.sort_by(&(-byte_size(&1))) |> Enum.join("|")
  @price ~r/\b(?:for|at)\s+(\d+|#{@number})\s*(coppers|copper|silvers|silver|gold|c)\b/i

  @doc "The named price in copper, or nil."
  @spec of(String.t() | nil) :: pos_integer() | nil
  def of(text) when is_binary(text) do
    case Regex.scan(@price, text) |> List.last() do
      [_, n, coin] -> amount(String.downcase(n)) * @coins[String.downcase(coin)]
      nil -> nil
    end
  end

  def of(_text), do: nil

  @doc """
  The price a buy or a sale is made at when the player names `named`, the
  trader's own price being `hers`: at once at the named price when it is at
  least as good for her (a sale to her at or below her price, a purchase
  from her at or above it), else `:counter`: her price stays an open offer
  the player can accept (`TalesForge.Game.Offer`). No named price is her price.

      iex> TalesForge.Game.NamedPrice.settle(:sell, 12, 15)
      {:at, 12}
      iex> TalesForge.Game.NamedPrice.settle(:sell, 20, 15)
      :counter
      iex> TalesForge.Game.NamedPrice.settle(:buy, 25, 20)
      {:at, 25}
      iex> TalesForge.Game.NamedPrice.settle(:buy, 15, 20)
      :counter
      iex> TalesForge.Game.NamedPrice.settle(:buy, nil, 20)
      {:at, 20}
  """
  @spec settle(:buy | :sell, pos_integer() | nil, integer()) :: {:at, integer()} | :counter
  def settle(_kind, nil, hers), do: {:at, hers}
  def settle(:sell, named, hers) when named <= hers, do: {:at, named}
  def settle(:buy, named, hers) when named >= hers, do: {:at, named}
  def settle(_kind, _named, _hers), do: :counter

  @doc ~s(`%{"named_price" => n}` for the words, or none: intent parameters.)
  @spec params(String.t() | nil) :: map()
  def params(text) do
    case of(text) do
      nil -> %{}
      price -> %{"named_price" => price}
    end
  end

  @doc """
  The trade at her price `trade` settled against the `named` price (`TalesForge.Game.NamedPrice.settle/3`):
  `{:trade, trade}` at the price it is made at, or `{:ok, offer}`, her price
  open for the player to accept. A counter-offer on a sale has the trader as
  its `receiver` (she buys from the player).
  """
  @spec deal(:buy | :sell, Trade.t(), pos_integer() | nil) ::
          {:trade, Trade.t()} | {:ok, Offer.t()}
  def deal(kind, %Trade{} = trade, named) do
    case settle(kind, named, trade.price) do
      {:at, price} ->
        {:trade, %{trade | price: price}}

      :counter ->
        receiver = if kind == :sell, do: trade.receiver

        {:ok,
         %Offer{giver: trade.giver, receiver: receiver, item: trade.item, price: trade.price}}
    end
  end

  defp amount(n), do: @words[n] || String.to_integer(n)
end
