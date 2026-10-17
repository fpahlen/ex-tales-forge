defmodule Mix.Tasks.Health.Snapshot do
  @shortdoc "Appends this merge's code health row to docs/health/history.csv and redraws trend.svg"
  @moduledoc """
  The code health history: one row per merge to main in
  `docs/health/history.csv`, drawn as `docs/health/trend.svg`.

  `mix health.snapshot` measures HEAD (`mix health.check`'s numbers), takes
  the date and the PR number from HEAD's commit (`--pr` and `--date`
  override them), puts the row in the CSV (a row for the same PR is
  replaced) and redraws the chart. `.github/workflows/health-snapshot.yml`
  runs it after each merge to main and opens one rolling PR with the rows.

      mix health.snapshot
      mix health.snapshot --pr 326 --date 2026-10-17T06:01:43+02:00
      mix health.snapshot --keep /tmp/branch.csv

  `--keep FILE` also keeps the rows of another history file whose PR the
  CSV does not have (in date order). The workflow passes the rolling
  branch's file from before it merged main, so a conflict in the CSV that
  it resolved with main's side loses no row.
  """
  use Mix.Task

  alias Mix.Tasks.Health.Check

  @csv "docs/health/history.csv"
  @svg "docs/health/trend.svg"

  @columns ~w(date pr cycles largest_cycle compile_connected_cycles compile_connected_largest
              web_refs complex_functions params_4plus counting)

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [pr: :integer, date: :string, keep: :string])
    {pr, date} = head_commit()
    row = row(Check.collect(), opts[:date] || date, opts[:pr] || pr)
    kept = if opts[:keep], do: read(opts[:keep]), else: []
    rows = @csv |> read() |> keep_rows(kept) |> put_row(row)
    File.write!(@csv, csv(rows))
    File.write!(@svg, svg(rows))
    Mix.shell().info("Wrote #{@csv} (PR ##{row["pr"]}) and #{@svg}")
  end

  # The PR number and date of HEAD: "Merge pull request #85 from ..." or a
  # squash merge "Title (#57)".
  defp head_commit do
    {out, 0} = System.cmd("git", ["log", "-1", "--format=%cI%n%s"])
    [date, subject] = String.split(out, "\n", parts: 2)
    {pr_of(subject), date}
  end

  @doc """
  The PR number in a merge commit's subject, or nil.

      iex> Mix.Tasks.Health.Snapshot.pr_of("Merge pull request #85 from whyse-ab/x")
      85
      iex> Mix.Tasks.Health.Snapshot.pr_of("Chat: delete a message (#57)")
      57
      iex> Mix.Tasks.Health.Snapshot.pr_of("Fix a typo")
      nil
  """
  @spec pr_of(String.t()) :: pos_integer() | nil
  def pr_of(subject) do
    case Regex.run(~r/#(\d+)/, subject) do
      [_, n] -> String.to_integer(n)
      nil -> nil
    end
  end

  @doc "One history row from `mix health.check`'s numbers (`Check.collect/0`)."
  @spec row(map(), String.t(), pos_integer() | nil) :: %{String.t() => term()}
  def row(numbers, date, pr) do
    s = numbers["summary"]

    %{
      "date" => date,
      "pr" => pr,
      "cycles" => s["cycle_count"]["all"],
      "largest_cycle" => s["largest_cycle"]["all"],
      "compile_connected_cycles" => s["cycle_count"]["compile-connected"],
      "compile_connected_largest" => s["largest_cycle"]["compile-connected"],
      "web_refs" => s["web_reference_edges"],
      "complex_functions" => s["complex_function_count"],
      "params_4plus" => s["wide_function_count"],
      "counting" => numbers["counting"]
    }
  end

  @doc "Adds the rows of `kept` whose PR is not in `rows`, in date order."
  @spec keep_rows([map()], [map()]) :: [map()]
  def keep_rows(rows, kept) do
    prs = MapSet.new(rows, & &1["pr"])

    case Enum.reject(kept, &(&1["pr"] in prs)) do
      [] -> rows
      extra -> Enum.sort_by(rows ++ extra, & &1["date"])
    end
  end

  @doc "Puts `row` in place of the row of the same PR, else at the end (merge order)."
  @spec put_row([map()], map()) :: [map()]
  def put_row(rows, row) do
    case Enum.find_index(rows, &(row["pr"] != nil and &1["pr"] == row["pr"])) do
      nil -> rows ++ [row]
      i -> List.replace_at(rows, i, row)
    end
  end

  @doc "The rows of a history CSV file (none when it is missing)."
  @spec read(Path.t()) :: [map()]
  def read(path) do
    case File.read(path) do
      {:ok, text} -> parse(text)
      {:error, :enoent} -> []
    end
  end

  @doc """
  The rows of history CSV text. Numbers come back as integers.

      iex> Mix.Tasks.Health.Snapshot.parse("date,pr,cycles\\n2026-10-17,85,64\\n")
      [%{"date" => "2026-10-17", "pr" => 85, "cycles" => 64}]
  """
  @spec parse(String.t()) :: [map()]
  def parse(text) do
    [header | lines] = String.split(text, "\n", trim: true)
    keys = String.split(header, ",")

    for line <- lines do
      keys
      |> Enum.zip(String.split(line, ","))
      |> Map.new(fn
        {"date", v} -> {"date", v}
        {k, ""} -> {k, nil}
        {k, v} -> {k, String.to_integer(v)}
      end)
    end
  end

  @doc "The rows as CSV text."
  @spec csv([map()]) :: String.t()
  def csv(rows) do
    lines = for r <- rows, do: Enum.map_join(@columns, ",", &to_string(r[&1]))
    Enum.join([Enum.join(@columns, ",") | lines], "\n") <> "\n"
  end

  # Bottom to top.
  @segments [
    {"cycles", "xref cycles", "#b91c1c"},
    {"complex_functions", "complex functions", "#15803d"},
    {"web_refs", "domain → web refs", "#7c3aed"},
    {"params_4plus", "functions with 4+ params", "#b45309"}
  ]

  @w 920
  @h 420
  @pad %{l: 48, r: 170, t: 48, b: 40}

  @doc """
  The rows as a stacked bar chart: one bar per merge, its segments xref
  cycles, complex functions, domain -> web refs and functions with 4+
  parameters (bottom to top). Each
  segment shows its value, each bar its total on top, and a thin dashed
  line joins a segment's top to the same segment's top on the next bar.
  A bar whose `counting` differs from the bar before it (a row without one
  counts as 1) gets a grey dashed line and "counting changed": that drop or
  rise comes from how `mix health.check` counts, not from the code.
  """
  @spec svg([map()]) :: String.t()
  def svg(rows) do
    g = geometry(rows)
    tops = Enum.map(rows, &segment_tops/1)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@w}" height="#{@h}" viewBox="0 0 #{@w} #{@h}" font-family="sans-serif" font-size="11" fill="#374151">
    <rect width="#{@w}" height="#{@h}" fill="#ffffff"/>
    <text x="#{@pad.l}" y="24" font-size="15" font-weight="bold">Tales Forge code health per merge to main: total, lower is better</text>
    #{grid(g)}
    #{rows |> Enum.zip(tops) |> Enum.with_index() |> Enum.map_join("\n", &bar(&1, g))}
    #{links(tops, g)}
    #{marks(rows, g)}
    #{legend()}
    </svg>
    """
  end

  # The scale: the top value, the slot of one bar and the bar width.
  defp geometry(rows) do
    top = rows |> Enum.map(&total/1) |> Enum.max(fn -> 10 end) |> ceil_to(20) |> max(20)
    slot = (@w - @pad.l - @pad.r) / max(length(rows), 1)
    %{top: top, slot: slot, bar: slot * 0.6}
  end

  defp x(g, i), do: @pad.l + i * g.slot + (g.slot - g.bar) / 2
  defp y(g, v), do: @pad.t + (@h - @pad.t - @pad.b) * (1 - v / g.top)

  defp grid(%{top: top} = g) do
    Enum.map_join(0..top//div(top, 4), "\n", fn v ->
      ~s|<line x1="#{@pad.l}" y1="#{f(y(g, v))}" x2="#{@w - @pad.r}" y2="#{f(y(g, v))}" stroke="#e5e7eb"/>| <>
        ~s|<text x="#{@pad.l - 6}" y="#{f(y(g, v) + 4)}" text-anchor="end">#{v}</text>|
    end)
  end

  defp bar({{row, segs}, i}, g) do
    cx = x(g, i) + g.bar / 2

    for(
      {{k, _, color}, {from, to}} <- Enum.zip(@segments, segs),
      to > from,
      do: segment(g, i, row[k], color, {from, to})
    )
    |> Enum.join()
    |> Kernel.<>(
      ~s|<text x="#{f(cx)}" y="#{f(y(g, total(row)) - 5)}" text-anchor="middle" font-weight="bold">#{total(row)}</text>|
    )
    |> Kernel.<>(
      ~s|<text x="#{f(cx)}" y="#{@h - @pad.b + 16}" text-anchor="middle">##{row["pr"]}</text>|
    )
  end

  # One segment with its value inside. A thin segment gets a smaller
  # number, so it stays inside.
  defp segment(g, i, value, color, {from, to}) do
    {low, high} = {y(g, from), y(g, to)}
    size = (low - high - 1) |> min(10) |> max(6) |> round()

    ~s|<rect x="#{f(x(g, i))}" y="#{f(high)}" width="#{f(g.bar)}" height="#{f(low - high)}" fill="#{color}"/>| <>
      ~s|<text x="#{f(x(g, i) + g.bar / 2)}" y="#{f((low + high) / 2 + size * 0.35)}" text-anchor="middle" fill="#ffffff" font-size="#{size}">#{value}</text>|
  end

  # A thin dashed line from each segment's top to its top on the next bar.
  defp links(tops, %{bar: bar} = g) do
    pairs = tops |> Enum.zip(Enum.drop(tops, 1)) |> Enum.with_index()

    Enum.map_join(
      for({{a, b}, i} <- pairs, seg <- Enum.zip([@segments, a, b]), do: {i, seg}),
      "\n",
      fn {i, {{_, _, color}, {_, ta}, {_, tb}}} ->
        ~s|<line x1="#{f(x(g, i) + bar)}" y1="#{f(y(g, ta))}" x2="#{f(x(g, i + 1))}" y2="#{f(y(g, tb))}" stroke="#{color}" stroke-width="1" stroke-dasharray="3 3"/>|
      end
    )
  end

  # A grey dashed line left of each bar where the counting changed.
  defp marks(rows, g) do
    counts = Enum.map(rows, &(&1["counting"] || 1))

    for {{a, b}, i} <- counts |> Enum.zip(Enum.drop(counts, 1)) |> Enum.with_index(1),
        a != b,
        into: "" do
      line_x = f(@pad.l + i * g.slot)

      ~s|<line x1="#{line_x}" y1="#{@pad.t - 8}" x2="#{line_x}" y2="#{@h - @pad.b}" stroke="#6b7280" stroke-width="1" stroke-dasharray="2 4"/>| <>
        ~s|<text x="#{line_x}" y="#{@pad.t - 12}" text-anchor="middle" font-size="10" fill="#6b7280">counting changed</text>|
    end
  end

  defp legend do
    @segments
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {{_, name, color}, j} ->
      ~s|<rect x="#{@w - @pad.r + 16}" y="#{@pad.t + j * 22}" width="12" height="12" fill="#{color}"/>| <>
        ~s|<text x="#{@w - @pad.r + 34}" y="#{@pad.t + j * 22 + 11}">#{name}</text>|
    end)
  end

  defp total(row), do: Enum.sum(for {k, _, _} <- @segments, do: row[k] || 0)

  # The {bottom, top} value of each segment of `row`, bottom first.
  defp segment_tops(row) do
    {segs, _} =
      Enum.map_reduce(@segments, 0, fn {k, _, _}, at ->
        {{at, at + (row[k] || 0)}, at + (row[k] || 0)}
      end)

    segs
  end

  defp ceil_to(v, step), do: div(v + step - 1, step) * step
  defp f(v), do: :erlang.float_to_binary(v / 1, decimals: 1)
end
