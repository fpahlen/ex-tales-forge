defmodule TalesForge.GameCharacter.RulesCheck do
  @moduledoc """
  The one place the character rules are checked.

  `labels!/1` checks the label
  tables (`defaults.json` plus a pack's `character_defaults.json`);
  `creation!/2` checks `creation.json` against those labels. Each check is a
  `TalesForge.GameCharacter.RulesCheck.Rule`; the first one that fails raises
  `ArgumentError`.
  """

  alias TalesForge.Game.Mechanics
  alias TalesForge.GameCharacter.Levers
  alias TalesForge.GameCharacter.RulesCheck.Rule

  @stats ~w(STR DEX CON INT WIS CHA)

  @doc "The six stat names."
  @spec stats() :: [String.t()]
  def stats, do: @stats

  @doc "Checks the label tables. Returns `labels` or raises `ArgumentError`."
  @spec labels!(map()) :: map()
  def labels!(labels) do
    known = %{skills: skills(), focuses: MapSet.new(labels["concern_focuses"])}

    (Enum.flat_map(labels["occupations"], &occupation_rules(&1, known)) ++
       Enum.flat_map(labels["classes"], &class_rules(&1, known)) ++
       Enum.flat_map(labels["races"], &race_rules/1) ++
       Enum.flat_map(labels["standings"], &standing_rules(&1, known)))
    |> run!()

    labels
  end

  @doc "Checks `creation.json` against the label tables. Returns `:ok` or raises."
  @spec creation!(map(), map()) :: :ok
  def creation!(labels, creation) do
    (Enum.flat_map(creation["race_choices"], &race_choice_rules(&1, labels)) ++
       occupation_choice_rules(labels, creation["occupation"]) ++
       Enum.flat_map(creation["skills"]["race_bonuses"], &race_bonus_rules(&1, labels)))
    |> run!()
  end

  defp run!(rules), do: Enum.each(rules, &Rule.check!/1)

  defp skills, do: Mechanics.skill_stat_map() |> Map.keys() |> MapSet.new()

  # --- label tables ---------------------------------------------------------------

  defp occupation_rules({id, occ}, known) do
    where = "occupation #{id}"

    [
      skills_rule(occ["core"] ++ occ["secondary"], known.skills, where),
      traits_rule(occ["ocean"], where),
      maslow_rule(occ["maslow"], where)
    ] ++ Enum.map(occ["concerns"], &concern_rule(&1, known.focuses, where))
  end

  defp class_rules({id, class}, known) do
    where = "class #{id}"
    [skills_rule(class["skills"], known.skills, where), stats_rule(class["stats"], where)]
  end

  defp race_rules({id, race}) do
    where = "race #{id}"
    [stats_rule(race["stats"], where), traits_rule(race["ocean"], where)]
  end

  defp standing_rules({id, standing}, known) do
    where = "standing #{id}"
    floor = standing["maslow_floor"]
    concern = standing["concern"]

    if(floor, do: [maslow_rule(floor, where)], else: []) ++
      if concern, do: [concern_rule(concern, known.focuses, where)], else: []
  end

  defp skills_rule(list, known, where),
    do: %Rule{names: list, known: known, message: &defaults(where, "unknown skills", &1)}

  defp stats_rule(map, where),
    do: %Rule{names: Map.keys(map), known: @stats, message: &defaults(where, "unknown stats", &1)}

  defp traits_rule(map, where) do
    %Rule{
      names: Map.keys(map),
      known: Levers.ocean_traits(),
      message: &defaults(where, "unknown OCEAN traits", &1)
    }
  end

  defp maslow_rule(level, where) do
    %Rule{
      names: [level],
      known: Levers.maslow_levels(),
      message: fn [bad] -> defaults(where, "unknown Maslow level", bad) end
    }
  end

  defp concern_rule(%{"focus" => focus, "text" => text}, focuses, where) when is_binary(text) do
    %Rule{
      names: [focus],
      known: focuses,
      message: fn [bad] -> defaults(where, "unknown concern focus", bad) end
    }
  end

  defp concern_rule(concern, _focuses, where),
    do: %Rule{names: [concern], message: fn [bad] -> defaults(where, "bad concern", bad) end}

  defp defaults(where, what, bad), do: "character defaults #{where}: #{what} #{inspect(bad)}"

  # --- creation.json ----------------------------------------------------------------

  defp race_choice_rules({race, choice}, labels) do
    [
      %Rule{
        names: [race],
        known: Map.keys(labels["races"]),
        message: fn [bad] -> "creation.json: race_choices for unknown race #{inspect(bad)}" end
      },
      %Rule{
        names: choice["from"] ++ Map.keys(choice["replaces"]),
        known: @stats,
        message: &"creation.json: unknown stats #{inspect(&1)} for #{race}"
      }
    ]
  end

  defp occupation_choice_rules(labels, occupation) do
    [
      occupation_ids_rule(labels, occupation),
      class_default_rule(labels, occupation),
      default_coverage_rule(labels, occupation["class_defaults"])
    ]
  end

  defp occupation_ids_rule(labels, occupation) do
    %Rule{
      names: occupation["choices"] ++ Map.values(occupation["class_defaults"]),
      known: Map.keys(labels["occupations"]),
      message: fn [bad | _] -> "creation.json: unknown occupation #{inspect(bad)}" end
    }
  end

  defp class_default_rule(labels, occupation) do
    pairs = for c <- Map.keys(labels["classes"]), o <- occupation["choices"], do: {c, o}

    %Rule{
      names: Enum.to_list(occupation["class_defaults"]),
      known: MapSet.new(pairs),
      message: fn [{c, o} | _] -> "creation.json: bad class default #{c} => #{o}" end
    }
  end

  defp default_coverage_rule(labels, defaults) do
    %Rule{
      names: Map.keys(labels["classes"]),
      known: Map.keys(defaults),
      message: &"creation.json: no default occupation for #{inspect(&1)}"
    }
  end

  defp race_bonus_rules({race, bonus}, labels) do
    [
      %Rule{
        names: [race],
        known: Map.keys(labels["races"]),
        message: fn [bad] -> "creation.json: skill bonus for unknown race #{inspect(bad)}" end
      },
      %Rule{
        names: bonus |> Map.get("fixed", %{}) |> Map.keys(),
        known: skills(),
        message: &"creation.json: unknown skills #{inspect(&1)} for #{race}"
      }
    ]
  end
end
