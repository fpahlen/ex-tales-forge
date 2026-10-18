defmodule TalesForge.Game.Schemas do
  @moduledoc """
  Game data structures for intent extraction and GM responses.
  """

  @type action_type ::
          :observe
          | :interact
          | :speak
          | :move
          | :combat
          | :use_item
          | :pickup
          | :drop
          | :buy
          | :sell
          | :trade
          | :spend
          | :wait
          | :train
          | :freeform
          | :rest
          | :work
          | :equip
          | :give
          | :none_fits
          | :other

  defmodule SingleAction do
    @moduledoc """
    One action the player wants to take: its type, target and parameters (e.g. `"item_id"`).
    """
    @type t :: %__MODULE__{}

    defstruct [:action_type, :target, parameters: %{}]

    @doc """
    Decodes one action from JSON (Tier 1 output or a stored job). JSON `null`
    counts as missing: Tier 1 sends `"parameters": null` for an action that
    needs no check, and `Map.get/3`'s default only covers a missing key, so a
    nil `parameters` once reached the action handler and crashed the turn job
    (playtest runs a76294d9, 0d1b8222 and 1a995c9f, 2026-10-08).

        iex> TalesForge.Game.Schemas.SingleAction.decode(%{"action_type" => "move", "target" => "market_square", "parameters" => nil})
        %TalesForge.Game.Schemas.SingleAction{action_type: :move, target: "market_square", parameters: %{}}
    """
    def decode(map) when is_map(map) do
      type =
        map
        |> Map.get("action_type")
        |> Kernel.||("other")
        |> to_string()
        |> String.downcase()
        |> action_type_atom()

      %__MODULE__{
        action_type: type,
        target: Map.get(map, "target"),
        parameters: map |> Map.get("parameters") |> parameters()
      }
    end

    def decode(_not_a_map), do: decode(%{})

    defp parameters(params) when is_map(params), do: params
    defp parameters(_null_or_other), do: %{}

    defp action_type_atom(type) do
      case type do
        "observe" -> :observe
        "interact" -> :interact
        "speak" -> :speak
        "move" -> :move
        "combat" -> :combat
        "use_item" -> :use_item
        "pickup" -> :pickup
        "drop" -> :drop
        "buy" -> :buy
        "sell" -> :sell
        "trade" -> :trade
        "spend" -> :spend
        "wait" -> :wait
        "train" -> :train
        "freeform" -> :freeform
        "rest" -> :rest
        "work" -> :work
        "equip" -> :equip
        "give" -> :give
        "none_fits" -> :none_fits
        _ -> :other
      end
    end

    def encode(%__MODULE__{} = action) do
      %{
        "action_type" => Atom.to_string(action.action_type),
        "target" => action.target,
        "parameters" => action.parameters
      }
    end
  end

  defmodule ClarificationOption do
    @moduledoc """
    One option offered to the player when the intent step asks a clarifying question.
    """
    @type t :: %__MODULE__{}

    defstruct [:id, :label, :description, action_index: 0]

    def decode(map) do
      %__MODULE__{
        id: Map.get(map, "id"),
        label: Map.get(map, "label"),
        description: Map.get(map, "description"),
        action_index: Map.get(map, "action_index", 0)
      }
    end
  end

  defmodule IntentExtraction do
    @moduledoc """
    The intent step's reading of the player's free text, before validation.
    """
    @type t :: %__MODULE__{}

    defstruct [
      :overall_intent,
      actions: [],
      primary_index: 0,
      confidence: 1.0,
      needs_clarification: false,
      clarification_question: nil,
      clarification_options: []
    ]

    # JSON null counts as missing (see `SingleAction.decode/1`).
    def decode(map) when is_map(map) do
      %__MODULE__{
        overall_intent: Map.get(map, "overall_intent") || "",
        actions: map |> Map.get("actions") |> list() |> Enum.map(&SingleAction.decode/1),
        primary_index: integer(Map.get(map, "primary_index"), 0),
        confidence: number(Map.get(map, "confidence"), 1.0),
        needs_clarification: Map.get(map, "needs_clarification") == true,
        clarification_question: Map.get(map, "clarification_question"),
        clarification_options: map |> Map.get("clarification_options") |> options()
      }
    end

    defp options(value),
      do: value |> list() |> Enum.filter(&is_map/1) |> Enum.map(&ClarificationOption.decode/1)

    defp list(value) when is_list(value), do: value
    defp list(_null_or_other), do: []

    defp integer(value, _default) when is_integer(value), do: value
    defp integer(_value, default), do: default

    defp number(value, _default) when is_number(value), do: value
    defp number(_value, default), do: default

    def encode(%__MODULE__{} = extraction) do
      %{
        "overall_intent" => extraction.overall_intent,
        "actions" => Enum.map(extraction.actions, &SingleAction.encode/1),
        "primary_index" => extraction.primary_index,
        "confidence" => extraction.confidence,
        "needs_clarification" => extraction.needs_clarification,
        "clarification_question" => extraction.clarification_question,
        "clarification_options" =>
          Enum.map(extraction.clarification_options, fn opt ->
            %{
              "id" => opt.id,
              "label" => opt.label,
              "description" => opt.description,
              "action_index" => opt.action_index
            }
          end)
      }
    end
  end

  defmodule PlayerAction do
    @moduledoc """
    The validated player action for a turn: overall intent, the primary `SingleAction`, confidence and any deferred actions.
    While a trade offer is open (`TalesForge.Game.Offer`), also the player's answer to it, as Jev read it:
    `offer_answer` (`:accept`, `:decline` or `:other`) and `offer_pick` (the index of the option picked).
    When the intent is unclear (`TalesForge.Game.Clarify`), `clarify` holds the question the GM voices
    in character (`"words"`, `"candidates"`, `"npc_id"`, `"npc"`), and nothing moves.
    """
    @type t :: %__MODULE__{}

    @offer_answers %{"accept" => :accept, "decline" => :decline, "other" => :other}

    defstruct [
      :overall_intent,
      :action,
      confidence: 1.0,
      deferred_actions: [],
      offer_answer: nil,
      offer_pick: nil,
      clarify: nil
    ]

    # JSON null counts as missing (see `SingleAction.decode/1`).
    def decode(map) when is_map(map) do
      %__MODULE__{
        overall_intent: Map.get(map, "overall_intent") || "",
        action: map |> Map.get("action") |> SingleAction.decode(),
        confidence: Map.get(map, "confidence") || 1.0,
        deferred_actions: map |> Map.get("deferred_actions") |> decode_actions(),
        offer_answer: Map.get(@offer_answers, Map.get(map, "offer_answer")),
        offer_pick: decode_pick(map["offer_pick"]),
        clarify: decode_clarify(map["clarify"])
      }
    end

    defp decode_actions(actions) when is_list(actions),
      do: Enum.map(actions, &SingleAction.decode/1)

    defp decode_actions(_null_or_other), do: []

    defp decode_pick(pick) when is_integer(pick), do: pick
    defp decode_pick(_pick), do: nil

    defp decode_clarify(%{} = clarify), do: clarify
    defp decode_clarify(_clarify), do: nil

    def encode(%__MODULE__{} = player_action) do
      %{
        "overall_intent" => player_action.overall_intent,
        "action" => SingleAction.encode(player_action.action),
        "confidence" => player_action.confidence,
        "deferred_actions" => Enum.map(player_action.deferred_actions, &SingleAction.encode/1)
      }
      |> put_answer(player_action)
      |> put_clarify(player_action.clarify)
    end

    # The question of an unclear turn, only when there is one.
    defp put_clarify(map, nil), do: map
    defp put_clarify(map, %{} = clarify), do: Map.put(map, "clarify", clarify)

    # The answer to an open offer, only when there is one (the GM prompt
    # and the job args are unchanged without).
    defp put_answer(map, %__MODULE__{offer_answer: nil, offer_pick: nil}), do: map

    defp put_answer(map, %__MODULE__{offer_answer: answer, offer_pick: pick}),
      do:
        Map.merge(map, %{"offer_answer" => answer && Atom.to_string(answer), "offer_pick" => pick})
  end

  defmodule MechanicalResolution do
    @moduledoc """
    The server's resolution of an action (skill, roll, outcome, state changes) that bounds what the GM may narrate.
    """
    @type t :: %__MODULE__{}

    defstruct skill: nil,
              outcome: "none",
              roll: nil,
              effective_skill: nil,
              lp_awarded: nil,
              notes: nil,
              improvements: [],
              training: nil,
              parts: nil,
              split: nil,
              combat: nil

    def decode(map) when is_map(map) do
      %__MODULE__{
        skill: Map.get(map, "skill"),
        outcome: Map.get(map, "outcome", "none"),
        roll: Map.get(map, "roll"),
        effective_skill: Map.get(map, "effective_skill"),
        lp_awarded: Map.get(map, "lp_awarded"),
        notes: Map.get(map, "notes"),
        improvements: Map.get(map, "improvements") || [],
        training: Map.get(map, "training"),
        parts: Map.get(map, "parts"),
        split: Map.get(map, "split"),
        combat: Map.get(map, "combat")
      }
    end

    def encode(%__MODULE__{} = res) do
      %{
        "skill" => res.skill,
        "outcome" => res.outcome,
        "roll" => res.roll,
        "effective_skill" => res.effective_skill,
        "lp_awarded" => res.lp_awarded,
        "notes" => res.notes,
        "improvements" => res.improvements || [],
        "training" => res.training,
        "parts" => res.parts,
        "split" => res.split,
        "combat" => res.combat
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end
  end

  defmodule GMStructuredResponse do
    @moduledoc """
    A decoded GM reply: the narrative plus bookkeeping (NPC memory updates, context summary), capped when parsed.
    """

    # Hard caps on the GM's bookkeeping, enforced here rather than with
    # maxLength / maxItems in the narration schema (those turn off xAI prompt
    # caching; see TalesForge.LLM.narration_schema/0). gm_system.txt asks for
    # less, so the caps only bite on a runaway reply.
    @context_summary_max_chars 300
    @npc_memory_max_items 3
    @npc_memory_max_chars 160

    def caps,
      do: %{
        context_summary: @context_summary_max_chars,
        npc_memory_items: @npc_memory_max_items,
        npc_memory_summary: @npc_memory_max_chars
      }

    @type t :: %__MODULE__{}

    defstruct [
      :narrative,
      mechanical_resolution: %MechanicalResolution{},
      npc_memory_updates: [],
      context_summary: nil,
      raw: %{}
    ]

    def decode(map) when is_map(map) do
      %__MODULE__{
        narrative: Map.get(map, "narrative", ""),
        mechanical_resolution:
          map
          |> Map.get("mechanical_resolution", %{})
          |> MechanicalResolution.decode(),
        npc_memory_updates: memories(Map.get(map, "npc_memory_updates")),
        context_summary: cap(Map.get(map, "context_summary"), @context_summary_max_chars),
        raw: map
      }
    end

    defp memories(list) when is_list(list) do
      list
      |> Enum.take(@npc_memory_max_items)
      |> Enum.map(fn
        %{"summary" => summary} = m -> %{m | "summary" => cap(summary, @npc_memory_max_chars)}
        other -> other
      end)
    end

    defp memories(_), do: []

    defp cap(text, max) when is_binary(text), do: String.slice(text, 0, max)
    defp cap(other, _max), do: other
  end

  defmodule HandlerResult do
    @moduledoc """
    Which action handler took the action, with its skill, target, notes and hints for the state update.
    """
    @type t :: %__MODULE__{}

    defstruct [:handler, :skill, :target, notes: "", state_hints: %{}]
  end
end
