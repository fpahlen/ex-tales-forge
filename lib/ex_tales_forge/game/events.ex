defmodule TalesForge.Game.Events do
  @moduledoc """
  Pure turn → event list. Triggers live on front and NPC definitions.

  Plain move onto a watched enter location is `player.failed_notice`
  unless the mechanical outcome is success with an unless_skill.

  A `"combat"` trigger fires when the player fights one of `target_in` (the
  action's target, or any of them present when the action names none):
  `event_on_success` or `event_on_failure` by the roll. A `"check"` trigger
  fires `event` when a check with a skill in `skill_in` on one of `target_in`
  succeeds.
  """

  alias TalesForge.Game.Mechanics

  defmodule Turn do
    @moduledoc """
    What `TalesForge.Game.Events.from_turn/1` reads: the player's action,
    its handler and mechanical resolution, the world before and after, and
    the fronts and people whose triggers can fire. `from_turn/1` adds the
    tick, the player's location before and after, the ticks that passed
    and the triggers.
    """

    @enforce_keys [:player_action, :handler, :mechanical, :world_before, :world_after]
    defstruct @enforce_keys ++
                [
                  fronts: [],
                  people: [],
                  tick: nil,
                  loc_before: nil,
                  loc_after: nil,
                  delta: 0,
                  triggers: []
                ]

    @type t :: %__MODULE__{
            player_action: map() | nil,
            handler: map() | nil,
            mechanical: map() | nil,
            world_before: map(),
            world_after: map(),
            fronts: [map()],
            people: [map()],
            tick: integer() | nil,
            loc_before: String.t() | nil,
            loc_after: String.t() | nil,
            delta: integer(),
            triggers: [map()]
          }
  end

  @doc "The events of `turn`, `time.passed` first."
  @spec from_turn(Turn.t()) :: [map()]
  def from_turn(%Turn{} = turn) do
    turn = derive(turn)

    [%{event(turn, "time.passed", %{"delta_ticks" => turn.delta}) | "actor" => "world"}]
    |> Kernel.++(travel_events(turn))
    |> Kernel.++(notice_events(turn))
    |> Kernel.++(dawdle_events(turn))
    |> Kernel.++(interact_events(turn))
    |> Kernel.++(combat_events(turn))
    |> Kernel.++(check_events(turn))
  end

  # The tick, where the player was and is, the ticks that passed and the
  # triggers of the fronts and people.
  defp derive(%Turn{world_before: before, world_after: later} = turn) do
    %{
      turn
      | tick: Map.get(later, "world_tick"),
        loc_before: character_loc(before),
        loc_after: character_loc(later),
        delta: Map.get(later, "world_tick", 0) - Map.get(before, "world_tick", 0),
        triggers: Enum.flat_map(turn.fronts ++ turn.people, &actor_triggers/1)
    }
  end

  defp combat_events(%Turn{player_action: action} = turn) do
    if action_type(action) == :combat do
      outcome = mechanical_outcome(turn.mechanical)

      turn.triggers
      |> Enum.filter(&(&1["on"] == "combat" and aimed_at?(&1, turn)))
      |> Enum.flat_map(&combat_event(turn, &1, outcome))
    else
      []
    end
  end

  defp combat_event(turn, trigger, outcome) do
    kind =
      if outcome in ~w(success critical_success),
        do: trigger["event_on_success"],
        else: trigger["event_on_failure"]

    if is_binary(kind),
      do: [event(turn, kind, %{"outcome" => outcome})],
      else: []
  end

  defp check_events(%Turn{mechanical: mechanical} = turn) do
    skill = mechanical_skill(mechanical)

    if mechanical_outcome(mechanical) == "success" and is_binary(skill) do
      turn.triggers
      |> Enum.filter(fn trigger ->
        trigger["on"] == "check" and skill in List.wrap(trigger["skill_in"]) and
          aimed_at?(trigger, turn)
      end)
      |> Enum.map(&event(turn, &1["event"], %{"skill" => skill}))
    else
      []
    end
  end

  # The action's target is one of the trigger's people, or the action names
  # nobody and one of them is present.
  defp aimed_at?(trigger, %Turn{player_action: action, world_after: world_after}) do
    targets = List.wrap(trigger["target_in"])
    present = List.wrap(world_after["present_npcs"])

    case action_target(action) do
      target when is_binary(target) -> target in targets and target in present
      _ -> Enum.any?(targets, &(&1 in present))
    end
  end

  defp travel_events(%Turn{loc_before: from, loc_after: to} = turn)
       when is_binary(from) and is_binary(to) and from != to do
    [event(turn, "player.travel", %{"from" => from, "to" => to})]
  end

  defp travel_events(_turn), do: []

  defp notice_events(turn) do
    turn.triggers
    |> Enum.filter(&enter_trigger?(&1, turn))
    |> Enum.map(&notice_event(turn, &1))
  end

  defp enter_trigger?(trigger, %Turn{loc_before: loc_before, loc_after: loc_after}) do
    trigger["on"] == "enter" and trigger["location_id"] == loc_after and loc_before != loc_after
  end

  defp notice_event(%Turn{handler: handler, mechanical: mechanical} = turn, trigger) do
    skill =
      Mechanics.normalize_skill_name(handler_skill(handler)) ||
        mechanical_skill(mechanical)

    unless_skills = List.wrap(trigger["unless_skill"])
    success? = mechanical_outcome(mechanical) == "success" and skill in unless_skills

    if success? do
      event(turn, trigger["event_on_notice"] || "player.noticed", %{})
    else
      %{event(turn, trigger["event"] || "player.failed_notice", %{}) | "player_aware" => false}
    end
  end

  defp dawdle_events(%Turn{loc_after: loc_after} = turn) do
    turn.triggers
    |> Enum.filter(&dawdle_trigger?(&1, loc_after))
    |> Enum.map(fn _ -> event(turn, "player.dawdled", %{"delta_ticks" => turn.delta}) end)
  end

  defp dawdle_trigger?(trigger, loc_after) do
    trigger["on"] == "time.passed" and loc_after in List.wrap(trigger["player_in"])
  end

  defp interact_events(%Turn{player_action: action, loc_after: loc_after} = turn) do
    target = action_target(action)

    if action_type(action) in [:interact, :other] do
      turn.triggers
      |> Enum.filter(&interact_trigger?(&1, loc_after, target))
      |> Enum.map(&interact_event(turn, &1))
    else
      []
    end
  end

  defp interact_trigger?(trigger, loc_after, target) do
    trigger["on"] == "interact" and
      is_binary(target) and
      (is_nil(trigger["location_id"]) or trigger["location_id"] == loc_after) and
      target in List.wrap(trigger["target_in"])
  end

  defp interact_event(turn, trigger) do
    %{
      event(turn, trigger["event"] || "npc.slighted", %{})
      | "actor" => trigger["actor_id"] || "npc",
        "player_aware" => Map.get(trigger, "player_aware", true)
    }
  end

  defp actor_triggers(%{definition: defn} = actor) do
    Enum.map(List.wrap(defn["triggers"]), &Map.put(&1, "actor_id", actor_id(actor)))
  end

  defp actor_triggers(%{"definition" => defn} = actor) do
    Enum.map(List.wrap(defn["triggers"]), &Map.put(&1, "actor_id", actor_id(actor)))
  end

  defp actor_triggers(_), do: []

  defp actor_id(%{npc_id: id}) when is_binary(id), do: id
  defp actor_id(%{front_id: id}) when is_binary(id), do: id
  defp actor_id(%{"npc_id" => id}) when is_binary(id), do: id
  defp actor_id(%{"front_id" => id}) when is_binary(id), do: id
  defp actor_id(_), do: nil

  defp action_type(%{action: %{action_type: type}}), do: type
  defp action_type(_), do: nil

  defp action_target(%{action: %{target: target}}), do: target
  defp action_target(_), do: nil

  # Every event happens at the turn's tick, where the player is after it.
  defp event(%Turn{tick: tick, loc_after: location_id}, kind, payload) do
    %{
      "kind" => kind,
      "actor" => "player",
      "player_aware" => true,
      "tick" => tick,
      "location_id" => location_id,
      "payload" => payload
    }
  end

  defp character_loc(world) when is_map(world) do
    get_in(world, ["character", "location_id"]) || world["location_id"]
  end

  defp character_loc(_), do: nil

  defp mechanical_outcome(%{outcome: outcome}), do: outcome
  defp mechanical_outcome(%{"outcome" => outcome}), do: outcome
  defp mechanical_outcome(_), do: "none"

  defp mechanical_skill(%{skill: skill}), do: Mechanics.normalize_skill_name(skill)
  defp mechanical_skill(%{"skill" => skill}), do: Mechanics.normalize_skill_name(skill)
  defp mechanical_skill(_), do: nil

  defp handler_skill(%{skill: skill}), do: skill
  defp handler_skill(_), do: nil
end
