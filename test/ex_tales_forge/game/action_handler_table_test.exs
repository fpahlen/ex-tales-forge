defmodule TalesForge.Game.ActionHandlerTableTest do
  @moduledoc """
  Characterization of `TalesForge.Game.ActionHandler.resolve/1` and
  `TalesForge.Game.Schemas.SingleAction.decode/1`: every action type and the
  result main gave before the lookup-table refactor (round 2, PR 1). Pure, no
  LLM calls.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}

  @types ~w(observe interact speak move combat use_item pickup drop buy sell trade spend wait
            train freeform rest work equip give none_fits)

  test "decode maps every action type string to its atom" do
    for type <- @types do
      assert SingleAction.decode(%{"action_type" => type}).action_type == String.to_atom(type)
    end
  end

  test "decode lowercases, and an unknown or missing type is :other" do
    assert SingleAction.decode(%{"action_type" => "MOVE"}).action_type == :move
    assert SingleAction.decode(%{"action_type" => "dance"}).action_type == :other
    assert SingleAction.decode(%{"action_type" => :speak}).action_type == :speak
    assert SingleAction.decode(%{}).action_type == :other
  end

  @cases [
    {:observe, %{},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary observe, nothing uncertain at stake.",
       skill: nil
     }},
    {:observe, %{"skill" => "Persuasion"},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{},
       notes: "Skill check for observe.",
       skill: "persuasion"
     }},
    {:observe, %{"ticks" => 3},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary observe, nothing uncertain at stake.",
       skill: nil
     }},
    {:interact, %{},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary interact, nothing uncertain at stake.",
       skill: nil
     }},
    {:interact, %{"skill" => "Persuasion"},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{},
       notes: "Skill check for interact.",
       skill: "persuasion"
     }},
    {:interact, %{"ticks" => 3},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary interact, nothing uncertain at stake.",
       skill: nil
     }},
    {:speak, %{},
     %{handler: "speak", target: "tgt", state_hints: %{}, notes: "Speak to tgt.", skill: nil}},
    {:speak, %{"skill" => "Persuasion"},
     %{
       handler: "speak",
       target: "tgt",
       state_hints: %{},
       notes: "Speak to tgt.",
       skill: "persuasion"
     }},
    {:speak, %{"ticks" => 3},
     %{handler: "speak", target: "tgt", state_hints: %{}, notes: "Speak to tgt.", skill: nil}},
    {:move, %{},
     %{
       handler: "move",
       target: "tgt",
       state_hints: %{"location_id" => "tgt"},
       notes: "Move to tgt.",
       skill: nil
     }},
    {:move, %{"skill" => "Persuasion"},
     %{
       handler: "move",
       target: "tgt",
       state_hints: %{"location_id" => "tgt"},
       notes: "Move to tgt.",
       skill: "persuasion"
     }},
    {:move, %{"ticks" => 3},
     %{
       handler: "move",
       target: "tgt",
       state_hints: %{"location_id" => "tgt"},
       notes: "Move to tgt.",
       skill: nil
     }},
    {:combat, %{},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{},
       notes: "Skill check for combat.",
       skill: "melee_combat"
     }},
    {:combat, %{"skill" => "Persuasion"},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{},
       notes: "Skill check for combat.",
       skill: "persuasion"
     }},
    {:combat, %{"ticks" => 3},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{},
       notes: "Skill check for combat.",
       skill: "melee_combat"
     }},
    {:use_item, %{},
     %{
       handler: "freeform",
       target: "tgt",
       state_hints: %{},
       notes: "Stub handler for use_item; narrated as freeform.",
       skill: nil
     }},
    {:use_item, %{"skill" => "Persuasion"},
     %{
       handler: "freeform",
       target: "tgt",
       state_hints: %{},
       notes: "Stub handler for use_item; narrated as freeform.",
       skill: "persuasion"
     }},
    {:use_item, %{"ticks" => 3},
     %{
       handler: "freeform",
       target: "tgt",
       state_hints: %{},
       notes: "Stub handler for use_item; narrated as freeform.",
       skill: nil
     }},
    {:pickup, %{},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "pickup", "parameters" => %{}},
       notes: "Inventory pickup.",
       skill: nil
     }},
    {:pickup, %{"skill" => "Persuasion"},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "pickup", "parameters" => %{"skill" => "Persuasion"}},
       notes: "Inventory pickup.",
       skill: nil
     }},
    {:pickup, %{"ticks" => 3},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "pickup", "parameters" => %{"ticks" => 3}},
       notes: "Inventory pickup.",
       skill: nil
     }},
    {:drop, %{},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "drop", "parameters" => %{}},
       notes: "Inventory drop.",
       skill: nil
     }},
    {:drop, %{"skill" => "Persuasion"},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "drop", "parameters" => %{"skill" => "Persuasion"}},
       notes: "Inventory drop.",
       skill: nil
     }},
    {:drop, %{"ticks" => 3},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "drop", "parameters" => %{"ticks" => 3}},
       notes: "Inventory drop.",
       skill: nil
     }},
    {:buy, %{},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "buy", "parameters" => %{}},
       notes: "Inventory buy.",
       skill: nil
     }},
    {:buy, %{"skill" => "Persuasion"},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "buy", "parameters" => %{"skill" => "Persuasion"}},
       notes: "Inventory buy.",
       skill: nil
     }},
    {:buy, %{"ticks" => 3},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "buy", "parameters" => %{"ticks" => 3}},
       notes: "Inventory buy.",
       skill: nil
     }},
    {:sell, %{},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "sell", "parameters" => %{}},
       notes: "Inventory sell.",
       skill: nil
     }},
    {:sell, %{"skill" => "Persuasion"},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "sell", "parameters" => %{"skill" => "Persuasion"}},
       notes: "Inventory sell.",
       skill: nil
     }},
    {:sell, %{"ticks" => 3},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "sell", "parameters" => %{"ticks" => 3}},
       notes: "Inventory sell.",
       skill: nil
     }},
    {:trade, %{},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "trade", "parameters" => %{}},
       notes: "Inventory trade.",
       skill: nil
     }},
    {:trade, %{"skill" => "Persuasion"},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "trade", "parameters" => %{"skill" => "Persuasion"}},
       notes: "Inventory trade.",
       skill: nil
     }},
    {:trade, %{"ticks" => 3},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "trade", "parameters" => %{"ticks" => 3}},
       notes: "Inventory trade.",
       skill: nil
     }},
    {:spend, %{},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "spend", "parameters" => %{}},
       notes: "Inventory spend.",
       skill: nil
     }},
    {:spend, %{"skill" => "Persuasion"},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "spend", "parameters" => %{"skill" => "Persuasion"}},
       notes: "Inventory spend.",
       skill: nil
     }},
    {:spend, %{"ticks" => 3},
     %{
       handler: "inventory",
       target: "tgt",
       state_hints: %{"action_type" => "spend", "parameters" => %{"ticks" => 3}},
       notes: "Inventory spend.",
       skill: nil
     }},
    {:wait, %{},
     %{
       handler: "wait",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Wait 4 ticks.",
       skill: nil
     }},
    {:wait, %{"skill" => "Persuasion"},
     %{
       handler: "wait",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Wait 4 ticks.",
       skill: nil
     }},
    {:wait, %{"ticks" => 3},
     %{
       handler: "wait",
       target: "tgt",
       state_hints: %{"ticks" => 3},
       notes: "Wait 3 ticks.",
       skill: nil
     }},
    {:train, %{},
     %{
       handler: "train",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Train 4 ticks.",
       skill: nil
     }},
    {:train, %{"skill" => "Persuasion"},
     %{
       handler: "train",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Train 4 ticks.",
       skill: nil
     }},
    {:train, %{"ticks" => 3},
     %{
       handler: "train",
       target: "tgt",
       state_hints: %{"ticks" => 3},
       notes: "Train 3 ticks.",
       skill: nil
     }},
    {:freeform, %{},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary freeform, nothing uncertain at stake.",
       skill: nil
     }},
    {:freeform, %{"skill" => "Persuasion"},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{},
       notes: "Skill check for freeform.",
       skill: "persuasion"
     }},
    {:freeform, %{"ticks" => 3},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary freeform, nothing uncertain at stake.",
       skill: nil
     }},
    {:rest, %{},
     %{
       handler: "wait",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Wait 4 ticks.",
       skill: nil
     }},
    {:rest, %{"skill" => "Persuasion"},
     %{
       handler: "wait",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Wait 4 ticks.",
       skill: nil
     }},
    {:rest, %{"ticks" => 3},
     %{
       handler: "wait",
       target: "tgt",
       state_hints: %{"ticks" => 3},
       notes: "Wait 3 ticks.",
       skill: nil
     }},
    {:work, %{},
     %{
       handler: "work",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Work 4 ticks for the unskilled wage.",
       skill: nil
     }},
    {:work, %{"skill" => "Persuasion"},
     %{
       handler: "work",
       target: "tgt",
       state_hints: %{"ticks" => 4},
       notes: "Work 4 ticks for the unskilled wage.",
       skill: nil
     }},
    {:work, %{"ticks" => 3},
     %{
       handler: "work",
       target: "tgt",
       state_hints: %{"ticks" => 3},
       notes: "Work 3 ticks for the unskilled wage.",
       skill: nil
     }},
    {:equip, %{},
     %{handler: "equip", target: "tgt", state_hints: %{}, notes: "equip tgt.", skill: nil}},
    {:equip, %{"skill" => "Persuasion"},
     %{handler: "equip", target: "tgt", state_hints: %{}, notes: "equip tgt.", skill: nil}},
    {:equip, %{"ticks" => 3},
     %{handler: "equip", target: "tgt", state_hints: %{}, notes: "equip tgt.", skill: nil}},
    {:give, %{},
     %{handler: "give", target: "tgt", state_hints: %{}, notes: "give tgt.", skill: nil}},
    {:give, %{"skill" => "Persuasion"},
     %{handler: "give", target: "tgt", state_hints: %{}, notes: "give tgt.", skill: nil}},
    {:give, %{"ticks" => 3},
     %{handler: "give", target: "tgt", state_hints: %{}, notes: "give tgt.", skill: nil}},
    {:none_fits, %{},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{"none_fits" => true},
       notes:
         "No mechanics: the action fits no type. Narrate the attempt with no mechanical effect.",
       skill: nil
     }},
    {:none_fits, %{"skill" => "Persuasion"},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{"none_fits" => true},
       notes:
         "No mechanics: the action fits no type. Narrate the attempt with no mechanical effect.",
       skill: nil
     }},
    {:none_fits, %{"ticks" => 3},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{"none_fits" => true},
       notes:
         "No mechanics: the action fits no type. Narrate the attempt with no mechanical effect.",
       skill: nil
     }},
    {:other, %{},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary other, nothing uncertain at stake.",
       skill: nil
     }},
    {:other, %{"skill" => "Persuasion"},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{},
       notes: "Skill check for other.",
       skill: "persuasion"
     }},
    {:other, %{"ticks" => 3},
     %{
       handler: "narrate",
       target: "tgt",
       state_hints: %{},
       notes: "No check: ordinary other, nothing uncertain at stake.",
       skill: nil
     }},
    {:move, %{"no_move" => true},
     %{
       handler: "narrate",
       target: nil,
       state_hints: %{"no_action" => true},
       notes: "No move: the character stays where it is. Narrate no walk.",
       skill: nil
     }},
    {:wait, %{"manner" => "quickly", "ticks" => 4},
     %{
       handler: "wait",
       target: "tgt",
       state_hints: %{"manner" => "quickly", "roll_modifier" => -2, "ticks" => 2},
       notes: "Wait 4 ticks.",
       skill: nil
     }},
    {:observe, %{"manner" => "carefully", "skill" => "perception"},
     %{
       handler: "skill_check",
       target: "tgt",
       state_hints: %{"manner" => "carefully", "roll_modifier" => 2},
       notes: "Skill check for observe.",
       skill: "perception"
     }},
    {:unknown_thing, %{},
     %{
       handler: "freeform",
       target: "tgt",
       state_hints: %{},
       notes: "Unhandled action_type unknown_thing; freeform.",
       skill: nil
     }}
  ]

  test "resolve/1 gives the same result for every action type" do
    for {type, params, expected} <- @cases do
      action = %SingleAction{action_type: type, target: "tgt", parameters: params}

      result =
        ActionHandler.resolve(%PlayerAction{overall_intent: "wait an hour", action: action})

      assert Map.from_struct(result) == expected, "#{type} #{inspect(params)}"
    end
  end
end
