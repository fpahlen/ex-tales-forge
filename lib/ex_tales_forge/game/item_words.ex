defmodule TalesForge.Game.ItemWords do
  @moduledoc """
  The item of a list that words name: by its id, its readable id
  ("ale_mug": "ale mug") or its name, either way round.

      iex> TalesForge.Game.ItemWords.resolve_item_id("my mug of ale", [%{"id" => "ale_mug", "name" => "Mug of Ale"}])
      "ale_mug"
      iex> TalesForge.Game.ItemWords.resolve_item_id("boots", [%{"id" => "ale_mug", "name" => "Mug of Ale"}])
      nil
  """

  @doc "The id of the item of `items` the words `hint` name, or nil."
  @spec resolve_item_id(String.t() | nil, [map()]) :: String.t() | nil
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
end
