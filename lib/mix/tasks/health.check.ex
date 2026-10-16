defmodule Mix.Tasks.Health.Check do
  @shortdoc "Fails when code health gets worse than docs/health/baseline.json"
  @moduledoc """
  The code health ratchet. Measures today's numbers and compares them with
  `docs/health/baseline.json`. The build fails when:

    * an xref cycle count goes up, or a cycle appears that is not the same as
      (or smaller than) a baseline cycle (a new or a bigger cycle);
    * a file in `lib/ex_tales_forge/` gets a new xref reference to a file in
      `lib/ex_tales_forge_web/` that is not in the baseline;
    * a function goes over the Credo cyclomatic complexity (#{9}) or ABC size
      (#{30}) limit and is not in the baseline, or a baseline function scores
      higher than its baseline value (its ceiling).

  With `--base REF` it also checks that the baseline itself only shrinks
  compared with the one at `REF` (CI passes the PR's base branch): no new
  entries, no higher ceilings, no higher counts.

      mix health.check
      mix health.check --base origin/main
      mix health.check --write   # rewrite the baseline with today's numbers

  `--write` is for paying debt down. A baseline that grows fails `--base`.
  """
  use Mix.Task

  @baseline "docs/health/baseline.json"
  @limits %{"cyclomatic_complexity" => 9, "abc_size" => 30}
  @domain "lib/ex_tales_forge/"
  @web "lib/ex_tales_forge_web/"
  @labels %{"all" => [], "compile-connected" => ["--label", "compile-connected"]}

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [base: :string, write: :boolean])
    current = collect()

    if opts[:write] do
      File.write!(@baseline, Jason.encode!(current, pretty: true) <> "\n")
      Mix.shell().info("Wrote #{@baseline}")
    else
      baseline = @baseline |> File.read!() |> Jason.decode!()

      base_errors =
        if ref = opts[:base], do: shrink_errors(base_baseline(ref), baseline), else: []

      report(check(baseline, current) ++ base_errors)
    end
  end

  defp report([]), do: Mix.shell().info("Code health: no worse than #{@baseline}.")

  defp report(errors) do
    Enum.each(errors, &Mix.shell().error/1)
    Mix.raise("Code health got worse (#{length(errors)} problems). See #{@baseline}.")
  end

  defp base_baseline(ref) do
    case System.cmd("git", ["show", "#{ref}:#{@baseline}"], stderr_to_stdout: true) do
      {json, 0} -> Jason.decode!(json)
      # No baseline at the base yet (the PR that adds it): nothing to shrink from.
      {_, _} -> nil
    end
  end

  @doc "Today's numbers, in the shape of the baseline file."
  @spec collect() :: map()
  def collect do
    cycles = Map.new(@labels, fn {name, args} -> {name, cycles(args)} end)

    numbers = %{
      "date" => Date.to_iso8601(Date.utc_today()),
      "limits" => @limits,
      "cycles" => cycles,
      "web_references" => web_references(),
      "complex_functions" => complex_functions()
    }

    Map.put(numbers, "summary", summary(numbers))
  end

  defp summary(numbers) do
    cycles = numbers["cycles"]
    refs = numbers["web_references"]

    %{
      "cycle_count" => Map.new(cycles, fn {k, v} -> {k, length(v)} end),
      "largest_cycle" => Map.new(cycles, fn {k, v} -> {k, max_size(v)} end),
      "web_reference_files" => length(refs),
      "web_reference_edges" => refs |> Enum.flat_map(& &1["to"]) |> length(),
      "complex_function_count" => length(numbers["complex_functions"])
    }
  end

  defp max_size([]), do: 0
  defp max_size(cycles), do: cycles |> Enum.map(& &1["size"]) |> Enum.max()

  defp mix(args) do
    {out, _status} = System.cmd("mix", args)
    out
  end

  @doc "Parses `mix xref graph --format cycles` output."
  @spec parse_cycles(String.t()) :: [map()]
  def parse_cycles(out) do
    out
    |> String.split(~r/^Cycle of length \d+:$/m)
    |> Enum.drop(1)
    |> Enum.map(fn chunk ->
      members =
        for line <- String.split(chunk, "\n"),
            line = String.trim(line),
            String.starts_with?(line, "lib/"),
            do: line |> String.split(" ") |> hd()

      members = Enum.sort(members)
      %{"size" => length(members), "members" => members}
    end)
    |> Enum.sort_by(&{-&1["size"], &1["members"]})
  end

  defp cycles(args), do: parse_cycles(mix(["xref", "graph", "--format", "cycles"] ++ args))

  @doc "Parses `mix xref graph --format plain` into domain -> web file references."
  @spec parse_web_references(String.t()) :: [map()]
  def parse_web_references(out) do
    out
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, &reference_line/2)
    |> elem(1)
    |> Enum.map(fn {from, to} -> %{"from" => from, "to" => Enum.sort(Enum.uniq(to))} end)
    |> Enum.sort_by(& &1["from"])
  end

  defp reference_line(line, {source, acc}) do
    case Regex.run(~r/^[|`]-- (\S+)/, line) do
      [_, sink] -> {source, add_reference(acc, source, sink)}
      nil -> {String.trim(line), acc}
    end
  end

  defp add_reference(acc, source, sink) do
    if String.starts_with?(source, @domain) and String.starts_with?(sink, @web),
      do: Map.update(acc, source, [sink], &[sink | &1]),
      else: acc
  end

  defp web_references, do: parse_web_references(mix(["xref", "graph", "--format", "plain"]))

  defp complex_functions do
    config = Path.join(System.tmp_dir!(), "health_credo.exs")

    File.write!(config, """
    %{configs: [%{name: "default", files: %{included: ["lib/"]}, strict: true,
      checks: %{enabled: [
        {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: #{@limits["cyclomatic_complexity"]}]},
        {Credo.Check.Refactor.ABCSize, [max_size: #{@limits["abc_size"]}]}
      ]}}]}
    """)

    out = mix(["credo", "--config-file", config, "--strict", "--format", "json"])
    out |> Jason.decode!() |> Map.fetch!("issues") |> parse_credo()
  end

  @doc "Turns Credo complexity issues into one entry per function with its scores."
  @spec parse_credo([map()]) :: [map()]
  def parse_credo(issues) do
    issues
    |> Enum.group_by(& &1["scope"])
    |> Enum.map(fn {scope, issues} ->
      Enum.reduce(issues, %{"function" => scope, "file" => hd(issues)["filename"]}, &add_score/2)
    end)
    |> Enum.sort_by(& &1["function"])
  end

  defp add_score(issue, acc) do
    key = if issue["check"] =~ "ABCSize", do: "abc_size", else: "cyclomatic_complexity"
    [_, score] = Regex.run(~r/is (\d+), max/, issue["message"])
    Map.update(acc, key, String.to_integer(score), &max(&1, String.to_integer(score)))
  end

  @doc "Problems in `current` compared with `baseline` (empty when no worse)."
  @spec check(map(), map()) :: [String.t()]
  def check(baseline, current) do
    cycle_errors(baseline, current) ++
      reference_errors(baseline, current) ++ function_errors(baseline, current)
  end

  @doc "Problems in `baseline` compared with the older `base` baseline: it may only shrink."
  @spec shrink_errors(map() | nil, map()) :: [String.t()]
  def shrink_errors(nil, _baseline), do: []

  def shrink_errors(base, baseline) do
    limit_errors =
      for {k, v} <- baseline["limits"],
          v > base["limits"][k],
          do: "baseline: limit #{k} raised to #{v}"

    Enum.map(check(base, baseline), &("baseline: " <> &1)) ++ limit_errors
  end

  defp cycle_errors(baseline, current) do
    Enum.flat_map(current["cycles"], fn {label, cycles} ->
      old = Map.get(baseline["cycles"], label, [])

      count =
        if length(cycles) > length(old),
          do: ["#{label} cycles: #{length(cycles)}, baseline #{length(old)}"],
          else: []

      count ++
        for cycle <- cycles, not Enum.any?(old, &subset?(cycle, &1)) do
          "#{label} cycle of #{cycle["size"]} is new or bigger: #{Enum.join(cycle["members"], ", ")}"
        end
    end)
  end

  defp subset?(cycle, old),
    do: MapSet.subset?(MapSet.new(cycle["members"]), MapSet.new(old["members"]))

  defp reference_errors(baseline, current) do
    allowed = MapSet.new(for r <- baseline["web_references"], to <- r["to"], do: {r["from"], to})

    for r <- current["web_references"], to <- r["to"], {r["from"], to} not in allowed do
      "new #{@domain} -> #{@web} reference: #{r["from"]} -> #{to}"
    end
  end

  defp function_errors(baseline, current) do
    allowed = Map.new(baseline["complex_functions"], &{&1["function"], &1})

    Enum.flat_map(current["complex_functions"], fn fun ->
      ceiling_errors(fun, allowed[fun["function"]], baseline["limits"])
    end)
  end

  defp ceiling_errors(fun, nil, _limits),
    do: ["new function over the complexity limits: #{fun["function"]} (#{fun["file"]})"]

  defp ceiling_errors(fun, old, limits) do
    for {key, limit} <- limits, score = fun[key], score > (old[key] || limit) do
      "#{fun["function"]}: #{key} #{score}, ceiling #{old[key] || limit}"
    end
  end
end
