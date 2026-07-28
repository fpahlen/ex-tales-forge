defmodule TalesForge.Game.ActionHandler do
  @moduledoc false

  # Core pure game logic. Ecto state only. No Ash.

  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}

  @stub_actions ~w(use_item)a
  @inventory_actions ~w(pickup drop buy sell trade spend)a

  def resolve(%PlayerAction{action: action} = _player_action) do
    skill = action.parameters |> Map.get("skill") |> Mechanics.normalize_skill_name()

    case action.action_type do
      t when t in @stub_actions ->
        %HandlerResult{
          handler: "freeform",
          skill: skill,
          target: action.target,
          notes: "Stub handler for #{t}; narrated as freeform."
        }

      t when t in @inventory_actions ->
        %HandlerResult{
          handler: "inventory",
          target: action.target,
          notes: "Inventory #{t}.",
          state_hints: %{
            "action_type" => Atom.to_string(t),
            "parameters" => action.parameters
          }
        }

      :move ->
        %HandlerResult{
          handler: "move",
          skill: skill,
          target: action.target,
          notes: "Move to #{action.target}.",
          state_hints: %{"location_id" => action.target}
        }

      :speak ->
        %HandlerResult{
          handler: "speak",
          skill: skill || "persuasion",
          target: action.target,
          notes: "Speak to #{action.target}."
        }

      t when t in [:observe, :interact, :combat, :other, :freeform] ->
        %HandlerResult{
          handler: "skill_check",
          skill: skill || "insight",
          target: action.target,
          notes: "Skill check for #{t}."
        }

      other ->
        %HandlerResult{
          handler: "freeform",
          skill: skill,
          target: action.target,
          notes: "Unhandled action_type #{other}; freeform."
        }
    end
  end
end
