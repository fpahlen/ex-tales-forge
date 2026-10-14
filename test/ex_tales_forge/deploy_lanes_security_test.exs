defmodule TalesForge.DeployLanes.SecurityTest do
  use ExUnit.Case, async: true

  alias TalesForge.DeployLanes
  alias TalesForge.DeployLanes.Security
  alias TalesForge.DeployLanes.SecurityCLI

  doctest TalesForge.DeployLanes.Security
  doctest TalesForge.DeployLanes.SecurityCLI

  @dir Path.expand("../fixtures/security_lane", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@dir, name))

  defp input(overrides \\ []) do
    Map.merge(
      %{
        files: ["mix.lock"],
        old_lock: fixture("base.lock"),
        new_lock: fixture("minor.lock"),
        old_mix_exs: fixture("mix_base.exs"),
        new_mix_exs: fixture("mix_base.exs"),
        title: "security: EEF-CVE-2026-97853: decimal 3.1.1 -> 3.2.0",
        body: "",
        labels: ["security"],
        ci_green: true
      },
      Map.new(overrides)
    )
  end

  defp failed(result), do: for(r <- result.rules, not r.ok, do: r.name)

  describe "check/1 qualifies" do
    test "a lock-only minor bump with the label and an advisory id" do
      result = Security.check(input())
      assert result.lane == :security
      assert failed(result) == []

      assert [%{package: "decimal", from: "3.1.1", to: "3.2.0", same_major: true}] =
               result.changes
    end

    test "the title prefix without the label, the advisory id in the body" do
      result =
        Security.check(
          input(labels: [], title: "Security: bump decimal", body: "Fixes GHSA-5chx-gg25-v37m.")
        )

      assert result.lane == :security
    end

    test "a version pin in mix.exs next to the lock" do
      result =
        Security.check(input(files: ["mix.exs", "mix.lock"], new_mix_exs: fixture("mix_pin.exs")))

      assert result.lane == :security
    end
  end

  describe "check/1 falls back to normal" do
    test "a major bump" do
      result = Security.check(input(new_lock: fixture("major.lock")))
      assert result.lane == :normal
      assert failed(result) == ["Every package stays within its major version"]
    end

    test "a 0.x minor bump counts as a major bump" do
      result = Security.check(input(new_lock: fixture("zero_minor.lock")))
      assert result.lane == :normal
      assert failed(result) == ["Every package stays within its major version"]
    end

    test "a package added to the lock" do
      result = Security.check(input(new_lock: fixture("added.lock")))
      assert result.lane == :normal
      assert failed(result) == ["Every package stays within its major version"]
    end

    test "extra files" do
      result = Security.check(input(files: ["mix.lock", "lib/ex_tales_forge/game/turn.ex"]))
      assert result.lane == :normal
      assert failed(result) == ["Only mix.lock (and mix.exs pins) change"]
    end

    test "a new dep in mix.exs" do
      result =
        Security.check(
          input(files: ["mix.exs", "mix.lock"], new_mix_exs: fixture("mix_new_dep.exs"))
        )

      assert result.lane == :normal
      assert failed(result) == ["Only mix.lock (and mix.exs pins) change"]
    end

    test "mix.lock does not change" do
      result = Security.check(input(files: ["mix.exs"], new_lock: fixture("base.lock")))
      assert result.lane == :normal
    end

    test "no label and no title prefix" do
      result = Security.check(input(labels: [], title: "Bump decimal (EEF-CVE-2026-97853)"))
      assert result.lane == :normal
      assert failed(result) == ["It references an advisory"]
    end

    test "the label without an advisory id" do
      result = Security.check(input(title: "security: bump decimal", body: "Routine bump."))
      assert result.lane == :normal
      assert failed(result) == ["It references an advisory"]
    end

    test "CI is not green" do
      result = Security.check(input(ci_green: false))
      assert result.lane == :normal
      assert failed(result) == ["CI is green"]
    end
  end

  test "advisory_ids/1 finds CVE, GHSA and EEF-CVE ids" do
    assert Security.advisory_ids("CVE-2025-1234, ghsa-5chx-gg25-v37m and EEF-CVE-2026-97853") ==
             ["CVE-2025-1234", "GHSA-5CHX-GG25-V37M", "EEF-CVE-2026-97853"]
  end

  test "parse_lock/1 reads the repo's own mix.lock" do
    lock = Security.parse_lock(File.read!("mix.lock"))
    assert is_binary(lock["phoenix"])
    assert String.starts_with?(lock["heroicons"], "git:")
  end

  describe "SecurityCLI" do
    # A fake git over two commits: "base" and "head".
    defp git(files, trees) do
      fn
        ["merge-base", "--is-ancestor", _, _] ->
          {"", 0}

        ["merge-base", _, _] ->
          {"base\n", 0}

        ["diff", "--name-only", "--no-renames", _, _] ->
          {Enum.join(files, "\n"), 0}

        ["show", rev_path] ->
          [rev, path] = String.split(rev_path, ":", parts: 2)

          case get_in(trees, [rev, path]) do
            nil -> {"fatal: no such path", 128}
            text -> {text, 0}
          end
      end
    end

    @trees %{
      "base" => %{
        "mix.lock" => File.read!(Path.expand("../fixtures/security_lane/base.lock", __DIR__))
      },
      "head" => %{
        "mix.lock" => File.read!(Path.expand("../fixtures/security_lane/minor.lock", __DIR__))
      }
    }

    @pr %{
      "title" => "security: EEF-CVE-2026-97853",
      "body" => "",
      "labels" => [%{"name" => "security"}]
    }

    test "decide_pr/5: a lock-only minor bump qualifies, the summary lists the rules" do
      result = SecurityCLI.decide_pr("main", "head", @pr, true, git(["mix.lock"], @trees))
      assert result.lane == :security
      assert result.advisories == ["EEF-CVE-2026-97853"]
      assert Enum.count(result.summary, &String.starts_with?(&1, "- PASS")) == 4
    end

    test "decide_pr/5: extra files fall back to normal with the reason" do
      result =
        SecurityCLI.decide_pr("main", "head", @pr, true, git(["mix.lock", "README.md"], @trees))

      assert result.lane == :normal
      assert Enum.any?(result.summary, &(&1 =~ "FAIL" and &1 =~ "README.md"))
    end

    test "since_production/4: an unreleased game change keeps production in the normal lane" do
      lanes = DeployLanes.load()
      trees = %{"prod" => @trees["base"], "head" => @trees["head"]}

      ok =
        SecurityCLI.since_production(
          lanes,
          "head",
          "prod",
          git(["mix.lock", "lib/ex_tales_forge_web/live/admin/costs_live.ex"], trees)
        )

      assert ok.ok

      bad =
        SecurityCLI.since_production(
          lanes,
          "head",
          "prod",
          git(["mix.lock", "lib/ex_tales_forge/game/turn.ex"], trees)
        )

      refute bad.ok
      assert bad.detail =~ "lib/ex_tales_forge/game/turn.ex"

      refute SecurityCLI.since_production(lanes, "head", nil, git([], trees)).ok
    end

    test "extract_json/1 takes the deps.audit report out of mixed output (run 38154907517)" do
      out = fixture("deps_audit_mixed.out")
      assert {:ok, json} = SecurityCLI.extract_json(out)
      assert %{"pass" => false, "vulnerabilities" => [vuln]} = SecurityCLI.decode_pr(json)
      assert vuln["advisory"]["id"] == "GHSA-5chx-gg25-v37m"
    end

    test "extract_json/1: clean JSON as is; compile output alone or a cut-off report is :error" do
      assert SecurityCLI.extract_json(~s({"pass":true,"vulnerabilities":[]})) ==
               {:ok, ~s({"pass":true,"vulnerabilities":[]})}

      assert SecurityCLI.extract_json("==> jido_tools\nwarning: {x}\n") == :error
      assert SecurityCLI.extract_json(~s({"pass":true,"vulnerabilities":[)) == :error
      assert SecurityCLI.extract_json(~s({"pass":true})) == :error
    end

    test "decode_pr/1 reads gh's JSON (escapes, unicode, nesting)" do
      json =
        ~s({"body":"a\\nb \\u00e5 \\ud83d\\ude00","labels":[{"name":"security"}],"n":12,"x":null,"t":true})

      assert SecurityCLI.decode_pr(json) == %{
               "body" => "a\nb å 😀",
               "labels" => [%{"name" => "security"}],
               "n" => 12,
               "x" => nil,
               "t" => true
             }
    end
  end
end
