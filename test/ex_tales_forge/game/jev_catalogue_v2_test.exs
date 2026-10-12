defmodule TalesForge.Game.JevCatalogueV2Test do
  @moduledoc "Catalogue v2 of the Jev intent read (JEV_CATALOGUE_V2)."
  use ExUnit.Case, async: true

  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.JevIntent
  alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}

  @context %{
    "present_npcs" => ["innkeep"],
    "npc_details" => %{"innkeep" => %{"name" => "Brenna"}}
  }

  test "v2 asks for the ordered actions and the manner, and has the new types" do
    questions = JevIntent.questions(JevIntent.candidates(@context), :v2)
    {_q, actions} = questions[:action]

    for type <- ~w(rest work equip give none_fits other)a, do: assert(Map.has_key?(actions, type))
    refute Map.has_key?(actions, :freeform)
    assert Keyword.has_key?(questions, :then)
    assert Keyword.has_key?(questions, :then2)
    assert Keyword.has_key?(questions, :manner)
  end

  test "v1 stays as it was" do
    questions = JevIntent.questions(JevIntent.candidates(@context), :v1)
    refute Keyword.has_key?(questions, :then)
    {_q, actions} = questions[:action]
    refute Map.has_key?(actions, :rest)
  end

  test "decode reads 1 to 3 actions this turn, in order, and the manner" do
    reply = %{action: :spend, then: :rest, then2: :none, manner: :quietly, safety: :benign}
    reading = JevIntent.decode(reply, [], text: "I pay for a room and go to sleep")

    assert reading.action == :spend
    assert reading.then == [:rest]
    assert reading.manner == :quietly
    # The #198 lodging rule is for v1 only: v2 reads the sleep as its own action.
    assert reading.later == nil
  end

  test "a message that is not benign plays one action" do
    reply = %{action: :speak, then: :give, then2: :rest, safety: :prompt_injection}
    assert JevIntent.decode(reply, [], text: "x").then == []
  end

  test "rest is a wait and none_fits has no mechanics" do
    rest = ActionHandler.resolve(action(:rest, %{"ticks" => 8}))
    assert rest.handler == "wait"
    assert rest.state_hints["ticks"] == 8

    none = ActionHandler.resolve(action(:none_fits, %{}))
    assert none.handler == "narrate"
    assert none.state_hints["none_fits"]
    assert none.skill == nil
  end

  defp action(type, params),
    do: %PlayerAction{
      overall_intent: "x",
      action: %SingleAction{action_type: type, parameters: params}
    }
end
