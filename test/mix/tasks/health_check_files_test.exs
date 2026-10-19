defmodule Mix.Tasks.Health.Check.FilesTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Health.Check
  alias Mix.Tasks.Health.Check.Files

  doctest Files

  describe "net over the touched files that exist on the base" do
    test "a net drop of 1 passes" do
      assert Files.errors(%{"lib/a.ex" => 100, "lib/b.ex" => 50}, %{
               "lib/a.ex" => 99,
               "lib/b.ex" => 50
             }) == []
    end

    test "a flat net fails, naming the files and the numbers" do
      assert [msg] = Files.errors(%{"lib/a.ex" => 100}, %{"lib/a.ex" => 100})
      assert msg =~ "ABC 100, base 100 (0)"
      assert msg =~ "lib/a.ex 100 -> 100"
      assert msg =~ "PR description"
    end

    test "a net rise fails" do
      assert [msg] =
               Files.errors(%{"lib/a.ex" => 100, "lib/b.ex" => 50}, %{
                 "lib/a.ex" => 104,
                 "lib/b.ex" => 49
               })

      assert msg =~ "ABC 153, base 150 (+3)"
    end

    test "one file 5% worse passes when the net drops" do
      base = %{"lib/a.ex" => 100, "lib/b.ex" => 50}
      pr = %{"lib/a.ex" => 105, "lib/b.ex" => 44}
      assert Files.errors(base, pr) == []
      assert [note] = Files.worse(base, pr)
      assert note =~ "lib/a.ex got worse: ABC 105, base 100 (+5, +5%)"
      assert note =~ "PR description"
    end

    test "one file 11% worse fails on the cap even when the net drops" do
      base = %{"lib/a.ex" => 100, "lib/b.ex" => 50}
      assert [msg] = Files.errors(base, %{"lib/a.ex" => 111, "lib/b.ex" => 20})
      assert msg =~ "lib/a.ex: ABC 111, base 100 (+11, +11%), over the cap for one file"
      assert msg =~ "split it"
    end

    test "exactly 10% worse is within the cap" do
      base = %{"lib/a.ex" => 100, "lib/b.ex" => 50}
      assert Files.errors(base, %{"lib/a.ex" => 110, "lib/b.ex" => 30}) == []
    end

    test "a file at 0 may grow by 3 but not by 4" do
      base = %{"lib/a.ex" => 0, "lib/b.ex" => 50}
      assert Files.errors(base, %{"lib/a.ex" => 3, "lib/b.ex" => 40}) == []
      assert [msg] = Files.errors(base, %{"lib/a.ex" => 4, "lib/b.ex" => 40})
      assert msg =~ "lib/a.ex: ABC 4, base 0 (+4), over the cap for one file (+10%, at least +3)"
    end

    test "a deleted file counts as its base score taken away" do
      assert Files.errors(%{"lib/a.ex" => 100, "lib/old.ex" => 20}, %{"lib/a.ex" => 110}) == []
    end
  end

  describe "new files" do
    test "are left out of the net" do
      assert Files.errors(%{"lib/a.ex" => 100}, %{"lib/a.ex" => 99, "lib/new.ex" => 500}) == []
      assert Files.errors(%{}, %{"lib/new.ex" => 500}) == []
      assert Files.worse(%{}, %{"lib/new.ex" => 500}) == []
    end

    test "still keep to the per-function limits" do
      base = %{"limits" => %{"abc_size" => 30}, "cycles" => %{}, "web_references" => []}
      base = Map.put(base, "complex_functions", [])
      fun = %{"function" => "New.f", "file" => "lib/new.ex", "abc_size" => 31}

      assert [msg] = Check.check(base, Map.put(base, "complex_functions", [fun]))
      assert msg =~ "new function over the complexity limits: New.f (lib/new.ex)"
    end
  end
end
