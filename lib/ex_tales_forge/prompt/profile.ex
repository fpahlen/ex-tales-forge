defmodule TalesForge.Prompt.Profile do
  @moduledoc """
  The single registry of prompt sections per call type (`TalesForge.Prompt`).

  For the narration calls (`:gm` and `:scene`) the cache order is:

    1. static: the narrator voice, the adventure rules, the task;
    2. session: the character sheet and the opening scene;
    3. turn: the per-turn state; for a GM turn also the server bounds, the
       validated player action and the handler result.

  The profile holds all the role, flag and baseline checks. A section only
  renders its data:

    * the baseline variant gets the baseline opening scene and no scene-now,
      premise or growth note;
    * `TURN_OUTCOME_RECORD` adds the outcome record;
    * `NPC_DIALOGUE_MEMORY` adds the NPC dialogue memory;
    * `NPC_REACTIONS` or `WORLD_AGENTS` adds the NPC reactions;
    * `WORLD_AGENTS` adds the world facts and the prices;
    * `SKILL_DETAIL_LEVEL` adds the noticed details;
    * the production role gets the lean GM task (`gm_task_fragments/1`) and
      the lean reply (`narration_fields/1`).
  """

  alias TalesForge.Prompt.Ctx
  alias TalesForge.Prompt.Sections

  # Sections of the default variant only (the baseline prompts stay as they were).
  @default_only [Sections.SceneNow, Sections.Premise, Sections.RestGrowth]

  @doc "The static sections (system messages)."
  @spec static_sections(Ctx.t()) :: [module()]
  def static_sections(%Ctx{call: call}) when call in [:gm, :scene],
    do: [Sections.Narrator, Sections.Rules, Sections.Task]

  @doc "The session sections."
  @spec session_sections(Ctx.t()) :: [module()]
  def session_sections(%Ctx{call: call} = ctx) when call in [:gm, :scene],
    do: [Sections.CharacterSheet, opening(ctx)]

  @doc "The turn sections."
  @spec turn_sections(Ctx.t()) :: [module()]
  def turn_sections(%Ctx{call: :scene} = ctx), do: state_sections(ctx)
  def turn_sections(%Ctx{call: :gm} = ctx), do: state_sections(ctx) ++ [Sections.GmTurnAction]

  @doc """
  The fragments of the GM task prompt (`priv/prompts/gm_system/`) for the app
  role. Production has a lean reply with no `gm_notes` and no
  `location_name`, so its prompt leaves out the fragments that ask for them.

      iex> TalesForge.Prompt.Profile.gm_task_fragments(%TalesForge.Prompt.Ctx{role: :production})
      ~w(head output)
      iex> TalesForge.Prompt.Profile.gm_task_fragments(%TalesForge.Prompt.Ctx{role: :playtest})
      ~w(head location_name output gm_notes)
  """
  @spec gm_task_fragments(Ctx.t()) :: [String.t()]
  def gm_task_fragments(%Ctx{role: :production}), do: ~w(head output)
  def gm_task_fragments(%Ctx{}), do: ~w(head location_name output gm_notes)

  @doc """
  The reply fields of a narration call for `ctx`, in schema order. The
  production GM call has no `location_name` and no `gm_notes`.

      iex> TalesForge.Prompt.Profile.narration_fields(%TalesForge.Prompt.Ctx{call: :gm, role: :production})
      ~w(narrative npc_memory_updates context_summary)
  """
  @spec narration_fields(Ctx.t()) :: [String.t()]
  def narration_fields(%Ctx{call: :gm, role: :production}),
    do: ~w(narrative npc_memory_updates context_summary)

  def narration_fields(%Ctx{}),
    do: ~w(narrative location_name npc_memory_updates context_summary gm_notes)

  @doc "All sections for `ctx`, in cache order."
  @spec sections(Ctx.t()) :: [module()]
  def sections(ctx), do: static_sections(ctx) ++ session_sections(ctx) ++ turn_sections(ctx)

  @doc "The section ids for `ctx`, in prompt order."
  @spec ids(Ctx.t()) :: [atom()]
  def ids(ctx), do: Enum.map(sections(ctx), & &1.id())

  defp opening(ctx),
    do: if(Ctx.baseline?(ctx), do: Sections.BaselineOpening, else: Sections.Opening)

  defp state_sections(ctx) do
    [
      Sections.PerceivedFacts,
      Sections.IntentContext,
      Sections.Npcs,
      Sections.WorldFacts,
      Sections.Prices,
      Sections.NpcReactions,
      Sections.NpcMemory,
      Sections.Gestures,
      Sections.SceneNow,
      Sections.OutcomeRecord,
      Sections.NoticedDetails,
      Sections.Premise,
      Sections.RestGrowth,
      Sections.PlayerRequest
    ]
    |> Enum.filter(&include?(&1, ctx))
  end

  defp include?(Sections.WorldFacts, ctx), do: Ctx.flag?(ctx, :world_agents)
  defp include?(Sections.Prices, ctx), do: Ctx.flag?(ctx, :world_agents)

  defp include?(Sections.NpcReactions, ctx),
    do: Ctx.flag?(ctx, :npc_reactions) or Ctx.flag?(ctx, :world_agents)

  defp include?(Sections.NpcMemory, ctx), do: Ctx.flag?(ctx, :npc_dialogue_memory)
  defp include?(Sections.OutcomeRecord, ctx), do: Ctx.flag?(ctx, :turn_outcome_record)
  defp include?(Sections.NoticedDetails, ctx), do: Ctx.flag?(ctx, :skill_detail_level)
  defp include?(section, ctx) when section in @default_only, do: not Ctx.baseline?(ctx)
  defp include?(_section, _ctx), do: true
end
