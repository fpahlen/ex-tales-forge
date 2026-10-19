defmodule TalesForge.DeployLanes.AutoCLI do
  @moduledoc """
  Decides the auto merge lane (`TalesForge.DeployLanes.Auto`) for
  `.github/workflows/security-lane.yml`, through `.github/scripts/auto_lane.exs`
  (plain `elixir`, run from `main`'s checkout so a PR cannot change its rules).

      # A pull request, after its CI run:
      elixir .github/scripts/auto_lane.exs pr --base <base sha> --head <head sha> \\
        --pr pr.json --checks checks.json

      # Dry run over merged pull requests (no merge, no GitHub call):
      elixir .github/scripts/auto_lane.exs history --prs prs.json

  `pr.json` is `gh pr view --json title,body,labels,headRefName`. `checks.json`
  is `{"checks": [{"name", "status", "conclusion"}]}`: the head sha's check runs
  and commit statuses (the workflow builds it with `gh api` and `jq`).
  `prs.json` is `{"prs": [...]}`, each a merged PR with `number`, `title`,
  `headRefName`, `labels`, `mergeCommit.oid` and its `checks`; its diff is the
  merge commit against its first parent.

  `pr` writes `lane=auto|normal` and `class=…` to `$GITHUB_OUTPUT` and the rules
  to `$GITHUB_STEP_SUMMARY`; `history` prints a Markdown table.
  """

  alias TalesForge.DeployLanes
  alias TalesForge.DeployLanes.Auto
  alias TalesForge.DeployLanes.SecurityCLI

  @deciding "What you're deciding:"

  @typedoc "Runs a git command (argument list) and returns `{output, exit_status}`."
  @type git :: ([String.t()] -> {String.t(), non_neg_integer()})

  @doc "Entry point for the script."
  @spec main([String.t()]) :: :ok
  def main([mode | argv]) when mode in ["pr", "history"] do
    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [
          base: :string,
          head: :string,
          pr: :string,
          checks: :string,
          prs: :string,
          lanes: :string
        ]
      )

    lanes = DeployLanes.load(opts[:lanes] || DeployLanes.default_path())
    run(mode, lanes, opts)
  end

  def main(_argv) do
    IO.puts(
      :stderr,
      "usage: auto_lane.exs pr|history [options] (see TalesForge.DeployLanes.AutoCLI)"
    )

    System.halt(2)
  end

  defp run("pr", lanes, opts) do
    pr = read_json(opts[:pr])
    checks = read_json(opts[:checks])["checks"] || []
    {merge_base, 0} = git(["merge-base", opts[:base], opts[:head]])
    files = changed_files(&git/1, String.trim(merge_base), opts[:head])
    result = Auto.check(lanes, input(pr, files, checks))
    markdown = Enum.join(summary(result, pr), "\n") <> "\n"
    IO.puts(markdown)
    append_env("GITHUB_OUTPUT", "lane=#{result.lane}\nclass=#{result.class}\n")
    append_env("GITHUB_STEP_SUMMARY", markdown)
  end

  defp run("history", lanes, opts) do
    prs = read_json(opts[:prs])["prs"] || []
    IO.puts(history_table(lanes, prs, &git/1))
  end

  @doc "The input `Auto.check/2` needs, from `pr.json`, the changed files and the checks."
  @spec input(map(), [Auto.file()], [map()]) :: Auto.input()
  def input(pr, files, checks) do
    %{
      files: files,
      branch: pr["headRefName"] || "",
      labels: Enum.map(pr["labels"] || [], &(&1["name"] || "")),
      checks: Enum.map(checks, &check/1)
    }
  end

  defp check(map),
    do: %{name: map["name"] || "", status: map["status"] || "", conclusion: map["conclusion"]}

  @doc "The run summary: the verdict, every rule, and a note when a founder PR has no decision line."
  @spec summary(Auto.result(), map()) :: [String.t()]
  def summary(result, pr) do
    rules =
      for r <- result.rules,
          do: "- #{if r.ok, do: "PASS", else: "FAIL"} **#{r.name}:** #{r.detail}"

    [verdict(result), "" | rules] ++ decision_note(result.lane, pr["body"] || "")
  end

  defp verdict(%{lane: :auto, class: class}),
    do: "### Auto lane: yes (#{class_name(class)}), the bot merges this head sha"

  defp verdict(_result), do: "### Auto lane: no, a founder reviews and merges"

  defp decision_note(:normal, body) do
    if String.starts_with?(String.trim_leading(body), @deciding),
      do: [],
      else: ["", "::warning::This PR needs a founder: start its body with `#{@deciding} ...`."]
  end

  defp decision_note(:auto, _body), do: []

  @doc "The dry-run table: the lane and class each merged pull request would have got."
  @spec history_table(DeployLanes.t(), [map()], git()) :: String.t()
  def history_table(lanes, prs, git) do
    rows =
      for pr <- prs do
        oid = get_in(pr, ["mergeCommit", "oid"])
        files = changed_files(git, "#{oid}^1", oid)
        result = Auto.check(lanes, input(pr, files, pr["checks"] || []))
        "| ##{pr["number"]} | #{escape(pr["title"])} | #{lane_name(result)} | #{why(result)} |"
      end

    Enum.join(["| PR | Title | Would get | Why |", "|---|---|---|---|" | rows], "\n")
  end

  defp lane_name(%{lane: :auto, class: class}), do: "**auto** (#{class_name(class)})"
  defp lane_name(_result), do: "founder"

  defp why(%{lane: :auto}), do: "every rule passes"

  defp why(%{rules: rules}),
    do: rules |> Enum.reject(& &1.ok) |> Enum.map_join("; ", &"#{&1.name}: #{escape(&1.detail)}")

  defp class_name(:docs_only), do: "docs-only"
  defp class_name(:health_history), do: "health-history"
  defp class_name(nil), do: "none"

  defp escape(text), do: String.replace(text || "", "|", "\\|")

  @doc "The changed files between `from` and `to`, as `{status, path}` (renames as delete + add)."
  @spec changed_files(git(), String.t(), String.t()) :: [Auto.file()]
  def changed_files(git, from, to) do
    case git.(["diff", "--name-status", "--no-renames", from, to]) do
      {out, 0} ->
        for line <- String.split(out, "\n", trim: true),
            [status, path] <- [String.split(line, "\t", parts: 2)],
            do: {String.first(status), path}

      {out, status} ->
        raise "git diff #{from} #{to} failed (#{status}): #{out}"
    end
  end

  defp read_json(path), do: path |> File.read!() |> SecurityCLI.decode_pr()

  defp append_env(var, text) do
    case System.get_env(var) do
      nil -> :ok
      "" -> :ok
      path -> File.write!(path, text, [:append])
    end
  end

  defp git(args), do: System.cmd("git", args, stderr_to_stdout: true)
end
