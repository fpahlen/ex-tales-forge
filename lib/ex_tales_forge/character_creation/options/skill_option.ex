defmodule TalesForge.CharacterCreation.Options.SkillOption do
  @moduledoc "One skill and its linked stat."
  defstruct id: "", stat: ""

  @type t :: %__MODULE__{id: String.t(), stat: String.t()}
end
