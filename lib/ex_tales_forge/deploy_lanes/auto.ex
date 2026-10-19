defmodule TalesForge.DeployLanes.Auto do
  @moduledoc """
  The **auto** merge lane (`docs/design-auto-merge.md`): a pull request that
  CI can prove safe is merged by the bot with no founder review.

  A pull request takes the auto lane only when all of these are true:

    1. **No founder file.** No changed path is on the `[founder]` list in
       `.github/deploy-lanes.txt` (migrations and data under `priv/`, SQL,
       `mix.exs`/`mix.lock`, `fly*.toml`, `Dockerfile`, `rel/`, `config/`,
       `.github/`, `docs/decisions.md`).
    2. **No deletion** outside `docs/` and `test/`.
    3. **No `user-visible` label.** The label can only add founder review.
    4. **An auto class:** *docs-only* (every path under `docs/`) or
       *health-history* (head branch `health-history`, changing only
       `docs/health/history.csv` and `docs/health/trend.svg`). Refactors stay
       founder-approved until a Replay check runs in CI.
    5. **Every check on the head sha passed:** each check run and commit
       status is completed as success, skipped or neutral, and `Test` passed.

  Anything else is the normal lane: a founder approves and merges. The
  classification comes from the diff, never from the PR's title or the bot's
  word. Like `TalesForge.DeployLanes`, this module uses only Elixir's standard
  library, so the workflow loads it from `main` with plain `elixir`.

      iex> lanes = TalesForge.DeployLanes.parse("[admin]\\nlib/a.ex\\n[founder]\\nmix.lock\\n")
      iex> checks = [%{name: "Test", status: "completed", conclusion: "success"}]
      iex> input = %{files: [{"M", "docs/x.md"}], branch: "docs/x", labels: [], checks: checks}
      iex> TalesForge.DeployLanes.Auto.check(lanes, input).lane
      :auto
      iex> TalesForge.DeployLanes.Auto.check(lanes, %{input | files: [{"M", "mix.lock"}]}).lane
      :normal
  """

  alias TalesForge.DeployLanes

  @health_branch "health-history"
  @health_files ["docs/health/history.csv", "docs/health/trend.svg"]
  @user_visible "user-visible"
  @passed ["success", "skipped", "neutral"]
  @may_delete ["docs/", "test/"]

  @typedoc "One changed file: its `git diff --name-status` letter and path."
  @type file :: {status :: String.t(), path :: String.t()}

  @typedoc "One check run or commit status on the head sha."
  @type check :: %{name: String.t(), status: String.t(), conclusion: String.t() | nil}

  @typedoc "What `check/2` needs about the pull request."
  @type input :: %{
          files: [file()],
          branch: String.t(),
          labels: [String.t()],
          checks: [check()]
        }

  @typedoc "The auto class of a pull request, or `nil` when it has none."
  @type class :: :docs_only | :health_history | nil

  @typedoc "The decision: the lane, the class and every rule with its result."
  @type result :: %{
          lane: :auto | :normal,
          class: class(),
          rules: [TalesForge.DeployLanes.Security.rule()]
        }

  @doc "Decides the lane of a pull request from its diff, labels and checks."
  @spec check(DeployLanes.t(), input()) :: result()
  def check(lanes, input) do
    class = class(input)
    rules = path_rules(lanes, input) ++ [class_rule(class), checks_rule(input.checks)]
    lane = if Enum.all?(rules, & &1.ok), do: :auto, else: :normal
    %{lane: lane, class: if(lane == :auto, do: class), rules: rules}
  end

  @doc """
  The auto class the changed files and branch fit, before any other rule.

      iex> TalesForge.DeployLanes.Auto.class(%{files: [{"M", "docs/health/trend.svg"}], branch: "health-history"})
      :health_history
      iex> TalesForge.DeployLanes.Auto.class(%{files: [{"M", "docs/a.md"}, {"A", "lib/a.ex"}], branch: "x"})
      nil
  """
  @spec class(%{
          required(:files) => [file()],
          required(:branch) => String.t(),
          optional(atom()) => any()
        }) :: class()
  def class(%{files: []}), do: nil

  def class(%{files: files, branch: branch}) do
    paths = Enum.map(files, &elem(&1, 1))

    cond do
      branch == @health_branch and Enum.all?(paths, &(&1 in @health_files)) -> :health_history
      Enum.all?(paths, &String.starts_with?(&1, "docs/")) -> :docs_only
      true -> nil
    end
  end

  defp path_rules(lanes, %{files: files, labels: labels}) do
    founder = for {_status, path} <- files, DeployLanes.founder?(lanes, path), do: path

    deleted =
      for {"D", path} <- files,
          not Enum.any?(@may_delete, &String.starts_with?(path, &1)),
          do: path

    [
      rule("No founder file", "on `[founder]`", founder),
      rule("No deletion outside docs/ and test/", "deleted", deleted),
      label_rule(@user_visible in labels)
    ]
  end

  defp label_rule(true),
    do: %{name: "No `user-visible` label", ok: false, detail: "Labelled `user-visible`."}

  defp label_rule(false),
    do: %{name: "No `user-visible` label", ok: true, detail: "Not labelled `user-visible`."}

  defp rule(name, _what, []), do: %{name: name, ok: true, detail: "None."}

  defp rule(name, what, paths) do
    listed = paths |> Enum.take(10) |> Enum.map_join(", ", &"`#{&1}`")
    %{name: name, ok: false, detail: "#{length(paths)} #{what}: #{listed}"}
  end

  defp class_rule(:docs_only),
    do: %{name: "Auto class", ok: true, detail: "docs-only: every path is under `docs/`."}

  defp class_rule(:health_history),
    do: %{name: "Auto class", ok: true, detail: "health-history: only the two history files."}

  defp class_rule(nil),
    do: %{
      name: "Auto class",
      ok: false,
      detail: "Not docs-only or health-history (refactors wait for the Replay check)."
    }

  @doc """
  The checks rule: every check is completed as success, skipped or neutral,
  and `Test` is among them with success.

      iex> TalesForge.DeployLanes.Auto.checks_rule([%{name: "Test", status: "completed", conclusion: "success"}]).ok
      true
      iex> TalesForge.DeployLanes.Auto.checks_rule([%{name: "Test", status: "in_progress", conclusion: nil}]).ok
      false
  """
  @spec checks_rule([check()]) :: TalesForge.DeployLanes.Security.rule()
  def checks_rule(checks) do
    failing = Enum.reject(checks, &passed?/1)
    test_ok = Enum.any?(checks, &(&1.name == "Test" and &1.conclusion == "success"))

    detail =
      cond do
        failing != [] ->
          "Not passed: " <> Enum.map_join(failing, ", ", &"`#{&1.name}` (#{describe(&1)})") <> "."

        not test_ok ->
          "No passed `Test` check on the head sha."

        true ->
          "All #{length(checks)} checks passed (success or skipped)."
      end

    %{name: "Every check on the head sha passed", ok: failing == [] and test_ok, detail: detail}
  end

  defp passed?(%{status: "completed", conclusion: conclusion}), do: conclusion in @passed
  defp passed?(_check), do: false

  defp describe(%{status: "completed", conclusion: conclusion}), do: conclusion || "none"
  defp describe(%{status: status}), do: status
end
