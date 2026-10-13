defmodule Workflow.TeamTest do
  use ExUnit.Case, async: true

  alias Workflow.Team

  doctest Workflow.Team
  doctest Workflow.NameCheck

  describe "the team config in priv/team" do
    test "has every column label, a bot for each role and the founders" do
      team = Team.Source.team()

      for col <- ~w(ideas refining check building done parked archived),
          do: assert(is_binary(Team.label(team, col)), col)

      for role <- [:refiner, :builder, :checker], do: assert(is_atom(Team.bot(team, role)))
      assert length(team.founders) == 5
      assert Enum.all?(team.founders, &is_binary(&1.github))
    end

    test "has every text that the pages read" do
      team = Team.Source.team()

      for key <-
            ~w(hero.title team.intro wired.intro wired.sign_in call_types.learning art.alt.hero),
          do: assert(is_binary(Team.text(team, key)), key)
    end
  end

  describe "from_map/2" do
    test "stops on a missing role or a missing column label" do
      map = %{
        "product_name" => "P",
        "repo_url" => "https://example.com/o/p",
        "docs_repo" => "o/p-docs",
        "founders" => [],
        "bots" => [%{"id" => "a", "name" => "A", "role" => "refiner"}],
        "column_labels" => %{}
      }

      assert_raise ArgumentError, fn -> Team.from_map(map, %{}) end
    end
  end

  describe "the name check" do
    test "finds the team names in a Workflow file, and not in plain code" do
      team = Team.example()

      assert [%{path: "a.ex", line: 1, name: "Rita"}] =
               Workflow.NameCheck.findings(team, [{"a.ex", "# Rita works here"}])

      assert [%{path: "b.ex", line: 1}] =
               Workflow.NameCheck.findings(team, [{"b.ex", "x = :rita"}])

      assert [] = Workflow.NameCheck.findings(team, [{"c.ex", "@bram 1\nmap[\"ada\"]"}])
    end

    test "the Workflow lib/ files have no team names" do
      assert Mix.Task.rerun("workflow.check_names") == :ok
    end
  end
end
