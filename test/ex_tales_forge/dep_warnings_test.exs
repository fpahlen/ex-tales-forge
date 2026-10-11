defmodule TalesForge.DepWarningsTest do
  use ExUnit.Case, async: true

  alias TalesForge.DepWarnings

  doctest TalesForge.DepWarnings

  @dir Path.expand("../fixtures/dep_warnings", __DIR__)
  @known DepWarnings.parse_known(File.read!(".github/dep-warnings-known.txt"))

  defp fixture(name), do: File.read!(Path.join(@dir, name))

  test "parse_log/1 finds every warning of a real deps.compile log, with its package" do
    warnings = DepWarnings.parse_log(fixture("deps_compile.log"))

    assert Enum.frequencies_by(warnings, & &1.package) == %{
             "jido_action" => 6,
             "jido_signal" => 2,
             "oban" => 1
           }

    assert Enum.all?(warnings, &is_binary(&1.location))
  end

  test "the repo's known list marks the Lua and oban warnings as known; the local-only :public_key ones are new" do
    report =
      "deps_compile.log" |> fixture() |> DepWarnings.parse_log() |> DepWarnings.classify(@known)

    assert report.known |> Enum.map(fn {w, _} -> w.package end) |> Enum.frequencies() ==
             %{"jido_action" => 6, "oban" => 1}

    assert Enum.map(report.new, & &1.package) == ["jido_signal", "jido_signal"]
  end

  test "parse_log/1: Erlang warnings and a location without a package use the ==> header" do
    assert DepWarnings.parse_log(fixture("other.log")) == [
             %{
               package: "some_erl_dep",
               message: "variable 'X' is unused",
               location: "src/some_erl.erl:12:5"
             },
             %{
               package: "newdep",
               message: ~s(variable "x" is unused),
               location: "lib/newdep.ex:3:9: Newdep.f/1"
             }
           ]
  end

  test "a pattern of another package does not match" do
    known = DepWarnings.parse_known("oban | Lua | wrong package\n")

    [lua | _] =
      DepWarnings.parse_log(fixture("deps_compile.log"))
      |> Enum.filter(&(&1.package == "jido_action"))

    assert DepWarnings.classify([lua], known).new == [lua]
  end

  test "summary/1: new warnings first, known ones collapsed with their reasons" do
    report =
      "deps_compile.log" |> fixture() |> DepWarnings.parse_log() |> DepWarnings.classify(@known)

    text = DepWarnings.summary(report)

    assert text =~ ~r/\A### Dependency warnings: 2 NEW/
    assert text =~ "<details><summary>7 known warning(s), with reasons</summary>"
    assert text =~ "Reason: MySQL-only clause in Oban"
    assert text =~ "Reason: Optional dependency"

    {new_at, _} = :binary.match(text, "jido_signal")
    {known_at, _} = :binary.match(text, "<details>")
    assert new_at < known_at
  end

  test "summary/1 with no warnings" do
    assert DepWarnings.summary(%{new: [], known: []}) ==
             "### Dependency warnings: no new warnings\n\nNo known warnings.\n"
  end

  test "parse_known/1 skips comments (also after a space) and rejects a malformed line" do
    assert [%{package: "a", source: "x|y", reason: "why"}] =
             DepWarnings.parse_known("# comment\n\na | x|y | why # a trailing comment\n")

    assert_raise ArgumentError, ~r/line 1/, fn -> DepWarnings.parse_known("only-a-package\n") end

    assert_raise ArgumentError, ~r/line 1/, fn ->
      DepWarnings.parse_known("a | ( | bad regex\n")
    end
  end
end
