defmodule TalesForge.Game.ActionHandler do
  @moduledoc false

  # Core pure game logic. Ecto state only.
  #
  # Roll rule (decision 2026-10-07, from Fredrik via Case): roll only when the
  # outcome is uncertain and failing matters. Speak, observe, interact, other
  # and freeform take the skill the intent step chose, and no skill means no
  # check. Combat always rolls (melee_combat unless named).

  alias TalesForge.Game.ActionHandler.HandlerSpec
  alias TalesForge.Game.Catalogue
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Game.WorldClock

  @stub_actions ~w(use_item)a
  @inventory_actions ~w(pickup drop buy sell trade spend)a

  def resolve(%PlayerAction{} = player_action) do
    player_action
    |> resolve_type()
    |> put_manner(player_action.action.parameters["manner"])
  end

  # Catalogue v2: the manner adverb (PROVISIONAL table, TalesForge.Game.Catalogue)
  # scales the time of a timed action and changes the roll.
  defp put_manner(handler, manner) when manner in ~w(quickly carefully quietly) do
    mods = Catalogue.manner(manner, handler.handler)

    hints =
      handler.state_hints
      |> Map.merge(%{"manner" => manner, "roll_modifier" => mods.roll})
      |> scale_hint_ticks(mods)

    %{handler | state_hints: hints}
  end

  defp put_manner(handler, _manner), do: handler

  defp scale_hint_ticks(%{"ticks" => ticks} = hints, mods) when is_integer(ticks),
    do: Map.put(hints, "ticks", Catalogue.scale_ticks(ticks, mods))

  defp scale_hint_ticks(hints, _mods), do: hints

  # A move the intent step refused (`parameters["no_move"]`,
  # `TalesForge.Locations.NoMove`):
  # nothing happens, so the turn costs no game time (`tick_delta/1`).
  defp resolve_type(%PlayerAction{action: %{parameters: %{"no_move" => true}}}) do
    %HandlerResult{
      handler: "narrate",
      notes: "No move: the character stays where it is. Narrate no walk.",
      state_hints: %{"no_action" => true}
    }
  end

  @checks ~w(observe interact other freeform)a
  @stub %HandlerSpec{
    handler: "freeform",
    skill?: true,
    notes: "Stub handler for %type; narrated as freeform."
  }
  @inventory %HandlerSpec{handler: "inventory", notes: "Inventory %type.", hints: :inventory}

  @handlers Map.merge(
              Map.new(@stub_actions, &{&1, @stub}),
              Map.new(@inventory_actions, &{&1, @inventory})
            )
            |> Map.merge(%{
              none_fits: %HandlerSpec{
                handler: "narrate",
                notes:
                  "No mechanics: the action fits no type. Narrate the attempt with no mechanical effect.",
                hints: :none_fits
              },
              work: %HandlerSpec{
                handler: "work",
                notes: "Work %ticks ticks for the unskilled wage.",
                hints: :ticks
              },
              equip: %HandlerSpec{notes: "%type %target."},
              give: %HandlerSpec{notes: "%type %target."},
              wait: %HandlerSpec{handler: "wait", notes: "Wait %ticks ticks.", hints: :ticks},
              rest: %HandlerSpec{handler: "wait", notes: "Wait %ticks ticks.", hints: :ticks},
              train: %HandlerSpec{handler: "train", notes: "Train %ticks ticks.", hints: :ticks},
              move: %HandlerSpec{
                handler: "move",
                skill?: true,
                notes: "Move to %target.",
                hints: :location
              },
              speak: %HandlerSpec{handler: "speak", skill?: true, notes: "Speak to %target."},
              combat: %HandlerSpec{
                handler: "skill_check",
                skill?: true,
                notes: "Skill check for combat."
              }
            })
  @check %HandlerSpec{handler: "skill_check", skill?: true, notes: "Skill check for %type."}
  @ordinary %HandlerSpec{
    handler: "narrate",
    notes: "No check: ordinary %type, nothing uncertain at stake."
  }
  @unhandled %HandlerSpec{
    handler: "freeform",
    skill?: true,
    notes: "Unhandled action_type %type; freeform."
  }

  defp resolve_type(%PlayerAction{action: action} = player_action) do
    skill = action.parameters |> Map.get("skill") |> Mechanics.normalize_skill_name()
    spec = Map.get(@handlers, action.action_type) || check_spec(action.action_type, skill)
    build(spec, {player_action, skill})
  end

  defp check_spec(type, skill) when type in @checks and is_binary(skill), do: @check
  defp check_spec(type, _skill) when type in @checks, do: @ordinary
  defp check_spec(_type, _skill), do: @unhandled

  # Fills one table row in for the action. Combat rolls melee_combat unless a
  # skill is named.
  defp build(%HandlerSpec{} = spec, {%PlayerAction{action: action} = player_action, skill}) do
    ticks = if spec.hints == :ticks, do: wait_ticks(player_action)

    vars = %{
      "%type" => to_string(action.action_type),
      "%target" => to_string(action.target),
      "%ticks" => to_string(ticks)
    }

    skill = if action.action_type == :combat, do: skill || "melee_combat", else: skill

    %HandlerResult{
      handler: spec.handler || vars["%type"],
      skill: if(spec.skill?, do: skill),
      target: action.target,
      notes: String.replace(spec.notes, Map.keys(vars), &vars[&1]),
      state_hints: hints(spec.hints, action, ticks)
    }
  end

  defp hints(:none, _action, _ticks), do: %{}
  defp hints(:ticks, _action, ticks), do: %{"ticks" => ticks}
  defp hints(:none_fits, _action, _ticks), do: %{"none_fits" => true}
  defp hints(:location, action, _ticks), do: %{"location_id" => action.target}

  defp hints(:inventory, action, _ticks),
    do: %{"action_type" => Atom.to_string(action.action_type), "parameters" => action.parameters}

  # TURN_APPLY_OUTCOMES=on: a room payment that also plays the sleep
  # (TalesForge.Game.TurnApply.sleep_after_lodging/3).
  def tick_delta(%{state_hints: %{"sleep_ticks" => ticks}}), do: WorldClock.clamp_wait(ticks)

  def tick_delta(%{handler: handler, state_hints: %{"ticks" => ticks}})
      when handler in ["wait", "train", "work"] do
    WorldClock.clamp_wait(ticks)
  end

  # TURN_OUTCOME_RECORD=on or TURN_PREMISE_FIRST=on: a rejected action costs no game time (turn
  # pipeline design §11, decision 1).
  def tick_delta(%{state_hints: %{"rejected" => true}}), do: 0
  def tick_delta(%{state_hints: %{"no_action" => true}}), do: 0
  # A counter-offer on a price the player named: nothing moved (Case, 2026-10-22).
  def tick_delta(%{state_hints: %{"trade" => %{"status" => "counter"}}}), do: 0

  def tick_delta(_), do: 1

  defp wait_ticks(%PlayerAction{} = player_action) do
    case player_action.action.parameters do
      %{"ticks" => ticks} -> WorldClock.clamp_wait(ticks)
      _ -> WorldClock.parse_duration(player_action.overall_intent || "")
    end
  end
end
