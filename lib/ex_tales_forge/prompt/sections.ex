defmodule TalesForge.Prompt.Sections do
  @moduledoc """
  The sections of the narration prompts (GM turn and scene). Each module is
  one `TalesForge.Prompt.Section`; `TalesForge.Prompt.Profile` lists them
  per call type, in prompt order.
  """
end

defmodule TalesForge.Prompt.Sections.Narrator do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :narrator, slot: :static

  @impl true
  def render(ctx), do: TalesForge.Game.Prompts.narrator_system(ctx.variant)
end

defmodule TalesForge.Prompt.Sections.Rules do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :rules, slot: :static

  @impl true
  def render(ctx), do: ctx.data.rules
end

defmodule TalesForge.Prompt.Sections.Task do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :task, slot: :static

  @impl true
  def render(ctx),
    do:
      if(ctx.call == :scene,
        do: TalesForge.Game.Prompts.scene_system(ctx.variant),
        else: TalesForge.Game.Prompts.gm_system(ctx.variant, ctx.role)
      )
end

defmodule TalesForge.Prompt.Sections.CharacterSheet do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :character_sheet, slot: :session

  @impl true
  def render(ctx), do: TalesForge.Game.Context.character_sheet(ctx.data.world_state)
end

defmodule TalesForge.Prompt.Sections.Opening do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :opening, slot: :session

  @impl true
  def render(ctx),
    do:
      TalesForge.Game.Context.opening_section(
        Map.get(ctx.data, :opening_scene),
        ctx.data.world_state
      )
end

defmodule TalesForge.Prompt.Sections.PerceivedFacts do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :perceived_facts, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.Game.Context.perceived_facts_section(ctx.data)
end

defmodule TalesForge.Prompt.Sections.IntentContext do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :intent_context, slot: :turn

  @impl true
  def render(ctx), do: ctx.data.formatted_intent
end

defmodule TalesForge.Prompt.Sections.Npcs do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :npcs, slot: :turn

  @impl true
  def render(ctx),
    do:
      TalesForge.NPC.format_gm_sections(
        ctx.data.session_id,
        Map.get(ctx.data.intent_context, "present_npcs", [])
      )
end

defmodule TalesForge.Prompt.Sections.WorldFacts do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :world_facts, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.World.prompt_section(Map.get(ctx.data, :world_facts))
end

defmodule TalesForge.Prompt.Sections.Prices do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :prices, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.World.Prices.prompt_section(Map.get(ctx.data, :price_lines))
end

defmodule TalesForge.Prompt.Sections.NpcReactions do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :npc_reactions, slot: :turn

  @impl true
  def render(ctx),
    do: TalesForge.Game.NpcReactions.prompt_section(Map.get(ctx.data, :npc_reactions))
end

defmodule TalesForge.Prompt.Sections.NpcMemory do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :npc_memory, slot: :turn

  @impl true
  def render(ctx), do: Map.get(ctx.data, :npc_memory)
end

defmodule TalesForge.Prompt.Sections.Gestures do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :gestures, slot: :turn

  @impl true
  def render(ctx),
    do: TalesForge.Game.Gestures.prompt_section(Map.get(ctx.data, :recent_gestures))
end

defmodule TalesForge.Prompt.Sections.SceneNow do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :scene_now, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.Game.Context.scene_now_section(ctx.data)
end

defmodule TalesForge.Prompt.Sections.OutcomeRecord do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :outcome_record, slot: :turn

  @impl true
  def render(ctx),
    do: TalesForge.Game.OutcomeRecord.prompt_section(Map.get(ctx.data, :outcome_record))
end

defmodule TalesForge.Prompt.Sections.Premise do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :premise, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.Game.Context.premise_section(ctx.data)
end

defmodule TalesForge.Prompt.Sections.RestGrowth do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :rest_growth, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.Game.Context.rest_growth_section(ctx.data)
end

defmodule TalesForge.Prompt.Sections.PlayerRequest do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :player_request, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.Game.Context.player_request_section(ctx.data)
end

defmodule TalesForge.Prompt.Sections.GmTurnAction do
  @moduledoc false
  # The tail of a GM turn: the server bounds, the validated player action and
  # the handler result. It follows the turn sections with no separator.
  use TalesForge.Prompt.Section, id: :gm_turn_action, slot: :turn

  alias TalesForge.Game.Context
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}

  @impl true
  def glue, do: ""

  @impl true
  def render(%{data: data}) do
    Context.mechanical_bounds(data.mechanical) <>
      "\n\nValidated player action (turn #{data.turn_number}):\n" <>
      Jason.encode!(PlayerAction.encode(data.player_action), pretty: true) <>
      "\n\nAction handler result:\n" <>
      Jason.encode!(handler_payload(data.handler), pretty: true)
  end

  defp handler_payload(%HandlerResult{} = handler) do
    %{
      "handler" => handler.handler,
      "skill" => handler.skill,
      "target" => handler.target,
      "notes" => handler.notes
    }
  end
end
