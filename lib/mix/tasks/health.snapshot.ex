defmodule Mix.Tasks.Health.Snapshot do
  @shortdoc "Writes docs/health/YYYY-MM-DD.md with today's code health numbers"
  @moduledoc """
  Writes this week's code health snapshot to `docs/health/YYYY-MM-DD.md`: the
  numbers `mix health.check` measures, next to the baseline. Run weekly by
  `.github/workflows/health-snapshot.yml`, which opens a PR with the file.
  """
  use Mix.Task

  alias Mix.Tasks.Health.Check

  @impl Mix.Task
  def run(_args) do
    baseline = "docs/health/baseline.json" |> File.read!() |> Jason.decode!()
    current = Check.collect()
    path = "docs/health/#{current["date"]}.md"
    File.write!(path, render(baseline, current))
    Mix.shell().info("Wrote #{path}")
  end

  @doc "The snapshot as Markdown."
  @spec render(map(), map()) :: String.t()
  def render(baseline, current) do
    now = current["summary"]
    base = baseline["summary"]
    problems = Check.check(baseline, current)

    """
    # Code health #{current["date"]}

    Measured by `mix health.check`. Baseline: `docs/health/baseline.json` (#{baseline["date"]}).

    | Number | Now | Baseline |
    | --- | --- | --- |
    #{row("xref cycles (all)", now, base, ["cycle_count", "all"])}
    #{row("xref cycles (compile-connected)", now, base, ["cycle_count", "compile-connected"])}
    #{row("Largest cycle (all)", now, base, ["largest_cycle", "all"])}
    #{row("Largest cycle (compile-connected)", now, base, ["largest_cycle", "compile-connected"])}
    #{row("Domain files referencing web files", now, base, ["web_reference_files"])}
    #{row("Domain -> web file references", now, base, ["web_reference_edges"])}
    #{row("Functions over complexity/ABC limits", now, base, ["complex_function_count"])}

    ## Worse than the baseline

    #{if problems == [], do: "Nothing.", else: Enum.map_join(problems, "\n", &"- #{&1}")}

    ## Most complex functions

    | Function | Cyclomatic | ABC |
    | --- | --- | --- |
    #{current["complex_functions"] |> Enum.sort_by(&(-(&1["abc_size"] || 0))) |> Enum.take(15) |> Enum.map_join("\n", &function_row/1)}
    """
  end

  defp row(name, now, base, path),
    do: "| #{name} | #{get_in(now, path)} | #{get_in(base, path)} |"

  defp function_row(f),
    do: "| `#{f["function"]}` | #{f["cyclomatic_complexity"] || "-"} | #{f["abc_size"] || "-"} |"
end
