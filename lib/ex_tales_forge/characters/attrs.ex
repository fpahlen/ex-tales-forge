defmodule TalesForge.Characters.Attrs do
  @moduledoc """
  Column values of a `characters` row from game data: an inventory, a
  number map, concerns. A leaf of pure helpers, shared by
  `TalesForge.Characters` and the NPC store (`TalesForge.NPC.Person`,
  `TalesForge.NPC.Seed`).
  """

  alias TalesForge.Characters.Levers

  @doc """
  The `inventory` column of `items`. Old sheets can hold items without an
  id, or a quantity as a string; an item without a name is left out.

      iex> TalesForge.Characters.Attrs.inventory([%{"name" => "Rope Coil", "quantity" => "2"}, %{"id" => "x"}])
      [%{"id" => "rope_coil", "name" => "Rope Coil", "quantity" => 2, "price_copper" => nil,
         "copper_value" => nil, "equipped" => nil}]
  """
  @spec inventory(term()) :: [map()]
  def inventory(items) do
    items
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"name" => name} = item when is_binary(name) and name != "" -> [inventory_item(item, name)]
      _ -> []
    end)
  end

  defp inventory_item(item, name) do
    %{
      "id" => item["id"] || name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_"),
      "name" => name,
      "quantity" => int(item["quantity"], 1),
      "price_copper" => typed(item["price_copper"], &is_integer/1),
      "copper_value" => typed(item["copper_value"], &is_integer/1),
      "equipped" => typed(item["equipped"], &is_boolean/1)
    }
  end

  defp typed(value, type?), do: if(type?.(value), do: value)

  @doc "The concerns of `list` that have a text, at most the lever's maximum, each with a `since_tick`."
  @spec concerns(term(), integer()) :: [map()]
  def concerns(list, tick) do
    list
    |> List.wrap()
    |> Enum.filter(&(is_map(&1) and is_binary(&1["text"])))
    |> Enum.take(Levers.max_concerns())
    |> Enum.map(&Map.put_new(&1, "since_tick", tick))
  end

  @doc """
  The integer values of `map`, keys as strings (a float is truncated).

      iex> TalesForge.Characters.Attrs.int_map(%{brawling: 41.7, note: "x"})
      %{"brawling" => 41}
  """
  @spec int_map(term()) :: %{String.t() => integer()}
  def int_map(map) when is_map(map) do
    for {k, v} <- map, is_integer(v) or is_float(v), into: %{}, do: {to_string(k), trunc(v)}
  end

  def int_map(_), do: %{}

  @doc "`v` as an integer (a float truncated, a string parsed), else `default`."
  @spec int(term(), integer()) :: integer()
  def int(v, _default) when is_integer(v), do: v
  def int(v, _default) when is_float(v), do: trunc(v)

  def int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  def int(_, default), do: default
end
