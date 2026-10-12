defmodule TalesForge.Prompt.Profile do
  @moduledoc """
  The single registry of prompt sections per call type (`TalesForge.Prompt`).

  For the narration calls (`:gm` and `:scene`) the cache order is:

    1. static: the narrator voice, the adventure rules, the task;
    2. session: the character sheet and the opening scene;
    3. turn: the per-turn state; for a GM turn also the server bounds, the
       validated player action and the handler result.

  Each section decides on its own content today. The role, flag and baseline
  checks move here in later steps.
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
  def turn_sections(%Ctx{call: :scene}), do: state_sections()
  def turn_sections(%Ctx{call: :gm}), do: state_sections() ++ [Sections.GmTurnAction]

  @doc "All sections for `ctx`, in cache order."
  @spec sections(Ctx.t()) :: [module()]
  def sections(ctx), do: static_sections(ctx) ++ session_sections(ctx) ++ turn_sections(ctx)

  defp state_sections do
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
      Sections.Premise,
      Sections.RestGrowth,
      Sections.PlayerRequest
    ]
  end
end
