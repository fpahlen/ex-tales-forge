defmodule Mix.Tasks.Health.SnapshotTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Health.Snapshot

  doctest Mix.Tasks.Health.Snapshot

  @numbers %{
    "summary" => %{
      "cycle_count" => %{"all" => 64, "compile-connected" => 1},
      "largest_cycle" => %{"all" => 10, "compile-connected" => 5},
      "web_reference_files" => 1,
      "web_reference_edges" => 2,
      "complex_function_count" => 80,
      "wide_function_count" => 124
    }
  }

  test "a row holds the numbers" do
    row = Snapshot.row(@numbers, "2026-10-17T09:29:00+02:00", 85)

    assert row == %{
             "date" => "2026-10-17T09:29:00+02:00",
             "pr" => 85,
             "cycles" => 64,
             "largest_cycle" => 10,
             "compile_connected_cycles" => 1,
             "compile_connected_largest" => 5,
             "web_refs" => 2,
             "complex_functions" => 80,
             "params_4plus" => 124
           }
  end

  test "rows round-trip through the CSV, and a row of the same PR is replaced" do
    a = Snapshot.row(@numbers, "2026-10-17T08:00:00+02:00", 84)
    b = Snapshot.row(@numbers, "2026-10-17T09:00:00+02:00", 85)

    rows =
      [] |> Snapshot.put_row(a) |> Snapshot.put_row(b) |> Snapshot.put_row(%{b | "cycles" => 63})

    assert Enum.map(rows, &{&1["pr"], &1["cycles"]}) == [{84, 64}, {85, 63}]
    assert rows |> Snapshot.csv() |> Snapshot.parse() == rows
  end

  test "rows only in the kept file are added in date order" do
    a = Snapshot.row(@numbers, "2026-10-17T08:00:00+02:00", 84)
    b = Snapshot.row(@numbers, "2026-10-17T09:00:00+02:00", 85)
    c = Snapshot.row(@numbers, "2026-10-17T10:00:00+02:00", 86)
    old = Map.delete(b, "params_4plus")

    assert Snapshot.keep_rows([a, c], [a, old]) == [a, old, c]
    assert Snapshot.keep_rows([a, c], [a]) == [a, c]
  end

  test "the chart stacks cycles, complex functions, web refs and 4+ param functions, with the total on top" do
    rows = [Snapshot.row(@numbers, "2026-10-17", 84), Snapshot.row(@numbers, "2026-10-18", 85)]
    svg = Snapshot.svg(rows)

    assert svg =~ "total, lower is better"
    # 2 bars of 4 segments, plus the background and 4 legend boxes.
    assert length(Regex.scan(~r/<rect /, svg)) == 2 * 4 + 1 + 4
    # One dashed line per segment between the two bars.
    assert length(Regex.scan(~r/stroke-dasharray/, svg)) == 4
    assert svg =~ ~s(font-weight="bold">270</text>)
    assert svg =~ "#85"
  end
end
