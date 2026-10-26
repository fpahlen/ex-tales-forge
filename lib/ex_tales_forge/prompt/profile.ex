defmodule TalesForge.Prompt.Profile do
  @moduledoc """
  The single registry of prompt sections per call type (`TalesForge.Prompt`).

  For the narration calls (`:gm` and `:scene`) the cache order is:

    1. static: the narrator voice, the adventure rules, the task;
    2. session: the character sheet and the opening scene;
    3. turn: the per-turn state; for a GM turn also the server bounds, the
       validated player action and the handler result.

  The profile holds all the role and flag checks. A section only
  renders its data:

    * `TURN_OUTCOME_RECORD` adds the outcome record;
    * `NPC_DIALOGUE_MEMORY` adds the NPC dialogue memory;
    * `NPC_REACTIONS` or `WORLD_AGENTS` adds the NPC reactions;
    * `WORLD_AGENTS` adds the world facts and the prices;
    * `SKILL_DETAIL_LEVEL` adds the noticed details;
    * the production role gets the lean GM task (`gm_task_fragments/1`);
      its lean reply (no `location_name`) is the `:lean`
      variant of `TalesForge.LLM.gm_variant/1`.
  """

  alias TalesForge.Prompt.Ctx
  alias TalesForge.Prompt.Sections

  @doc "The static sections (system messages)."
  @spec static_sections(Ctx.t()) :: [module()]
  def static_sections(%Ctx{call: call}) when call in [:gm, :scene],
    do: [Sections.Narrator, Sections.Rules, Sections.Task]

  @doc "The session sections."
  @spec session_sections(Ctx.t()) :: [module()]
  def session_sections(%Ctx{call: call}) when call in [:gm, :scene],
    do: [Sections.CharacterSheet, Sections.Opening]

  @doc "The turn sections."
  @spec turn_sections(Ctx.t()) :: [module()]
  def turn_sections(%Ctx{call: :scene} = ctx), do: state_sections(ctx)
  def turn_sections(%Ctx{call: :gm} = ctx), do: state_sections(ctx) ++ [Sections.GmTurnAction]

  @doc "All sections for `ctx`, in cache order."
  @spec sections(Ctx.t()) :: [module()]
  def sections(ctx), do: static_sections(ctx) ++ session_sections(ctx) ++ turn_sections(ctx)

  @doc "The section ids for `ctx`, in prompt order."
  @spec ids(Ctx.t()) :: [atom()]
  def ids(ctx), do: Enum.map(sections(ctx), & &1.id())

  defp state_sections(ctx) do
    [
      Sections.PerceivedFacts,
      Sections.IntentContext,
      Sections.Characters,
      Sections.WorldFacts,
      Sections.Prices,
      Sections.CharacterReactions,
      Sections.DialogueMemory,
      Sections.CharacterMemory,
      Sections.Gestures,
      Sections.SceneNow,
      Sections.Surroundings,
      Sections.OutcomeRecord,
      Sections.NoticedDetails,
      Sections.Premise,
      Sections.SkillSplit,
      Sections.Combat,
      Sections.Fallen,
      Sections.RestGrowth,
      Sections.PlayerRequest,
      Sections.StateFacts
    ]
    |> Enum.filter(&include?(&1, ctx))
  end

  # The flags that turn a section on (any one of them); a section not listed
  # is always on.
  @flags %{
    Sections.WorldFacts => [:world_agents],
    Sections.Prices => [:world_agents],
    Sections.CharacterReactions => [:npc_reactions, :world_agents],
    Sections.DialogueMemory => [:npc_dialogue_memory],
    Sections.CharacterMemory => [:character_memory],
    Sections.OutcomeRecord => [:turn_outcome_record, :turn_apply_outcomes],
    Sections.NoticedDetails => [:skill_detail_level],
    Sections.SkillSplit => [:skill_split],
    Sections.Combat => [:combat_opposed],
    Sections.Surroundings => [:location_grid]
  }

  defp include?(section, ctx) do
    case Map.fetch(@flags, section) do
      {:ok, flags} -> Enum.any?(flags, &Ctx.flag?(ctx, &1))
      :error -> true
    end
  end
end
