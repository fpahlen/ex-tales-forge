defmodule TalesForge.Locations.Target do
  @moduledoc """
  Which legend item on a grid a player's words mean ("the bar", "over to the
  fire"), by the item's name or one of its `aliases` (world-pack data in the
  legend, carried on each cell; docs/design-locations.md, step 2). Pure. The longest matching name wins,
  so "kitchen door" beats "kitchen"; only items that are on the grid count.
  """

  alias TalesForge.Locations.Cell
  alias TalesForge.Locations.Grid

  @articles ~w(the a an that this my his her its their)

  @doc """
  The item `words` name on `grid`, or `:unknown`.

      iex> {:ok, legend} = TalesForge.Locations.Legend.parse(%{"scale" => "room", "items" => %{
      ...>   "." => %{"item" => "floor"}, "=" => %{"item" => "bar desk", "aliases" => ["bar"]}}})
      iex> ascii = "=" <> String.duplicate(".", 19) <> "\\n" <> String.duplicate(String.duplicate(".", 20) <> "\\n", 19)
      iex> {:ok, grid} = TalesForge.Locations.Grid.parse(ascii, legend, %{id: "inn", z: 0})
      iex> TalesForge.Locations.Target.resolve(grid, "I walk over to the Bar.")
      {:ok, "bar desk"}
      iex> TalesForge.Locations.Target.resolve(grid, "the dragon")
      :unknown
  """
  @spec resolve(Grid.t(), String.t()) :: {:ok, String.t()} | :unknown
  def resolve(%Grid{} = grid, words) when is_binary(words) do
    text = " " <> normalize(words) <> " "

    grid
    |> names()
    |> Enum.filter(fn {name, _item} -> String.contains?(text, " " <> name <> " ") end)
    |> Enum.max_by(fn {name, _item} -> String.length(name) end, fn -> nil end)
    |> case do
      {_name, item} -> {:ok, item}
      nil -> :unknown
    end
  end

  # Every name of every item on the grid, as {name, item}.
  defp names(%Grid{cells: cells}) do
    for %Cell{item: item, aliases: aliases} <- Enum.uniq_by(Map.values(cells), & &1.char),
        name <- [item | aliases],
        do: {normalize(name), item}
  end

  defp normalize(words) do
    words
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split()
    |> Enum.reject(&(&1 in @articles))
    |> Enum.join(" ")
  end
end
