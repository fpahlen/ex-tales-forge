defmodule TalesForge.CharacterCreation.Options.RaceOption do
  @moduledoc "One race a player can choose: description, stat modifiers, bonus choice and skill bonus."
  defstruct id: "", description: "", stats: %{}, choice: nil, skill_bonus: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          stats: map(),
          choice: map() | nil,
          skill_bonus: map()
        }
end
