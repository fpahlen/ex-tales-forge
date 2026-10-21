defmodule TalesForge.GameCharacter.Defaults.Picked do
  @moduledoc "The rules rows that resolved inputs pick: race, class, standing, occupation and seniority tier."
  alias TalesForge.GameCharacter.Defaults.Inputs

  defstruct race: %{}, class: %{}, standing: %{}, occupation: %{}, tier: 0

  @type t :: %__MODULE__{
          race: map(),
          class: map(),
          standing: map(),
          occupation: map(),
          tier: non_neg_integer()
        }

  @doc "The rows of `rules` for `inputs`."
  @spec from(Inputs.t(), map()) :: t()
  def from(%Inputs{} = inputs, rules) do
    %__MODULE__{
      race: rules["races"][inputs.race],
      class: rules["classes"][inputs.class],
      standing: rules["standings"][inputs.standing],
      occupation: rules["occupations"][inputs.occupation],
      tier: rules["seniority"][inputs.seniority]
    }
  end
end
