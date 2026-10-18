defmodule TalesForge.Game.RollRulesTest do
  @moduledoc """
  Roll rule (decision 2026-10-07, from Fredrik via Case): no skill roll on
  ordinary talk; roll only when the outcome is uncertain and failing matters.
  A failed read means learning nothing extra, never a colder NPC.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{ActionHandler, Context, Intent, Mechanics, NpcReactions, Prompts}
  alias TalesForge.Game.Schemas.{IntentExtraction, MechanicalResolution, SingleAction}
  alias TalesForge.GameSessions

  doctest Mechanics, only: [infer_check_skill: 1, untrained_floor: 1]

  defp session do
    {:ok, session} = GameSessions.create_session(%{name: "Rolls", adventure_id: "tin_valley"})

    session
  end

  # The resolution a turn would get: intent heuristic → handler → server roll.
  defp resolve(session, text) do
    context = Context.build_intent_context(session)
    action = text |> Intent.heuristic_intent(context) |> Intent.validate_player_action(context)
    handler = ActionHandler.resolve(action)
    character = session.world_state["character"]
    {_character, rolled} = Mechanics.apply_server_mechanics(character, action, handler)
    {action, handler, rolled}
  end

  @ordinary [
    "A tankard of your finest ale and a seat by the fire, if you please.",
    "I ask Brenna what the miners talk about these days",
    "Good evening! Quite the crowd tonight.",
    "I look around the common room",
    "I sit down and eat my stew"
  ]

  test "ordinary talk and everyday actions get no roll" do
    session = session()

    for text <- @ordinary do
      {_action, handler, rolled} = resolve(session, text)
      assert handler.skill == nil, "#{text} got skill #{inspect(handler.skill)}"
      assert %MechanicalResolution{outcome: "none", roll: nil} = rolled
    end
  end

  test "uncertain actions with stakes still roll the matching skill" do
    session = session()

    for {text, skill} <- [
          {"I try to convince Brenna to knock a copper off the room", "persuasion"},
          {"I search the loose floorboard by the hearth", "insight"},
          {"I lie and say the Guild sent me", "deception"},
          {"I sneak past the miners to the back door", "stealth"},
          {"I attack the guild man", "melee_combat"}
        ] do
      {_action, handler, rolled} = resolve(session, text)
      assert handler.skill == skill, text
      assert rolled.skill == skill
      assert is_integer(rolled.roll)
    end
  end

  test "\"scale\" as a noun is no climb (Paul to Rusk, run 3f7777a6, turn 7)" do
    session = session()

    paul =
      "Rusk, my good fellow, a toll upon a wandering preacher who seeks only to lighten burdens " <>
        "and serve stew to honest folk? Surely the road's own shadows weigh heavy enough without " <>
        "adding silver to the scale. Come, share a bowl and a tale instead."

    {_action, handler, rolled} = resolve(session, paul)
    refute handler.skill == "climbing"
    refute rolled.skill == "climbing"

    for text <- ["I scale the wall behind the stable", "I start climbing the cliff path"] do
      {_action, handler, _rolled} = resolve(session, text)
      assert handler.skill == "climbing", "#{text} got skill #{inspect(handler.skill)}"
    end
  end

  test "a Tier 1 action without a skill is valid and means no check" do
    extraction = %IntentExtraction{
      overall_intent: "greet the innkeeper",
      actions: [%SingleAction{action_type: :speak, target: "innkeep", parameters: %{}}],
      primary_index: 0,
      confidence: 0.95
    }

    action = Intent.validate_player_action(extraction, %{})
    assert %{handler: "speak", skill: nil} = ActionHandler.resolve(action)
  end

  test "combat without a named skill rolls melee, observe without one only narrates" do
    combat = player_action(:combat)
    assert %{skill: "melee_combat"} = ActionHandler.resolve(combat)

    observe = player_action(:observe)
    assert %{handler: "narrate", skill: nil} = ActionHandler.resolve(observe)
  end

  test "an NPC never sees a failed read; she does see a failed lie" do
    failed_read = %MechanicalResolution{skill: "insight", outcome: "failure", roll: 17}
    failed_lie = %MechanicalResolution{skill: "deception", outcome: "failure", roll: 17}

    assert NpcReactions.visible_outcome(failed_read, %{}) == nil
    assert NpcReactions.visible_outcome(failed_lie, %{}) == failed_lie
  end

  test "the GM prompt says a failed check means learning nothing extra, not a colder NPC" do
    gm = Prompts.gm_system()
    assert gm =~ "learns nothing extra"
    assert gm =~ "never makes an NPC colder"
    assert gm =~ "Outcome none means no check was needed"

    intent = Prompts.intent_system()
    assert intent =~ "Ordinary talk and everyday actions get no skill"
  end

  defp player_action(type) do
    %TalesForge.Game.Schemas.PlayerAction{
      overall_intent: "something",
      action: %SingleAction{action_type: type, target: nil, parameters: %{}}
    }
  end
end
