defmodule TalesForge.DeployLanes.AutoTest do
  use ExUnit.Case, async: true

  alias TalesForge.DeployLanes
  alias TalesForge.DeployLanes.Auto
  alias TalesForge.DeployLanes.AutoCLI

  doctest TalesForge.DeployLanes.Auto

  @lanes DeployLanes.load()

  @green [
    %{name: "Changed files", status: "completed", conclusion: "success"},
    %{name: "Test", status: "completed", conclusion: "success"},
    %{name: "Dialyzer", status: "completed", conclusion: "skipped"}
  ]

  defp input(files, opts) do
    %{
      files: files,
      branch: Keyword.get(opts, :branch, "docs/x"),
      labels: Keyword.get(opts, :labels, []),
      checks: Keyword.get(opts, :checks, @green)
    }
  end

  defp lane(files, opts \\ []), do: Auto.check(@lanes, input(files, opts))

  defp failed(result), do: for(r <- result.rules, not r.ok, do: r.name)

  describe "the [founder] list in .github/deploy-lanes.txt" do
    test "forces founder review for migrations, data, SQL, deps, deploy config and CI" do
      for path <- [
            "priv/repo/migrations/20261018120000_character_lifetime.exs",
            "priv/repo/seeds.exs",
            "priv/adventures/tin_valley/pack.yaml",
            "priv/npcs/brenna.md",
            "scripts/backfill.sql",
            "mix.exs",
            "mix.lock",
            "fly.toml",
            "fly.playtest.toml",
            "Dockerfile",
            "rel/overlays/bin/migrate",
            "config/runtime.exs",
            ".github/workflows/security-lane.yml",
            ".github/deploy-lanes.txt",
            "docs/decisions.md"
          ] do
        assert DeployLanes.founder?(@lanes, path), path
      end
    end

    test "leaves docs, code and tests to the other rules" do
      for path <- [
            "docs/architecture.md",
            "docs/health/history.csv",
            "lib/ex_tales_forge/npc.ex",
            "test/x_test.exs"
          ] do
        refute DeployLanes.founder?(@lanes, path), path
      end
    end

    test "says nothing about deploy lanes" do
      assert DeployLanes.classify(@lanes, ["mix.lock"]).lane == :normal
      refute DeployLanes.admin?(@lanes, "docs/decisions.md")
    end
  end

  describe "auto classes" do
    test "docs-only is auto" do
      result = lane([{"M", "docs/architecture.md"}, {"A", "docs/playtest/run.md"}])
      assert %{lane: :auto, class: :docs_only} = result
    end

    test "deleting or renaming inside docs/ is still docs-only" do
      assert lane([{"D", "docs/old.md"}, {"A", "docs/new.md"}]).lane == :auto
    end

    test "health-history on its branch with only the two files" do
      files = [{"M", "docs/health/history.csv"}, {"M", "docs/health/trend.svg"}]
      assert %{lane: :auto, class: :health_history} = lane(files, branch: "health-history")
    end

    test "docs/decisions.md needs a founder, even in a docs-only PR" do
      result = lane([{"M", "docs/decisions.md"}, {"M", "docs/a.md"}])
      assert result.lane == :normal
      assert failed(result) == ["No founder file"]
    end

    test "code, even a refactor, needs a founder (no Replay check yet)" do
      result = lane([{"M", "lib/ex_tales_forge/npc.ex"}, {"M", "docs/a.md"}])
      assert result.lane == :normal
      assert failed(result) == ["Auto class"]
    end

    test "a test-only change needs a founder" do
      assert lane([{"M", "test/ex_tales_forge/npc_test.exs"}]).lane == :normal
    end

    test "an empty diff needs a founder" do
      assert %{lane: :normal, class: nil} = lane([])
    end

    test "a deletion outside docs/ and test/ is named" do
      result = lane([{"D", "lib/ex_tales_forge/jido.ex"}])
      assert "No deletion outside docs/ and test/" in failed(result)
    end

    test "a migration is named, whatever else changes" do
      result = lane([{"A", "priv/repo/migrations/1_x.exs"}])
      assert "No founder file" in failed(result)
    end
  end

  describe "the user-visible label" do
    test "adds founder review to a docs-only PR" do
      result = lane([{"M", "docs/a.md"}], labels: ["user-visible"])
      assert result.lane == :normal
      assert failed(result) == ["No `user-visible` label"]
    end

    test "other labels change nothing" do
      assert lane([{"M", "docs/a.md"}], labels: ["auto", "docs"]).lane == :auto
    end

    test "can never remove founder review" do
      assert lane([{"M", "mix.lock"}], labels: ["auto"]).lane == :normal
    end
  end

  describe "checks on the head sha" do
    test "a failed check blocks" do
      checks =
        @green ++ [%{name: "Dependency warnings", status: "completed", conclusion: "failure"}]

      assert failed(lane([{"M", "docs/a.md"}], checks: checks)) == [
               "Every check on the head sha passed"
             ]
    end

    test "a pending check blocks" do
      checks = @green ++ [%{name: "Dialyzer", status: "in_progress", conclusion: nil}]
      assert lane([{"M", "docs/a.md"}], checks: checks).lane == :normal
    end

    test "a cancelled check blocks" do
      checks = [%{name: "Test", status: "completed", conclusion: "cancelled"}]
      assert lane([{"M", "docs/a.md"}], checks: checks).lane == :normal
    end

    test "no Test check blocks" do
      checks = [%{name: "Changed files", status: "completed", conclusion: "success"}]
      rule = Auto.checks_rule(checks)
      refute rule.ok
      assert rule.detail =~ "No passed `Test`"
    end

    test "a skipped Test does not count as passed" do
      checks = [%{name: "Test", status: "completed", conclusion: "skipped"}]
      refute Auto.checks_rule(checks).ok
    end
  end

  describe "AutoCLI" do
    test "reads labels, branch and checks from gh's JSON" do
      pr = %{"headRefName" => "health-history", "labels" => [%{"name" => "user-visible"}]}
      checks = [%{"name" => "Test", "status" => "completed", "conclusion" => "success"}]

      assert %{branch: "health-history", labels: ["user-visible"], checks: [%{name: "Test"}]} =
               AutoCLI.input(pr, [], checks)
    end

    test "splits git diff --name-status into status and path" do
      git = fn ["diff", "--name-status", "--no-renames", "a", "b"] ->
        {"M\tdocs/a.md\nD\tlib/x.ex\nA\tdocs/b c.md\n", 0}
      end

      assert AutoCLI.changed_files(git, "a", "b") ==
               [{"M", "docs/a.md"}, {"D", "lib/x.ex"}, {"A", "docs/b c.md"}]
    end

    test "a failing git diff raises" do
      assert_raise RuntimeError, ~r/git diff/, fn ->
        AutoCLI.changed_files(fn _ -> {"fatal: bad revision", 128} end, "a", "b")
      end
    end

    test "warns when a founder PR does not start with the decision line" do
      result = lane([{"M", "lib/x.ex"}])
      assert Enum.any?(AutoCLI.summary(result, %{"body" => "Some PR"}), &(&1 =~ "::warning::"))

      refute Enum.any?(
               AutoCLI.summary(result, %{"body" => "What you're deciding: x"}),
               &(&1 =~ "::warning::")
             )
    end

    test "the dry-run table classifies merged PRs from their merge commits" do
      git = fn
        ["diff", "--name-status", "--no-renames", "m1^1", "m1"] ->
          {"M\tdocs/a.md\n", 0}

        ["diff", "--name-status", "--no-renames", "m2^1", "m2"] ->
          {"A\tpriv/repo/migrations/1.exs\n", 0}
      end

      checks = [%{"name" => "Test", "status" => "completed", "conclusion" => "success"}]

      prs = [
        %{
          "number" => 1,
          "title" => "docs | a",
          "mergeCommit" => %{"oid" => "m1"},
          "checks" => checks
        },
        %{
          "number" => 2,
          "title" => "migration",
          "mergeCommit" => %{"oid" => "m2"},
          "checks" => checks
        }
      ]

      table = AutoCLI.history_table(@lanes, prs, git)
      assert table =~ "| #1 | docs \\| a | **auto** (docs-only) | every rule passes |"
      assert table =~ "| #2 | migration | founder | No founder file"
    end
  end
end
