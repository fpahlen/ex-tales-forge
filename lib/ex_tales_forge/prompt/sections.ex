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
    do: TalesForge.Game.Context.opening_section(Map.get(ctx.data, :opening_scene), :default)
end

defmodule TalesForge.Prompt.Sections.BaselineOpening do
  @moduledoc false
  # The opening scene text of the baseline variant.
  use TalesForge.Prompt.Section, id: :opening, slot: :session

  @impl true
  def render(ctx),
    do: TalesForge.Game.Context.opening_section(Map.get(ctx.data, :opening_scene), :baseline)
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
  @moduledoc """
  The facts of the world agents for this turn (`TalesForge.World`).

      iex> TalesForge.Prompt.Sections.WorldFacts.text([])
      nil
  """
  use TalesForge.Prompt.Section, id: :world_facts, slot: :turn

  @impl true
  def render(ctx), do: text(Map.get(ctx.data, :world_facts))

  @doc "The section for the collected agents, within the budget, or nil."
  @spec text([TalesForge.World.agent()] | nil) :: String.t() | nil
  def text(nil), do: nil

  def text(agents) do
    case TalesForge.World.prompt_lines(agents) do
      [] -> nil
      lines -> Enum.join(["## World facts (true in this world; keep to them)" | lines], "\n")
    end
  end
end

defmodule TalesForge.Prompt.Sections.Prices do
  @moduledoc """
  The server prices for this turn (`TalesForge.World.Prices`).

      iex> TalesForge.Prompt.Sections.Prices.text([])
      nil
  """
  use TalesForge.Prompt.Section, id: :prices, slot: :turn

  @impl true
  def render(ctx), do: text(Map.get(ctx.data, :price_lines))

  @doc "The section for the price lines, or nil."
  @spec text([String.t()] | nil) :: String.t() | nil
  def text(nil), do: nil
  def text([]), do: nil

  def text(lines),
    do:
      Enum.join(
        [
          "## Prices this turn (from the server; use these exact amounts)"
          | Enum.map(lines, &("- " <> &1))
        ],
        "\n"
      )
end

defmodule TalesForge.Prompt.Sections.NpcReactions do
  @moduledoc """
  The NPC reactions of this turn (`TalesForge.Game.NpcReactions`). One short
  typed line per NPC, e.g. `- Brenna Holt — wary (0.7), stance cool, confidence 0.8`.

      iex> TalesForge.Prompt.Sections.NpcReactions.text([])
      nil
  """
  use TalesForge.Prompt.Section, id: :npc_reactions, slot: :turn

  @impl true
  def render(ctx), do: text(Map.get(ctx.data, :npc_reactions))

  @doc "The section for the reactions, or nil."
  @spec text([map()] | nil) :: String.t() | nil
  def text(nil), do: nil
  def text([]), do: nil

  def text(reactions) do
    lines =
      Enum.map_join(reactions, "\n", fn r ->
        "- #{r["name"]} — #{r["emotion"]} (#{fmt(r["intensity"])}), stance #{r["stance"]}, confidence #{fmt(r["confidence"])}"
      end)

    "## NPC reactions (this moment)\n" <> lines
  end

  defp fmt(nil), do: "?"
  defp fmt(x) when is_float(x), do: :erlang.float_to_binary(Float.round(x, 1), decimals: 1)
  defp fmt(x), do: to_string(x)
end

defmodule TalesForge.Prompt.Sections.NpcMemory do
  @moduledoc """
  The memory of the present NPCs (`TalesForge.Game.NpcMemory`): the last
  lines each NPC spoke.
  """
  use TalesForge.Prompt.Section, id: :npc_memory, slot: :turn

  alias TalesForge.Game.NpcMemory

  @impl true
  def render(%{data: data}) do
    text(
      get_in(data, [:world_state, "npc_memory"]),
      NpcMemory.present_npcs(Map.get(data, :intent_context))
    )
  end

  @doc "The section for the memory of `npcs`, or nil when it is empty."
  @spec text(map() | nil, [NpcMemory.npc()]) :: String.t() | nil
  def text(memory, npcs) do
    blocks =
      npcs
      |> Enum.map(fn npc -> {npc, Map.get(memory || %{}, npc.id, [])} end)
      |> Enum.reject(fn {_npc, lines} -> lines == [] end)
      |> Enum.map(fn {npc, lines} ->
        "#{hd(npc.names)}:\n" <> Enum.map_join(lines, "\n", &"- \"#{&1}\"")
      end)

    if blocks != [],
      do:
        "## NPC dialogue memory (the last lines each NPC spoke; do not repeat these lines)\n" <>
          Enum.join(blocks, "\n")
  end
