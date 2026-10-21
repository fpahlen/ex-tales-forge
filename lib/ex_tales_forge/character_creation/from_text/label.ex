defmodule TalesForge.CharacterCreation.FromText.Label do
  @moduledoc "One label read from a description: the value and the confidence (0 to 1)."
  defstruct value: "", confidence: 0.0

  @type t :: %__MODULE__{value: term(), confidence: float()}

  @doc "A reply's confidence as a float from 0 to 1 (0 when it is not a number)."
  @spec confidence(term()) :: float()
  def confidence(n) when is_number(n), do: n |> max(0.0) |> min(1.0) |> Kernel.*(1.0)
  def confidence(_), do: 0.0
end
