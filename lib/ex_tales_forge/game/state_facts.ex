defmodule TalesForge.Game.StateFacts do
  @moduledoc """
  The character's own state as plain facts for the GM (card 1): the coins and
  the pack, so a question such as "what does my pack contain?" is answered
  from the sheet. Pure; rendered by `TalesForge.Prompt.Sections.StateFacts`.

      iex> character = %{"coins" => %{"copper" => 12}, "inventory" => [%{"id" => "rope", "name" => "rope"}]}
      iex> TalesForge.Game.StateFacts.lines(TalesForge.Game.StateFacts.build(character))
      ["Coins: 0g 1s 2c", "Pack: rope"]
  """

  alias TalesForge.Game.{Inventory, PlayPanel}

  defstruct coins: %{}, inventory: []

  @type t :: %__MODULE__{coins: map(), inventory: [map()]}

  @doc "The facts of a world-state character map."
  @spec build(map()) :: t()
  def build(character) do
    %__MODULE__{
      coins: Map.get(character, "coins") || %{},
      inventory: Inventory.normalize_items(Map.get(character, "inventory") || [])
    }
  end

  @doc "One line per fact."
  @spec lines(t()) :: [String.t()]
  def lines(facts), do: ["Coins: " <> fact(facts, :coins), "Pack: " <> fact(facts, :pack)]

  @doc "One fact as text: the coins (`0g 1s 2c`) or the pack (`rope, torch (3)` or `empty`)."
  @spec fact(t(), :coins | :pack) :: String.t()
  def fact(%__MODULE__{coins: coins}, :coins), do: PlayPanel.format_coins(coins)
  def fact(%__MODULE__{inventory: []}, :pack), do: "empty"
  def fact(%__MODULE__{inventory: items}, :pack), do: Enum.map_join(items, ", ", &item/1)

  defp item(%{"name" => name, "quantity" => 1}), do: name
  defp item(%{"name" => name, "quantity" => n}), do: "#{name} (#{n})"
end