end

defmodule TalesForge.Prompt.Sections.Gestures do
  @moduledoc """
  The gestures the GM used in recent turns (`TalesForge.Game.Gestures`).

      iex> TalesForge.Prompt.Sections.Gestures.text([])
      nil
  """
  use TalesForge.Prompt.Section, id: :gestures, slot: :turn

  @impl true
  def render(ctx), do: text(Map.get(ctx.data, :recent_gestures))

  @doc "The section listing spent gestures, or nil when there are none."
  @spec text([TalesForge.Game.Gestures.t()] | nil) :: String.t() | nil
  def text(nil), do: nil
  def text([]), do: nil

  def text(gestures) do
    lines = Enum.map_join(gestures, "\n", &"- #{&1.phrase}")

    "## Gestures already used (recent turns)\n" <>
      lines <>
      "\nThese are spent: do not use them again, nor the same motion with the same body part or prop."
  end
end

defmodule TalesForge.Prompt.Sections.SceneNow do
  @moduledoc false
  use TalesForge.Prompt.Section, id: :scene_now, slot: :turn

  @impl true
  def render(ctx), do: TalesForge.Game.Context.scene_now_section(ctx.data)
end

defmodule TalesForge.Prompt.Sections.OutcomeRecord do
  @moduledoc """
  The outcome record of the turn (`TalesForge.Game.OutcomeRecord`). The GM
  narrates each accepted and each rejected action, and states no coin or item
  change that the record does not contain.

      iex> TalesForge.Prompt.Sections.OutcomeRecord.text(nil)
      nil
  """
  use TalesForge.Prompt.Section, id: :outcome_record, slot: :turn

  alias TalesForge.Game.OutcomeRecord

  @impl true
  def render(ctx), do: text(Map.get(ctx.data, :outcome_record))

  @doc "The section for the record, or nil when there is no record."
  @spec text(OutcomeRecord.t() | nil) :: String.t() | nil
  def text(nil), do: nil

  def text(record) do
    """
    ## Outcome record (booked by the server)
    The server booked this turn. #{OutcomeRecord.rejection_template()} State no coin amount, item gain or item loss that this record does not contain. Use this location and this time.
    #{Enum.map_join(OutcomeRecord.prompt_lines(record), "\n", &("- " <> &1))}
    """
  end
end

defmodule TalesForge.Prompt.Sections.Premise do
  @moduledoc """
  The claims in the player's words that the session state contradicts
  (`data[:premise_findings]`, from `TalesForge.Game.PremiseCheck`), with a
  short correction each.

      iex> TalesForge.Prompt.Sections.Premise.text([])
      nil
  """
  use TalesForge.Prompt.Section, id: :premise, slot: :turn

  @impl true
  def render(ctx), do: text(Map.get(ctx.data, :premise_findings))

  @doc "The GM note for `findings`, or nil when there are none."
  @spec text([TalesForge.Game.PremiseCheck.finding()] | nil) :: String.t() | nil
  def text(nil), do: nil
  def text([]), do: nil

  def text(findings) do
    lines = Enum.map_join(findings, "\n", &("- " <> &1.correction))

    """
    ## Player claims the state doesn't back
    The server owns the inventory, the coins and what has happened. These claims in the player's words are not true in this session. The character may believe or say them, but the world doesn't change: don't narrate them as true, don't let anyone accept them, and play the action from what is actually there.
    #{lines}
    """
  end
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
