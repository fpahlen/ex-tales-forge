defmodule TalesForge.CharacterCreation.Options do
  @moduledoc """
  What a player chooses from when creating a character.

  Built from the creation rules (`"labels"` and `"creation"`) by
  `from_rules/1`, and the rule lookups the draft functions share.
  """

  alias TalesForge.CharacterCreation.Options.{
    ClassOption,
    OccupationOption,
    RaceOption,
    SkillOption
  }

  alias TalesForge.Game.Mechanics

  defstruct races: [],
            classes: [],
            occupations: [],
            point_buy: %{},
            stat_roll: %{},
            skills: %{},
            skill_list: [],
            name_max_length: nil

  @type t :: %__MODULE__{
          races: [RaceOption.t()],
          classes: [ClassOption.t()],
          occupations: [OccupationOption.t()],
          point_buy: map(),
          stat_roll: map(),
          skills: map(),
          skill_list: [SkillOption.t()],
          name_max_length: pos_integer() | nil
        }

  @doc ~s(The options for creation rules `%{"labels" => _, "creation" => _}`.)
  @spec from_rules(map()) :: t()
  def from_rules(%{"labels" => labels, "creation" => creation}) do
    %__MODULE__{
      races: races(labels, creation),
      classes: classes(labels, creation),
      occupations: occupations(labels, creation),
      point_buy: creation["point_buy"],
      stat_roll: Map.delete(creation["stat_roll"], "_doc"),
      skills: Map.delete(creation["skills"], "_doc"),
      skill_list: skill_list(),
      name_max_length: creation["name_max_length"]
    }
  end

  defp races(labels, creation) do
    labels["races"]
    |> ordered("human")
    |> Enum.map(fn {id, race} ->
      %RaceOption{
        id: id,
        description: description(creation, "races", id),
        stats: race["stats"],
        choice: race_choice(creation, id),
        skill_bonus: race_bonus(creation, id)
      }
    end)
  end

  defp classes(labels, creation) do
    labels["classes"]
    |> ordered("none")
    |> Enum.map(fn {id, class} ->
      %ClassOption{
        id: id,
        description: description(creation, "classes", id),
        stats: class["stats"],
        skills: class_skills(class, creation),
        occupation: creation["occupation"]["class_defaults"][id]
      }
    end)
  end

  defp occupations(labels, creation) do
    Enum.map(creation["occupation"]["choices"], fn id ->
      %OccupationOption{
        id: id,
        description: description(creation, "occupations", id),
        skills: occupation_skills(labels["occupations"][id], creation)
      }
    end)
  end

  defp skill_list do
    Mechanics.skill_stat_map()
    |> Enum.sort()
    |> Enum.map(fn {id, stat} -> %SkillOption{id: id, stat: stat} end)
  end

  defp ordered(table, first), do: Enum.sort_by(table, fn {id, _} -> {id != first, id} end)

  # A label without a description (one a pack added) gets an empty one.
  defp description(creation, kind, id), do: get_in(creation, ["descriptions", kind, id]) || ""

  # --- rule lookups -------------------------------------------------------------------

  @doc "The stat bonus choice of `race` in creation.json, or nil."
  @spec race_choice(map(), String.t()) :: map() | nil
  def race_choice(creation, race), do: get_in(creation, ["race_choices", race])

  @doc "The skill bonus of `race` in creation.json (`%{}` when it has none)."
  @spec race_bonus(map(), String.t()) :: map()
  def race_bonus(creation, race), do: get_in(creation, ["skills", "race_bonuses", race]) || %{}

  @doc "The class package: every class skill, at the package's free levels in order."
  @spec class_skills(map(), map()) :: map()
  def class_skills(class, creation) do
    package = creation["skills"]["class_package"]

    class["skills"]
    |> Enum.with_index()
    |> Map.new(fn {skill, i} -> {skill, Enum.at(package, i)} end)
  end

  @doc "The past occupation's free levels: core skills, then secondary ones."
  @spec occupation_skills(map() | nil, map()) :: map()
  def occupation_skills(nil, _creation), do: %{}

  def occupation_skills(occupation, creation) do
    %{"core_bonus" => core, "secondary_bonus" => secondary} = creation["occupation"]

    occupation["secondary"]
    |> Map.new(&{&1, secondary})
    |> Map.merge(Map.new(occupation["core"], &{&1, core}))
  end
end
