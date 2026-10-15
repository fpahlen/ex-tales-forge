defmodule TalesForge.Game.IntentClarification do
  @moduledoc """
  The act / ask decision for a Jev intent reading, and the templated question
  shown when the game asks.

  A turn acts when the read is confident (`>= act_min`), asks only when it is
  unsure **and** the two most likely readings would play out differently, and
  otherwise plays its best guess. "Unsure" is the calibrated confidence below
  `ask_below`, **or** Jev's raw confidence below `ask_below_raw`: calibration
  lifts low raw reads a long way (raw 0.41 reads 0.82 calibrated), so on the
  calibrated value alone a raw read that low never asks. "Differently" means the top
  two action types fall in different consequence classes (talk is cheap to get
  wrong; a fight, a move, or spending coin is not), or, for a move or a fight,
  the target read itself is unsure, so the top two targets compete. At most one
  question per turn: the caller never asks again on the answer
  (`TalesForge.IntentJev`). See `docs/design-jev-intent.md` §4.

  The question payload keeps the shape of
  `TalesForge.Game.Intent.build_clarification/2`, so the LiveView and the
  persona bot read it unchanged; it adds `"source" => "jev"` and, per option,
  the typed actions that option plays (`"option_actions"`).
  """

  alias TalesForge.Game.JevIntent
  alias TalesForge.Game.Schemas.SingleAction

  @default_act_min 0.70
  @default_ask_below 0.45
  @default_ask_below_raw 0.45
  # Two move/fight targets compete when the runner-up is this close to the top.
  @target_margin 0.25

  # Getting the class wrong is what a wrong guess costs the player. Talk-like
  # actions are cheap; the others commit the character to something.
  @classes %{
    speak: :talk,
    observe: :talk,
    interact: :talk,
    use_item: :talk,
    freeform: :talk,
    other: :talk,
    move: :move,
    combat: :combat,
    buy: :coin,
    sell: :coin,
    trade: :coin,
    spend: :coin,
    pickup: :items,
    drop: :items,
    wait: :time,
    train: :time,
    rest: :time,
    work: :time,
    equip: :items,
    give: :items
  }

  @verbs %{
    observe: "look around",
    interact: "handle",
    use_item: "use",
    pickup: "pick up",
    drop: "drop",
    buy: "buy",
    sell: "sell",
    trade: "trade",
    spend: "pay",
    wait: "wait",
    train: "train",
    rest: "rest",
    work: "work",
    equip: "equip",
    give: "give something to",
    freeform: "do something else",
    other: "do something else"
  }

  @typedoc "The turn's decision for a reading: act on it, play a best guess, or ask."
  @type decision :: :act | :best_guess | :ask

  @doc """
  The default band thresholds: `[act_min: #{@default_act_min}, ask_below:
  #{@default_ask_below}, ask_below_raw: #{@default_ask_below_raw}]`.
  """
  @spec defaults() :: keyword(float())
  def defaults,
    do: [
      act_min: @default_act_min,
      ask_below: @default_ask_below,
      ask_below_raw: @default_ask_below_raw
    ]

  @doc "The consequence class of an action type."
  @spec class(atom()) :: atom()
  def class(action), do: Map.get(@classes, action, :talk)

  @doc """
  The decision for a `t:TalesForge.Game.JevIntent.reading/0`.

  `opts` may set `:act_min` (default #{@default_act_min}), `:ask_below`
  (default #{@default_ask_below}) and `:ask_below_raw` (default
  #{@default_ask_below_raw}; `0.0` turns the raw check off).

  The turn asks when the top two readings play out differently and either the
  calibrated confidence is below `ask_below` or the raw confidence
  (`reading.raw_confidence`, when present) is below `ask_below_raw`. The ask
  check comes first, so a low raw read whose calibrated value clears `act_min`
  still asks. Otherwise it acts at a calibrated confidence `>= act_min` and
  plays its best guess in between.
  """
  @spec band(JevIntent.reading() | map(), keyword()) :: decision()
  def band(reading, opts \\ []) do
    act_min = Keyword.get(opts, :act_min, @default_act_min)
    ask_below = Keyword.get(opts, :ask_below, @default_ask_below)
    ask_below_raw = Keyword.get(opts, :ask_below_raw, @default_ask_below_raw)
    confidence = reading.confidence || 1.0

    cond do
      unsure?(confidence, raw_confidence(reading), ask_below, ask_below_raw) and
          split_class?(reading) ->
        :ask

      confidence >= act_min ->
        :act

      true ->
        :best_guess
    end
  end

  defp unsure?(confidence, raw, ask_below, ask_below_raw) do
    confidence < ask_below or (is_number(raw) and raw < ask_below_raw)
  end

  defp raw_confidence(reading), do: Map.get(reading, :raw_confidence)

  # True when the top two readings would commit the character to different
  # kinds of consequence, or a move or fight whose target is itself unsure (so
  # a wrong guess is worth a question).
  defp split_class?(%{top2: [a, b | _]} = reading) when a != b do
    class(a) != class(b) or split_target?(reading)
  end

  defp split_class?(reading), do: split_target?(reading)

  defp split_target?(%{action: action} = reading) when action in [:move, :combat] do
    case target_ranking(reading) do
      [{_first, p1}, {_second, p2} | _] -> p2 > 0 and p1 - p2 < @target_margin
      _ -> false
    end
  end

  defp split_target?(_reading), do: false

  @doc """
  The clarification payload for a reading over `candidates`: a templated
  question offering the top two readings ("Do you want to talk to Brenna Holt,
  or go to Market Square?"), matching the shape
  `TalesForge.Game.Intent.build_clarification/2` returns, plus `"source"` and
  `"option_actions"` (each option's typed actions, primary first).

  With `v2: true` (`INTENT_CLARIFICATION_V2`) the options come from
  `options_v2/2`: only options that the game state allows, at most
  #{3}. The question stays one templated sentence; there is no LLM call.
  """
  @spec build(JevIntent.reading(), [JevIntent.candidate()], keyword()) :: map()
  def build(reading, candidates, opts \\ []) do
    id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    readings =
      if Keyword.get(opts, :v2, false),
        do: options_v2(reading, candidates),
        else: readings(reading, candidates)

    %{
      "clarification_id" => id,
      "source" => "jev",
      "question" =>
        "Do you want to #{Enum.map_join(readings, ", or ", &phrase(&1, candidates))}?",
      "options" =>
        readings
        |> Enum.with_index()
        |> Enum.map(fn {r, idx} ->
          %{
            "id" => "option_#{idx}",
            "label" => Atom.to_string(r.action_type),
            "description" => phrase(r, candidates),
            "action_index" => idx
          }
        end),
      "option_actions" =>
        Enum.map(readings, fn r -> Enum.map(option_actions(r, reading), &encode_action/1) end),
      "allow_free_text" => true,
      "overall_intent" => reading.extraction.overall_intent,
      "confidence" => reading.confidence,
      "raw_action" => reading.extraction.overall_intent,
      "actions" => Enum.map(reading.extraction.actions, &encode_action/1)
    }
  end

  # The two readings offered: the top action with its target, and either the
  # runner-up action (with the best target of a kind it can take) or, when
  # the actions agree and the target is what is unsure, the runner-up target.
  defp readings(reading, candidates) do
    [first_type | rest] = Enum.uniq(reading.top2 ++ [reading.action])
    primary = List.first(reading.extraction.actions)
    first = %SingleAction{primary | action_type: first_type}

    second =
      case {rest, target_ranking(reading)} do
        {[second_type | _], _} when second_type != first_type ->
          if class(second_type) == class(first_type) and split_target?(reading),
            do: runner_up_target(first, reading),
            else: %SingleAction{
              action_type: second_type,
              target: best_target_for(second_type, reading, candidates),
              parameters: %{}
            }

        _ ->
          runner_up_target(first, reading)
      end

    Enum.uniq_by([first, second], &{&1.action_type, &1.target})
  end

  @max_options 3
  @goods ~w(buy sell trade pickup drop equip give use_item)a

  @doc """
  Clarification v2: the options to offer for a reading, at most
  #{@max_options}, each one that the game state allows:

    * `buy` takes only an item for sale, never an item the character carries;
    * `sell`, `drop`, `equip`, `give` (an item) and `use_item` take only a
      carried item; `pickup` takes only an item on the ground;
    * a goods action never takes a person as its target;
    * `move` takes a place, `speak` and `combat` a person.

  An option with a target that the state does not allow gets the best allowed
  target from the ranking. When no allowed target exists, the option drops out.
  """
  @spec options_v2(JevIntent.reading(), [JevIntent.candidate()]) :: [SingleAction.t()]
  def options_v2(reading, candidates) do
    primary = List.first(reading.extraction.actions)
    types = Enum.uniq([primary.action_type | reading.top2 ++ [reading.action]])
    ranked = Enum.map(target_ranking(reading), &elem(&1, 0))

    types
    |> Enum.flat_map(&type_options(&1, primary, [primary.target | ranked], candidates))
    |> Enum.uniq_by(&{&1.action_type, &1.target})
    |> Enum.take(@max_options)
  end

  defp type_options(type, primary, targets, candidates) do
    keep = if type == primary.action_type, do: 2, else: 1

    targets
    |> Enum.uniq()
    |> Enum.filter(&allowed?(type, &1, candidates))
    |> Enum.take(keep)
    |> Enum.map(&option(type, &1, primary))
  end

  defp option(type, target, %{action_type: type, target: target} = primary), do: primary

  defp option(type, target, _primary),
    do: %SingleAction{action_type: type, target: target, parameters: %{}}

  @doc """
  True when the game state allows `type` on `target` (see `options_v2/2`).

      iex> c = [%{kind: :item, id: "bread", text: "Bread (carried)"}, %{kind: :npc, id: "brenna", text: "Brenna — innkeeper (present)"}]
      iex> TalesForge.Game.IntentClarification.allowed?(:buy, "bread", c)
      false
      iex> TalesForge.Game.IntentClarification.allowed?(:sell, "bread", c)
      true
      iex> TalesForge.Game.IntentClarification.allowed?(:buy, "brenna", c)
      false
  """
  @spec allowed?(atom(), String.t() | nil, [JevIntent.candidate()]) :: boolean()
  def allowed?(type, target, candidates) do
    found = Enum.filter(candidates, &(&1.id == target))
    item_status = fn status -> Enum.any?(found, &(&1.kind == :item and &1.text =~ status)) end
    person? = Enum.any?(found, &(&1.kind in [:npc, :npc_elsewhere]))

    case type do
      _ when type in @goods and person? and type != :give -> false
      :buy -> item_status.("(for sale)") and not item_status.("(carried)")
      t when t in [:sell, :drop, :equip, :use_item] -> item_status.("(carried)")
      :pickup -> item_status.("(on the ground)")
      :give -> Enum.any?(found, &(&1.kind == :npc))
      :move -> target == nil or Enum.any?(found, &(&1.kind in [:place, :npc_elsewhere]))
      t when t in [:speak, :combat] -> target == nil or person?
      _ -> target == nil or found != []
    end
  end

  defp runner_up_target(first, reading) do
    case target_ranking(reading) do
      [_top, {id, _p} | _] -> %SingleAction{first | target: id}
      _ -> %SingleAction{action_type: :other, target: nil, parameters: %{}}
    end
  end

  # The option's actions: the reading itself, plus the deferred action when
  # the option is the primary reading.
  defp option_actions(%SingleAction{} = r, reading) do
    case reading.extraction.actions do
      [primary | deferred]
      when primary.action_type == r.action_type and primary.target == r.target ->
        [r | deferred]

      _ ->
        [r]
    end
  end

  @doc """
  The target candidates by probability, highest first: `[{id | nil, p}]`
  (`nil` is "no target"). Empty when the reply carried no target question.
  """
  @spec target_ranking(map()) :: [{String.t() | nil, float()}]
  def target_ranking(%{target_ranking: ranking}) when is_list(ranking), do: ranking
  def target_ranking(_reading), do: []

  defp best_target_for(type, reading, candidates) do
    kinds =
      case type do
        :move -> [:place, :npc_elsewhere]
        t when t in [:speak, :combat] -> [:npc, :npc_elsewhere]
        t when t in [:buy, :sell, :pickup, :drop, :use_item, :trade] -> [:item]
        :interact -> [:fixture, :item]
        _ -> []
      end

    by_id = Map.new(candidates, &{&1.id, &1.kind})

    reading
    |> target_ranking()
    |> Enum.find_value(fn {id, _p} -> if Map.get(by_id, id) in kinds, do: id end)
  end

  defp phrase(%SingleAction{action_type: :move, target: t}, candidates),
    do: "go to #{target_text(t, candidates) || "somewhere else"}"

  defp phrase(%SingleAction{action_type: :combat, target: t}, candidates),
    do: "attack #{target_text(t, candidates) || "them"}"

  defp phrase(%SingleAction{action_type: :speak, target: t}, candidates),
    do: "talk to #{target_text(t, candidates) || "them"}"

  defp phrase(%SingleAction{action_type: type, target: t}, candidates) do
    case target_text(t, candidates) do
      nil -> @verbs[type] || Atom.to_string(type)
      text -> "#{@verbs[type] || Atom.to_string(type)} #{text}"
    end
  end

  defp target_text(nil, _candidates), do: nil

  defp target_text(id, candidates) do
    case Enum.find(candidates, &(&1.id == id)) do
      %{text: text} ->
        text |> String.split(" — ") |> List.first() |> String.split(" (") |> List.first()

      _ ->
        id
    end
  end

  @doc """
  The question for an attack with no clear target (#281 item 6, QA
  2026-10-14 21:15): "Whom do you attack?", one option for each person here
  (`people` is `[{id, name}]`). Each option attacks that person; the option
  action carries `"target_chosen"` so the combat step takes the target as
  chosen (`TalesForge.Game.Turn.Combat.target/4`).
  """
  @spec combat_target(map(), [{String.t(), String.t()}], String.t()) :: map()
  def combat_target(reading, people, raw_action) do
    id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    primary = List.first(reading.extraction.actions) || %SingleAction{action_type: :combat}
    params = primary.parameters || %{}

    options =
      Enum.map(people, fn {npc_id, _name} ->
        %SingleAction{
          action_type: :combat,
          target: npc_id,
          parameters: Map.put(params, "target_chosen", true)
        }
      end)

    %{
      "clarification_id" => id,
      "source" => "combat_target",
      "question" => "Whom do you attack? #{Enum.map_join(people, ", or ", &elem(&1, 1))}?",
      "options" =>
        people
        |> Enum.with_index()
        |> Enum.map(fn {{_npc_id, name}, idx} ->
          %{
            "id" => "option_#{idx}",
            "label" => "combat",
            "description" => "Attack #{name}",
            "action_index" => idx
          }
        end),
      "option_actions" => Enum.map(options, &[encode_action(&1)]),
      "allow_free_text" => true,
      "overall_intent" => reading.extraction.overall_intent,
      "confidence" => reading.confidence,
      "raw_action" => raw_action,
      "actions" => Enum.map(reading.extraction.actions, &encode_action/1)
    }
  end

  defp encode_action(action), do: SingleAction.encode(action)
end
