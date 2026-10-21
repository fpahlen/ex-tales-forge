defmodule TalesForge.Game.OutcomeProseCharacterizationTest do
  @moduledoc """
  Characterization of the item deltas of `OutcomeRecord.build/1` and the
  item mismatches of `ProseCheck.check/2` before round 2 PR 9: exact
  outputs from main, except that "Nobody gives you anything." no longer
  reports an item "nything". Pure, no LLM calls.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Game.{OutcomeRecord, ProseCheck}
  alias TalesForge.Game.Schemas.SingleAction

  defp world(inventory),
    do: %{
      "world_tick" => 1,
      "character" => %{
        "location_id" => "inn",
        "coins" => %{"copper" => 10},
        "inventory" => inventory
      }
    }

  # {inventory before, inventory after, record items}: summed quantities,
  # the name after the turn, ids sorted, bare-string and nameless items.
  @deltas [
    {[], [], %{"gained" => [], "lost" => []}},
    {[%{"id" => "knife", "name" => "hunting knife", "quantity" => 1}],
     [
       %{"id" => "knife", "name" => "hunting knife", "quantity" => 1},
       %{"id" => "ale_mug", "name" => "mug of ale", "quantity" => 2}
     ],
     %{"gained" => [%{"id" => "ale_mug", "name" => "mug of ale", "quantity" => 2}], "lost" => []}},
    {[
       %{"id" => "knife", "name" => "hunting knife"},
       %{"id" => "bread", "name" => "bread", "quantity" => 3},
       %{"id" => "knife", "name" => "hunting knife", "quantity" => 2}
     ], [%{"id" => "bread", "name" => "stale bread", "quantity" => 1}],
     %{
       "gained" => [],
       "lost" => [
         %{"id" => "bread", "name" => "stale bread", "quantity" => 2},
         %{"id" => "knife", "name" => "hunting knife", "quantity" => 3}
       ]
     }},
    {["rope", %{"id" => "zeta", "quantity" => 1}],
     [%{"id" => "apple", "name" => "apple", "quantity" => 1}, "rope", "rope"],
     %{
       "gained" => [%{"id" => "apple", "name" => "apple", "quantity" => 1}],
       "lost" => [%{"id" => "zeta", "name" => "Zeta", "quantity" => 1}]
     }},
    {[%{"id" => "cloak", "name" => "cloak", "quantity" => 1}],
     [%{"id" => "cloak", "name" => "cloak", "quantity" => 1}], %{"gained" => [], "lost" => []}}
  ]

  test "item deltas: gained and lost, by id" do
    for {before, after_turn, expected} <- @deltas do
      record =
        OutcomeRecord.build(%OutcomeRecord.Input{
          world_before: world(before),
          world_after: world(after_turn),
          action: %SingleAction{action_type: :other},
          handler: %{handler: "narrate"},
          inventory_result: nil
        })

      assert record["items"] == expected
    end
  end

  defp record(nil, nil), do: %{}

  defp record(gained, delta),
    do: %{
      "items" => %{"gained" => gained, "lost" => []},
      "coins" => %{"delta_copper" => delta},
      "location" => %{"from" => "inn", "to" => "inn"},
      "clock" => %{"tick_before" => 1, "tick_after" => 2}
    }

  # {prose, items gained (nil: empty record), copper delta, item mismatches}
  @prose [
    {"Brenna hands you a mug of ale.", [], 0, [%{kind: :item, detail: "mug of ale"}]},
    {"Brenna hands you a mug of ale.", [%{"id" => "ale_mug", "name" => "mug of ale"}], 0, []},
    {"She gives you the key and passes you some bread, then tosses you three copper.", [], 0,
     [%{kind: :item, detail: "key"}, %{kind: :item, detail: "bread"}]},
    {"He slides a bowl of stew across to you. She sets the mug in front of you.", [], 0,
     [%{kind: :item, detail: "bowl of stew"}, %{kind: :item, detail: "mug"}]},
    {"He slides a bowl of stew across to you.", [], -5, []},
    {"She offers you your coins back; he gives you gold.", [], 0, []},
    {"Brenna hands you a warm loaf and offers you the stew for two copper.",
     [%{"id" => "bowl_of_stew", "name" => "bowl of stew"}], 0,
     [%{kind: :item, detail: "warm loaf"}]},
    {"Brenna Hands You A Knife!", [], 0, [%{kind: :item, detail: "knife"}]},
    {"Nobody gives you anything.", nil, nil, []},
    {"She hands you nothing; he offers you something.", nil, nil, []},
    {"He passes you everyone's thanks.", nil, nil, []},
    {"Nobody gives anyone anything.", nil, nil, []},
    {"She hands you an apple.", nil, nil, [%{kind: :item, detail: "apple"}]},
    {"She hands you anise seed.", nil, nil, [%{kind: :item, detail: "anise seed"}]}
  ]

  test "prose items the record does not back, in order" do
    for {prose, gained, delta, expected} <- @prose do
      found = prose |> ProseCheck.check(record(gained, delta)) |> Enum.filter(&(&1.kind == :item))
      assert found == expected, prose
    end
  end
end
