defmodule TalesForge.CharacterCreation.FromText.Known do
  @moduledoc "The ids a reading may use: races, classes, occupations and skills."
  alias TalesForge.CharacterCreation.Options

  defstruct races: [], classes: [], occupations: [], skills: MapSet.new()

  @type t :: %__MODULE__{
          races: [String.t()],
          classes: [String.t()],
          occupations: [String.t()],
          skills: MapSet.t(String.t())
        }

  @doc "The known ids in `options`."
  @spec from_options(Options.t()) :: t()
  def from_options(%Options{} = options) do
    %__MODULE__{
      races: Enum.map(options.races, & &1.id),
      classes: Enum.map(options.classes, & &1.id),
      occupations: Enum.map(options.occupations, & &1.id),
      skills: MapSet.new(options.skill_list, & &1.id)
    }
  end

  @doc "The known ids for a label field (`race`, `class` or `occupation`)."
  @spec ids(t(), String.t()) :: [String.t()]
  def ids(%__MODULE__{races: ids}, "race"), do: ids
  def ids(%__MODULE__{classes: ids}, "class"), do: ids
  def ids(%__MODULE__{occupations: ids}, "occupation"), do: ids
end
