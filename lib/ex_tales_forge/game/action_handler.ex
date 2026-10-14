defmodule TalesForge.Game.ActionHandler do
  @moduledoc false

  # Core pure game logic. Ecto state only.
  #
  # Roll rule (decision 2026-10-07, from Fredrik via Case): roll only when the
  # outcome is uncertain and failing matters. Speak, observe, interact, other
  # and freeform take the skill the intent step chose, and no skill means no
  # check. Combat always rolls (melee_combat unless named).

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

  defp resolve_type(%PlayerAction{} = player_action) do
    action = player_action.action
    skill = action.parameters |> Map.get("skill") |> Mechanics.normalize_skill_name()

    cond do
      action.action_type in @stub_actions ->
        %HandlerResult{
          handler: "freeform",
          skill: skill,
          target: action.target,
          notes: "Stub handler for #{action.action_type}; narrated as freeform."
        }

      action.action_type in @inventory_actions ->
        %HandlerResult{
          handler: "inventory",
          target: action.target,
          notes: "Inventory #{action.action_type}.",
          state_hints: %{
            "action_type" => Atom.to_string(action.action_type),
            "parameters" => action.parameters
          }
        }

      # Catalogue v2 (JEV_CATALOGUE_V2): no mechanics; the GM narrates the
      # attempt (turn pipeline design §5, rule 5).
      action.action_type == :none_fits ->
        %HandlerResult{
          handler: "narrate",
          target: action.target,
          notes:
            "No mechanics: the action fits no type. Narrate the attempt with no mechanical effect.",
          state_hints: %{"none_fits" => true}
        }

      action.action_type == :work ->
        ticks = wait_ticks(player_action)

        %HandlerResult{
          handler: "work",
          target: action.target,
          notes: "Work #{ticks} ticks for the unskilled wage.",
          state_hints: %{"ticks" => ticks}
        }

      action.action_type in [:equip, :give] ->
        %HandlerResult{
          handler: Atom.to_string(action.action_type),
          target: action.target,
          notes: "#{action.action_type} #{action.target}.",
          state_hints: %{}
        }

      action.action_type in [:wait, :rest] ->
        ticks = wait_ticks(player_action)

        %HandlerResult{
          handler: "wait",
          target: action.target,
          notes: "Wait #{ticks} ticks.",
          state_hints: %{"ticks" => ticks}
        }

      action.action_type == :train ->
        ticks = wait_ticks(player_action)

        %HandlerResult{
          handler: "train",
          target: action.target,
          notes: "Train #{ticks} ticks.",
          state_hints: %{"ticks" => ticks}
        }

      action.action_type == :move ->
        %HandlerResult{
          handler: "move",
          skill: skill,
          target: action.target,
          notes: "Move to #{action.target}.",
          state_hints: %{"location_id" => action.target}
        }

      action.action_type == :speak ->
        %HandlerResult{
          handler: "speak",
          skill: skill,
          target: action.target,
          notes: "Speak to #{action.target}."
        }

      action.action_type == :combat ->
        %HandlerResult{
          handler: "skill_check",
          skill: skill || "melee_combat",
          target: action.target,
          notes: "Skill check for combat."
        }

      action.action_type in [:observe, :interact, :other, :freeform] and is_binary(skill) ->
        %HandlerResult{
          handler: "skill_check",
          skill: skill,
          target: action.target,
          notes: "Skill check for #{action.action_type}."
        }

      action.action_type in [:observe, :interact, :other, :freeform] ->
        %HandlerResult{
          handler: "narrate",
          target: action.target,
          notes: "No check: ordinary #{action.action_type}, nothing uncertain at stake."
        }

      true ->
        %HandlerResult{
          handler: "freeform",
          skill: skill,
          target: action.target,
          notes: "Unhandled action_type #{action.action_type}; freeform."
        }
    end
  end

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

  def tick_delta(_), do: 1

  defp wait_ticks(%PlayerAction{} = player_action) do
    case player_action.action.parameters do
      %{"ticks" => ticks} -> WorldClock.clamp_wait(ticks)
      _ -> WorldClock.parse_duration(player_action.overall_intent || "")
    end
  end
end
