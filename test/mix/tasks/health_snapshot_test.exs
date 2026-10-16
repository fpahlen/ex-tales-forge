defmodule Mix.Tasks.Health.SnapshotTest do
  use ExUnit.Case, async: true

  test "renders the numbers next to the baseline" do
    summary = %{
      "cycle_count" => %{"all" => 3, "compile-connected" => 1},
      "largest_cycle" => %{"all" => 5, "compile-connected" => 2},
      "web_reference_files" => 2,
      "web_reference_edges" => 4,
      "complex_function_count" => 1
    }

    numbers = %{
      "date" => "2026-10-19",
      "limits" => %{"cyclomatic_complexity" => 9, "abc_size" => 30},
      "cycles" => %{"all" => []},
      "web_references" => [],
      "complex_functions" => [%{"function" => "A.f", "abc_size" => 40}],
      "summary" => summary
    }

    md = Mix.Tasks.Health.Snapshot.render(numbers, numbers)
    assert md =~ "# Code health 2026-10-19"
    assert md =~ "| xref cycles (all) | 3 | 3 |"
    assert md =~ "| `A.f` | - | 40 |"
    assert md =~ "Nothing."
  end
end
