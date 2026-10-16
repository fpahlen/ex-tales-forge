defmodule Mix.Tasks.Health.CheckTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Health.Check

  @limits %{"cyclomatic_complexity" => 9, "abc_size" => 30}

  defp numbers(opts \\ []) do
    %{
      "limits" => Keyword.get(opts, :limits, @limits),
      "cycles" => %{"all" => Keyword.get(opts, :cycles, [cycle(~w(a b c))])},
      "web_references" =>
        Keyword.get(opts, :refs, [
          %{"from" => "lib/ex_tales_forge/a.ex", "to" => ["lib/ex_tales_forge_web/e.ex"]}
        ]),
      "complex_functions" =>
        Keyword.get(opts, :funs, [
          %{"function" => "A.f", "cyclomatic_complexity" => 12, "abc_size" => 40}
        ])
    }
  end

  defp cycle(members), do: %{"size" => length(members), "members" => members}

  test "the same numbers pass" do
    assert Check.check(numbers(), numbers()) == []
  end

  describe "cycles" do
    test "a smaller cycle passes, a bigger one fails" do
      assert Check.check(numbers(), numbers(cycles: [cycle(~w(a b))])) == []
      assert [msg] = Check.check(numbers(), numbers(cycles: [cycle(~w(a b c d))]))
      assert msg =~ "new or bigger"
    end

    test "a new cycle and a higher count fail" do
      errors = Check.check(numbers(), numbers(cycles: [cycle(~w(a b c)), cycle(~w(x y))]))
      assert Enum.any?(errors, &(&1 =~ "cycles: 2, baseline 1"))
      assert Enum.any?(errors, &(&1 =~ "x, y"))
    end
  end

  describe "web references" do
    test "a removed reference passes, a new one fails" do
      assert Check.check(numbers(), numbers(refs: [])) == []

      refs = [
        %{
          "from" => "lib/ex_tales_forge/a.ex",
          "to" => ["lib/ex_tales_forge_web/e.ex", "lib/ex_tales_forge_web/f.ex"]
        }
      ]

      assert [msg] = Check.check(numbers(), numbers(refs: refs))
      assert msg =~ "lib/ex_tales_forge/a.ex -> lib/ex_tales_forge_web/f.ex"
    end
  end

  describe "complex functions" do
    test "fixed or lower scores pass" do
      assert Check.check(numbers(), numbers(funs: [])) == []
      lower = [%{"function" => "A.f", "cyclomatic_complexity" => 10}]
      assert Check.check(numbers(), numbers(funs: lower)) == []
    end

    test "a score above its ceiling fails" do
      worse = [%{"function" => "A.f", "cyclomatic_complexity" => 12, "abc_size" => 41}]
      assert [msg] = Check.check(numbers(), numbers(funs: worse))
      assert msg =~ "abc_size 41, ceiling 40"
    end

    test "a baseline function going over a limit it was under fails" do
      base = numbers(funs: [%{"function" => "A.f", "abc_size" => 40}])

      assert [msg] =
               Check.check(
                 base,
                 numbers(
                   funs: [%{"function" => "A.f", "abc_size" => 40, "cyclomatic_complexity" => 10}]
                 )
               )

      assert msg =~ "cyclomatic_complexity 10, ceiling 9"
    end

    test "a new function over the limits fails" do
      funs = [
        %{"function" => "A.f", "cyclomatic_complexity" => 12, "abc_size" => 40},
        %{"function" => "B.g", "abc_size" => 31}
      ]

      assert [msg] = Check.check(numbers(), numbers(funs: funs))
      assert msg =~ "B.g"
    end
  end

  describe "the baseline only shrinks" do
    test "removing entries and lowering ceilings passes" do
      assert Check.shrink_errors(
               numbers(),
               numbers(refs: [], funs: [%{"function" => "A.f", "abc_size" => 35}])
             ) == []
    end

    test "adding an entry, raising a ceiling or a limit fails" do
      grown =
        numbers(funs: [%{"function" => "A.f", "cyclomatic_complexity" => 13, "abc_size" => 40}])

      assert [msg] = Check.shrink_errors(numbers(), grown)
      assert msg =~ "baseline: A.f"

      assert [msg] =
               Check.shrink_errors(numbers(), numbers(limits: %{@limits | "abc_size" => 50}))

      assert msg =~ "limit abc_size raised"
    end

    test "no baseline at the base passes" do
      assert Check.shrink_errors(nil, numbers()) == []
    end
  end

  describe "parsing" do
    test "xref cycles" do
      out = """
      2 cycles found. Showing them in decreasing size:

      Cycle of length 3:

          lib/b.ex (compile)
          lib/a.ex
          lib/c.ex (export)

      Cycle of length 2:

          lib/x.ex
          lib/y.ex
      """

      assert Check.parse_cycles(out) == [
               cycle(~w(lib/a.ex lib/b.ex lib/c.ex)),
               cycle(~w(lib/x.ex lib/y.ex))
             ]
    end

    test "xref plain graph keeps only domain -> web references" do
      out = """
      lib/ex_tales_forge/a.ex
      |-- lib/ex_tales_forge/b.ex
      |-- lib/ex_tales_forge_web/e.ex (compile)
      `-- lib/ex_tales_forge_web/d.ex
      lib/ex_tales_forge_web/e.ex
      `-- lib/ex_tales_forge/a.ex
      """

      assert Check.parse_web_references(out) == [
               %{
                 "from" => "lib/ex_tales_forge/a.ex",
                 "to" => ["lib/ex_tales_forge_web/d.ex", "lib/ex_tales_forge_web/e.ex"]
               }
             ]
    end

    test "credo issues, one entry per function with its highest scores" do
      issues = [
        %{
          "scope" => "A.f",
          "filename" => "lib/a.ex",
          "check" => "Credo.Check.Refactor.ABCSize",
          "message" => "Function is too complex (ABC size is 35, max is 30)."
        },
        %{
          "scope" => "A.f",
          "filename" => "lib/a.ex",
          "check" => "Credo.Check.Refactor.ABCSize",
          "message" => "Function is too complex (ABC size is 37, max is 30)."
        },
        %{
          "scope" => "A.f",
          "filename" => "lib/a.ex",
          "check" => "Credo.Check.Refactor.CyclomaticComplexity",
          "message" => "Function is too complex (cyclomatic complexity is 11, max is 9)."
        }
      ]

      assert Check.parse_credo(issues) == [
               %{
                 "function" => "A.f",
                 "file" => "lib/a.ex",
                 "abc_size" => 37,
                 "cyclomatic_complexity" => 11
               }
             ]
    end
  end
end
