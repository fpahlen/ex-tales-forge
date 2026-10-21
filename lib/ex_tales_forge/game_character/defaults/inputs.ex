defmodule TalesForge.GameCharacter.Defaults.Inputs do
  @moduledoc """
  The input labels a character's defaults are derived from. A label left out
  (or nil) takes its default.
  """

  defstruct race: "human",
            class: "none",
            standing: "commoner",
            occupation: "laborer",
            seniority: "journeyman"

  @type t :: %__MODULE__{
          race: String.t(),
          class: String.t(),
          standing: String.t(),
          occupation: String.t(),
          seniority: String.t()
        }

  # Each input with the rules table that must know it, in check order.
  @tables [
    race: "races",
    class: "classes",
    standing: "standings",
    occupation: "occupations",
    seniority: "seniority"
  ]

  @doc "The default labels, as the string-keyed map `Defaults.input_defaults/0` returns."
  @spec defaults() :: %{String.t() => String.t()}
  def defaults, do: Map.new(@tables, fn {key, _} -> {Atom.to_string(key), default(key)} end)

  defp default(key), do: Map.fetch!(%__MODULE__{}, key)

  @doc """
  The labels in `inputs` (string keys), defaults for the rest. Raises
  `ArgumentError` for a label the rules table does not know.
  """
  @spec resolve!(map(), map()) :: t()
  def resolve!(inputs, rules) when is_map(inputs) do
    resolved =
      Enum.reduce(@tables, %__MODULE__{}, fn {key, _table}, acc ->
        case inputs[Atom.to_string(key)] do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    Enum.each(@tables, fn {key, table} -> known!(rules[table], key, Map.fetch!(resolved, key)) end)

    resolved
  end

  defp known!(table, key, value) do
    unless Map.has_key?(table, value),
      do: raise(ArgumentError, "unknown #{key} #{inspect(value)}")
  end
end
