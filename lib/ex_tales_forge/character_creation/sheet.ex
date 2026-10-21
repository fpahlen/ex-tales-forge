defmodule TalesForge.CharacterCreation.Sheet do
  @moduledoc """
  The finished character for a draft that passed its checks, in the shape of
  a pack character file, as a pure function of a
  `TalesForge.CharacterCreation.Context`.
  """
  alias TalesForge.CharacterCreation.Context
  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.Mechanics

  @doc "The character map for the draft in `ctx`, with id `slug`."
  @spec build(Context.t(), String.t()) :: map()
  def build(%Context{draft: draft} = ctx, slug) do
    derived = derived(ctx, slug)

    %{
      "id" => slug,
      "name" => draft.name,
      "race" => draft.race,
      "class" => draft.class,
      "stats" => ctx.final_stats,
      "skills" => ctx.skill_levels,
      "learning_points" => %{},
      "learning_failures" => %{},
      "wounds" => 0,
      "wound_max" => Mechanics.wound_max(%{"stats" => ctx.final_stats}),
      "vitality" => "ok",
      "coins" => derived["coins"],
      "inventory" => ctx.rules["creation"]["starting_kit"],
      "ocean" => derived["ocean"],
      "maslow" => derived["maslow"],
      "concerns" => derived["concerns"],
      "creation" => creation_record(ctx)
    }
  end

  # The levers and coins, derived as for an NPC from the draft's labels.
  defp derived(%Context{draft: draft, rules: rules}, slug) do
    inputs = rules["creation"]["derive"]

    inputs
    |> Map.merge(%{"race" => draft.race, "class" => draft.class})
    |> Map.put("occupation", draft.occupation || inputs["occupation"])
    |> Defaults.derive(rules["labels"], Defaults.seed(draft.seed_key, slug))
  end

  # How the character was made.
  defp creation_record(%Context{draft: draft} = ctx) do
    %{
      "seed_key" => draft.seed_key,
      "model" => draft.model,
      "base_stats" => draft.base_stats,
      "race_picks" => draft.race_picks,
      "points_spent" => ctx.points_spent,
      "occupation" => draft.occupation,
      "skill_choices" => draft.skills,
      "skill_points_spent" => ctx.skill_points_spent,
      "derive" => Map.put(ctx.rules["creation"]["derive"], "occupation", draft.occupation)
    }
  end
end
