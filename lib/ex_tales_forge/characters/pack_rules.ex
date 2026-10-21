defmodule TalesForge.Characters.PackRules do
  @moduledoc """
  How a pack's `character_defaults.json` extends the base character rules:
  new labels only, more concern focuses, and `class_defaults`, the default
  past occupation of a class (one it adds, or a base class it overrides).
  """

  @tables ~w(seniority races classes standings occupations)

  @doc """
  `base` extended by one pack's `character_defaults.json` (`source` names it
  in errors). Raises `ArgumentError` on an unknown key or a redefined base
  label. A pack's `class_defaults` may also override a base class's default.
  """
  @spec extend!(map(), map(), String.t()) :: map()
  def extend!(base, pack, source), do: Enum.reduce(pack, base, &extend_key!(&2, &1, source))

  defp extend_key!(acc, {"_doc", _extra}, _source), do: acc

  defp extend_key!(acc, {"concern_focuses", extra}, _source),
    do: Map.update!(acc, "concern_focuses", &Enum.uniq(&1 ++ extra))

  defp extend_key!(acc, {"class_defaults", extra}, _source) when is_map(extra),
    do: Map.put(acc, "class_defaults", extra)

  defp extend_key!(acc, {table, extra}, source) when table in @tables and is_map(extra) do
    no_clash!(acc[table], {table, extra}, source)
    Map.update!(acc, table, &Map.merge(&1, extra))
  end

  defp extend_key!(_acc, {key, _extra}, source),
    do: raise(ArgumentError, "#{source}: unknown key #{inspect(key)}")

  defp no_clash!(base, {table, extra}, source) do
    case extra |> Map.keys() |> Enum.filter(&Map.has_key?(base, &1)) do
      [] -> :ok
      clash -> raise ArgumentError, "#{source}: cannot redefine base #{table} #{inspect(clash)}"
    end
  end

  @doc """
  `creation` (creation.json) with the pack's `class_defaults` from `labels`
  added to `occupation.class_defaults`; the pack's default wins.
  """
  @spec with_class_defaults(map(), map()) :: map()
  def with_class_defaults(creation, %{"class_defaults" => defaults}),
    do: update_in(creation, ["occupation", "class_defaults"], &Map.merge(&1, defaults))

  def with_class_defaults(creation, _labels), do: creation
end
