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
  def lines(%__MODULE__{} = facts),
    do: ["Coins: " <> PlayPanel.format_coins(facts.coins), "Pack: " <> pack(facts.inventory)]

  defp pack([]), do: "empty"
  defp pack(items), do: Enum.map_join(items, ", ", &item/1)

  defp item(%{"name" => name, "quantity" => 1}), do: name
  defp item(%{"name" => name, "quantity" => n}), do: "#{name} (#{n})"
end
