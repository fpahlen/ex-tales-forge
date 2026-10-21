defmodule TalesForge.GameCharacter.RulesCheck.Rule do
  @moduledoc """
  One rule check: every name in `names` must be in `known`, or `message`
  (a function of the unknown names, in order) is raised as an `ArgumentError`.
  """

  defstruct names: [], known: [], message: nil

  @type t :: %__MODULE__{
          names: [term()],
          known: Enumerable.t(),
          message: ([term()] -> String.t())
        }

  @doc "The names in `rule` that are not known, in order, duplicates kept."
  @spec unknown(t()) :: [term()]
  def unknown(%__MODULE__{names: names, known: known}),
    do: Enum.reject(names, &Enum.member?(known, &1))

  @doc "Raises `ArgumentError` with the rule's message if a name is unknown."
  @spec check!(t()) :: :ok
  def check!(%__MODULE__{message: message} = rule) do
    case unknown(rule) do
      [] -> :ok
      bad -> raise ArgumentError, message.(bad)
    end
  end
end
