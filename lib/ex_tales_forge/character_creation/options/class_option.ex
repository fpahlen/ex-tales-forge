defmodule TalesForge.CharacterCreation.Options.ClassOption do
  @moduledoc "One class a player can choose: description, stat leanings, package skills and default past occupation."
  defstruct id: "", description: "", stats: %{}, skills: %{}, occupation: nil

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          stats: map(),
          skills: %{optional(String.t()) => non_neg_integer()},
          occupation: String.t() | nil
        }
end
