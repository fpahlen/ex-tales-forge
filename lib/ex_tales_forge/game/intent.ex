defmodule TalesForge.Game.Intent do
  @moduledoc false

  require Logger

  alias TalesForge.Config
  alias TalesForge.Game.Context
  alias TalesForge.Game.Inventory
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Schemas.{IntentExtraction, PlayerAction, SingleAction}
  alias TalesForge.LLM

  @skill_required ~w(observe speak interact combat use_item)a
  @move_hints ~r/\b(go|head|walk|travel|move|enter|leave|step|run|proceed)\b/i

  @action_type_patterns [
    {~r/\b(attack|fight|strike|stab|shoot|punch)\b/i, :combat},
    {~r/\b(say|ask|tell|speak|shout|whisper|greet)\b/i, :speak},
    {~r/\b(buy|purchase)\b/i, :buy},
    {~r/\bpay\b.+\bfor\b/i, :buy},
    {~r/\b(pay|tip|bribe|toll)\b/i, :spend},
    {~r/\b(sell)\b/i, :sell},
    {~r/\b(trade|swap|barter)\b/i, :trade},
    {~r/\b(drop|discard)\b/i, :drop},
    {~r/\b(pick up|pickup|take|grab)\b/i, :pickup},
    {~r/\b(look|examine|study|read|search|inspect|listen)\b/i, :observe},
    {~r/\b(use|drink|eat|open)\b/i, :use_item}
  ]

  defmodule ClarificationNeeded do
    defexception [:extraction]

    @impl true
    def exception(opts) do
      %__MODULE__{extraction: Keyword.fetch!(opts, :extraction)}
    end

    @impl true
    def message(%__MODULE__{}), do: "player clarification required"
  end

  def extract_intent(raw_action, context) when is_binary(raw_action) do
    {bundle, _source} = resolve_bundle(raw_action, context)

    if should_clarify?(bundle) do
      raise ClarificationNeeded, extraction: bundle
    end

    validate_player_action(bundle, context)
  end

  def needs_clarification?(%IntentExtraction{} = extraction), do: should_clarify?(extraction)

  def resolve_bundle(raw_action, context) when is_binary(raw_action) do
    case LLM.provider() do
      "mock" ->
        {heuristic_intent(raw_action, context), :heuristic}

      _ ->
        resolve_bundle_live(raw_action, context)
    end
  end

  defp resolve_bundle_live(raw_action, context) do
    heuristic = heuristic_intent(raw_action, context)

    if heuristic_sufficient?(heuristic, context) do
      {heuristic, :heuristic}
    else
      tier1_or_heuristic(raw_action, context, heuristic)
    end
  end

  defp tier1_or_heuristic(raw_action, context, heuristic) do
    case call_tier1(raw_action, context) do
      {:ok, extraction} ->
        {extraction, :llm}

      {:error, reason} ->
        Logger.warning("tier1 intent failed reason=#{inspect(reason)}; using heuristic")
        {heuristic, :heuristic}
    end
  end

  def validate_player_action(%IntentExtraction{} = extraction, _context) do
    primary = primary_action(extraction)

    if skill_missing?(primary) do
      raise ArgumentError, "primary action missing required skill"
    end

    deferred =
      extraction.actions
      |> Enum.with_index()
      |> Enum.reject(fn {_action, idx} -> idx == extraction.primary_index end)
      |> Enum.map(fn {action, _idx} -> action end)

    %PlayerAction{
      overall_intent: sanitize_summary(extraction.overall_intent),
      action: primary,
      confidence: extraction.confidence,
      deferred_actions: deferred
    }
  end

  def build_clarification(extraction, raw_action) do
    id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    %{
      "clarification_id" => id,
      "question" => extraction.clarification_question || "What do you want to do?",
      "options" =>
        Enum.map(extraction.clarification_options, fn opt ->
          %{
            "id" => opt.id,
            "label" => opt.label,
            "description" => opt.description,
            "action_index" => opt.action_index
          }
        end),
      "allow_free_text" => true,
      "overall_intent" => extraction.overall_intent,
      "confidence" => extraction.confidence,
      "raw_action" => raw_action,
      "actions" => Enum.map(extraction.actions, &TalesForge.Game.Schemas.SingleAction.encode/1)
    }
  end

  defp call_tier1(raw_action, context) do
    system = TalesForge.Game.Prompts.intent_system()

    # Use centralized builder (prompt construction is no longer scattered).
    user = TalesForge.Game.Prompts.build_intent_user(context, raw_action)

    case LLM.complete_intent(system, user) do
      {:ok, extraction} ->
        {:ok, ensure_skill(extraction, raw_action)}

      error ->
        error
    end
  end

  defp heuristic_sufficient?(%IntentExtraction{} = extraction, context) do
    primary = primary_action(extraction)

    extraction.confidence >= Config.tier1_heuristic_threshold() and
      length(extraction.actions) == 1 and
      not extraction.needs_clarification and
      not ambiguous_move?(primary, context) and
      not skill_missing?(primary)
  end

  defp ambiguous_move?(%SingleAction{action_type: :move, target: target}, context) do
    is_nil(target) or target == "" or target not in context["exits"]
  end

  defp ambiguous_move?(_, _), do: false

  defp ensure_skill(%IntentExtraction{} = extraction, raw_action) do
    primary = primary_action(extraction)

    if skill_missing?(primary) do
      case Mechanics.infer_skill_from_action(raw_action) do
        nil -> extraction
        skill -> patch_skill(extraction, primary, skill)
      end
    else
      extraction
    end
  end

  defp patch_skill(%IntentExtraction{} = extraction, %SingleAction{} = primary, skill) do
    patched = %SingleAction{
      primary
      | parameters: Map.put(primary.parameters || %{}, "skill", skill)
    }

    %{
      extraction
      | actions: List.replace_at(extraction.actions, extraction.primary_index, patched)
    }
  end

  def heuristic_intent(raw_action, context) do
    action = build_heuristic_action(raw_action, context)

    %IntentExtraction{
      overall_intent: sanitize_summary(raw_action),
      actions: [action],
      primary_index: 0,
      confidence: 0.9,
      needs_clarification: false
    }
  end

  defp build_heuristic_action(raw_action, context) do
    target_location = infer_target_location(raw_action, context)
    target_npc = infer_target_npc(raw_action, context)
    action_type = infer_action_type(raw_action, target_location)
    skill = Mechanics.infer_skill_from_action(raw_action)

    parameters =
      %{}
      |> maybe_put_skill(skill, action_type)
      |> Map.merge(infer_inventory_parameters(raw_action, action_type, context, target_npc))

    {target, action_parameters} =
      inventory_target(action_type, target_location, target_npc, parameters)

    %SingleAction{
      action_type: action_type,
      target: target,
      parameters: action_parameters
    }
  end

  defp primary_action(%IntentExtraction{actions: actions, primary_index: index}) do
    Enum.at(actions, index) || List.first(actions)
  end

  defp should_clarify?(%IntentExtraction{} = extraction) do
    extraction.needs_clarification or
      extraction.confidence < Config.tier1_confidence_threshold() or
      (length(extraction.actions) > 1 and extraction.confidence < 0.85)
  end

  defp skill_missing?(%SingleAction{action_type: type, parameters: params}) do
    type in @skill_required and is_nil(Mechanics.normalize_skill_name(Map.get(params, "skill")))
  end

  defp infer_action_type(raw_action, target_location) do
    if target_location do
      :move
    else
      lowered = String.downcase(raw_action)
      find_action_type(lowered)
    end
  end

  defp find_action_type(lowered) do
    Enum.find_value(@action_type_patterns, :other, fn {regex, type} ->
      if Regex.match?(regex, lowered), do: type
    end)
  end

  defp infer_target_location(raw_action, context) do
    if Regex.match?(@move_hints, raw_action) do
      raw_action
      |> String.downcase()
      |> find_matching_exit(context)
    end
  end

  defp find_matching_exit(lowered, context) do
    Enum.find_value(context["exits"], &exit_mentioned_in_action?(lowered, &1, context))
  end

  defp exit_mentioned_in_action?(lowered, exit_id, context) do
    readable = String.replace(exit_id, "_", " ")
    name = Map.get(context["exit_names"], exit_id, exit_id)

    if String.contains?(lowered, exit_id) or String.contains?(lowered, readable) or
         String.contains?(lowered, String.downcase(name)) do
      exit_id
    end
  end

  defp infer_target_npc(raw_action, context) do
    lowered = String.downcase(raw_action)

    Enum.find_value(Context.present_npcs(context), fn npc_id ->
      readable = String.replace(npc_id, "_", " ")
      detail = Map.get(context["npc_details"] || %{}, npc_id, %{})
      display = Map.get(detail, "name", "")

      first_name = display |> String.split() |> List.first() |> downcase_or_empty()

      String.contains?(lowered, npc_id) or
        String.contains?(lowered, readable) or
        (display != "" and String.contains?(lowered, String.downcase(display))) or
        (first_name != "" and String.contains?(lowered, first_name))
    end)
  end

  defp downcase_or_empty(nil), do: ""
  defp downcase_or_empty(name), do: String.downcase(name)

  defp maybe_put_skill(params, skill, action_type) do
    if skill && action_type != :move do
      Map.put(params, "skill", skill)
    else
      params
    end
  end

  defp inventory_target(type, _target_location, target_npc, parameters)
       when type in [:drop, :pickup] do
    {Map.get(parameters, "item_id") || target_npc, parameters}
  end

  defp inventory_target(:buy, _target_location, target_npc, parameters) do
    {Map.get(parameters, "npc_id") || target_npc, parameters}
  end

  defp inventory_target(type, _target_location, target_npc, parameters)
       when type in [:sell, :spend] do
    {target_npc, parameters}
  end

  defp inventory_target(_type, target_location, target_npc, parameters) do
    {target_location || target_npc, parameters}
  end

  defp infer_inventory_parameters(raw_action, :spend, _context, _target_npc) do
    %{"amount_copper" => Inventory.parse_copper_hint(raw_action)}
  end

  defp infer_inventory_parameters(raw_action, :drop, context, _target_npc) do
    item_id = match_item_in_text(raw_action, context["player_inventory"] || [])
    base = if(item_id, do: %{"item_id" => item_id}, else: %{})
    Map.put(base, "quantity", 1)
  end

  defp infer_inventory_parameters(raw_action, :pickup, context, _target_npc) do
    item_id = match_item_in_text(raw_action, context["ground_items"] || [])
    base = if(item_id, do: %{"item_id" => item_id}, else: %{})
    Map.put(base, "quantity", 1)
  end

  defp infer_inventory_parameters(raw_action, :buy, context, target_npc) do
    stock =
      context
      |> Map.get("npc_stock", %{})
      |> stock_for_npc(target_npc)

    item_id = match_item_in_text(raw_action, stock)

    params =
      case Enum.find(stock, &(&1["id"] == item_id)) do
        %{"price_copper" => price} when is_integer(price) -> %{"price_copper" => price}
        _ -> %{}
      end

    params
    |> maybe_put("item_id", item_id)
    |> maybe_put("npc_id", target_npc)
    |> Map.put("quantity", 1)
  end

  defp infer_inventory_parameters(raw_action, :sell, context, target_npc) do
    item_id = match_item_in_text(raw_action, context["player_inventory"] || [])

    %{}
    |> maybe_put("item_id", item_id)
    |> maybe_put("npc_id", target_npc)
    |> Map.put("quantity", 1)
  end

  defp infer_inventory_parameters(_raw_action, _action_type, _context, _target_npc) do
    %{}
  end

  defp stock_for_npc(_npc_stock, nil), do: []
  defp stock_for_npc(npc_stock, npc_id), do: Map.get(npc_stock, npc_id, [])

  defp match_item_in_text(raw_action, items) do
    Inventory.resolve_item_id(raw_action, Inventory.normalize_items(items))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp sanitize_summary(text) do
    text
    |> String.trim()
    |> String.replace(~r/(?i)ignore\s+(all\s+)?(previous|prior)\s+instructions/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.slice(0, 500)
    |> case do
      "" -> raise ArgumentError, "empty action after sanitization"
      cleaned -> cleaned
    end
  end
end
