defmodule TalesForge.CharacterCreation.Options.OccupationOption do
  @moduledoc "One past occupation a player can choose: description and free skill levels."
  defstruct id: "", description: "", skills: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          skills: %{optional(String.t()) => non_neg_integer()}
        }
end
