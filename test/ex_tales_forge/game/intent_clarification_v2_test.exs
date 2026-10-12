defmodule TalesForge.Game.IntentClarificationV2Test do
  use ExUnit.Case, async: true

  alias TalesForge.Game.IntentClarification

  doctest TalesForge.Game.IntentClarification
  alias TalesForge.Game.Schemas.{IntentExtraction, SingleAction}

  @candidates [
    %{kind: :item, id: "bread", text: "Bread (carried)"},
    %{kind: :item, id: "rope", text: "Rope (for sale)"},
    %{kind: :item, id: "lamp", text: "Lamp (for sale)"},
    %{kind: :npc, id: "brenna", text: "Brenna Holt — innkeeper (present)"},
    %{kind: :place, id: "market", text: "Market Square (exit)"}
  ]

  defp reading(action, target, top2, ranking) do
    %{
      action: action,
      top2: top2,
      confidence: 0.3,
      target_ranking: ranking,
      extraction: %IntentExtraction{
        overall_intent: "x",
        actions: [%SingleAction{action_type: action, target: target, parameters: %{}}],
        primary_index: 0,
        confidence: 0.3,
        needs_clarification: false
      }
    }
  end

  test "buy never offers a carried item or a person" do
    r = reading(:buy, "bread", [:buy, :speak], [{"bread", 0.4}, {"brenna", 0.3}, {"rope", 0.2}])
    options = IntentClarification.options_v2(r, @candidates)

    refute Enum.any?(options, &(&1.action_type == :buy and &1.target in ["bread", "brenna"]))
    assert %SingleAction{action_type: :buy, target: "rope"} in options
    assert %SingleAction{action_type: :speak, target: "brenna"} in options
  end

  test "at most three options and one templated question" do
    r =
      reading(:buy, "rope", [:buy, :move], [
        {"rope", 0.3},
        {"lamp", 0.3},
        {"market", 0.2},
        {"brenna", 0.1}
      ])

    c = IntentClarification.build(r, @candidates, v2: true)
    assert length(c["options"]) <= 3
    assert c["question"] =~ ~r/^Do you want to .+\?$/
    assert c["source"] == "jev"
  end

  test "the v1 build is unchanged without the flag" do
    r = reading(:buy, "bread", [:buy, :speak], [{"bread", 0.4}, {"brenna", 0.3}])
    c = IntentClarification.build(r, @candidates)
    assert Enum.any?(c["options"], &(&1["label"] == "buy"))
  end
end
