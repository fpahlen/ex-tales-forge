defmodule Workflow.SlicingPieTest do
  use ExUnit.Case, async: true

  alias Workflow.SlicingPie

  doctest Workflow.SlicingPie

  setup do
    %{team: Workflow.Team.example()}
  end

  test "sums the minutes of each contributor, largest first", %{team: team} do
    rows = [
      %{founder: "lin@x.se", minutes: 30},
      %{founder: "ada@x.se", minutes: 60},
      %{founder: "lin@x.se", minutes: 90},
      %{founder: "orjan@x.se", minutes: 0}
    ]

    assert [
             %{label: "Lin", minutes: 120, hours: "2.00", percent: 67},
             %{label: "Ada", percent: 33}
           ] =
             SlicingPie.slices(team, rows)
  end

  test "the sum of the percentages is 100" do
    for minutes <- [[1, 1, 1], [7, 13, 29, 51], [1, 2], [999, 1, 1], [5]] do
      assert minutes |> SlicingPie.percents() |> Enum.sum() == 100, inspect(minutes)
    end
  end

  test "the hours agree with the CSV export" do
    assert SlicingPie.slices(Workflow.Team.example(), [%{founder: "a@x.se", minutes: 125}])
           |> hd()
           |> Map.fetch!(:hours) == TalesForge.WorkLog.Report.hours(125)
  end

  test "one contributor gets a full circle", %{team: team} do
    assert [%{percent: 100, path: "M 50 2 A" <> _}] =
             SlicingPie.slices(team, [%{founder: "ada@x.se", minutes: 10}])
  end

  test "a slice of more than half uses the large arc", %{team: team} do
    [big, small] =
      SlicingPie.slices(team, [
        %{founder: "ada@x.se", minutes: 3},
        %{founder: "lin@x.se", minutes: 1}
      ])

    assert big.path =~ " 0 1 1 "
    assert small.path =~ " 0 0 1 "
  end

  test "an empty range gives no slices", %{team: team} do
    assert SlicingPie.slices(team, []) == []
    assert SlicingPie.percents([0, 0]) == [0, 0]
  end
end
