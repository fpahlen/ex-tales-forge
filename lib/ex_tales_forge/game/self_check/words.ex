defmodule TalesForge.Game.SelfCheck.Words do
  @moduledoc """
  A self-check fact in words for the GM (`TalesForge.Game.SelfCheck`). The
  coins name a zero amount in words (`2 gold, 10 silver, no copper`, or
  `no coins`), not as `0c`: on playtest 6cb0391 the GM read `2g 10s 0c` as
  "a handful of copper" (h-qa16, h-qa19). The pack is the sheet's text
  (`TalesForge.Game.StateFacts.fact/2`).

      iex> facts = TalesForge.Game.StateFacts.build(%{"coins" => %{"gold" => 2, "silver" => 10}})
      iex> TalesForge.Game.SelfCheck.Words.fact(facts, :coins)
      "2 gold, 10 silver, no copper"
      iex> TalesForge.Game.SelfCheck.Words.fact(TalesForge.Game.StateFacts.build(%{}), :coins)
      "no coins"
  """

  alias TalesForge.Game.{Inventory, StateFacts}

  @doc "The fact `ask` of `facts` as text."
  @spec fact(StateFacts.t(), :coins | :pack) :: String.t()
  def fact(%StateFacts{coins: coins}, :coins), do: coins |> Inventory.normalize_coins() |> coins()
  def fact(facts, :pack), do: StateFacts.fact(facts, :pack)

  defp coins(%{"gold" => 0, "silver" => 0, "copper" => 0}), do: "no coins"

  defp coins(%{"gold" => gold, "silver" => silver, "copper" => copper}),
    do: Enum.map_join([gold: gold, silver: silver, copper: copper], ", ", &amount/1)

  defp amount({unit, 0}), do: "no #{unit}"
  defp amount({unit, n}), do: "#{n} #{unit}"
end
