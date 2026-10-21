defmodule TalesForge.CharacterCreation.FromText.Reading do
  @moduledoc "The labels (by field) and the follow-up questions from one reading."
  alias TalesForge.CharacterCreation.FromText.Label

  defstruct labels: %{}, questions: []

  @type t :: %__MODULE__{labels: %{optional(String.t()) => Label.t()}, questions: [String.t()]}
end
