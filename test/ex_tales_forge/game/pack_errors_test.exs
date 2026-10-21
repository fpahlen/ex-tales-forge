defmodule TalesForge.Game.PackErrorsTest do
  @moduledoc """
  Characterization of `TalesForge.Game.Pack` before round 2 PR 5: the
  loaded packs (a hash of the whole map, from main) and every error message
  of `load/2`, `validate_graph!/2`, `validate_tree!/1` and
  `validate_positions!/1`, as exact strings.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Game.Pack

  describe "load/2" do
    test "the loaded packs are the same maps" do
      for {id, features, hash} <- [
            {"tin_valley", [], 84_403_725},
            {"tin_valley", ["inn_world"], 66_501_944},
            {"tin_valley", ["inn_world", "antagonist", "hierarchical_locations"], 37_802_592}
          ] do
        assert :erlang.phash2(Pack.load(id, features)) == hash, "#{id} #{inspect(features)}"
      end
    end

    test "a missing pack" do
      assert_raise ArgumentError, "adventure pack missing: no_such_pack", fn ->
        Pack.load("no_such_pack")
      end
    end

    test "a pack directory with no adventure.md" do
      error = assert_raise ArgumentError, fn -> Pack.load("generic-demo") end
      assert error.message =~ ~r{^adventure\.md missing in /.+/priv/adventures/generic-demo$}
    end

    test "an empty or non-binary id has no clause" do
      assert_raise FunctionClauseError, fn -> Pack.load("") end
      assert_raise FunctionClauseError, fn -> Pack.load(nil, []) end
    end
  end

  describe "validate_graph!/2" do
    @graph %{"inn" => %{"exits" => ["yard"], "door" => "yard"}, "yard" => %{"exits" => ["inn"]}}

    test "a good graph" do
      assert Pack.validate_graph!("inn", @graph) == :ok
    end

    test "the start is not a place" do
      assert_raise ArgumentError, ~s(starting_location_id "cellar" missing from locations), fn ->
        Pack.validate_graph!("cellar", @graph)
      end

      assert_raise ArgumentError, "starting_location_id nil missing from locations", fn ->
        Pack.validate_graph!(nil, @graph)
      end
    end

    test "an exit to no place" do
      graph = put_in(@graph, ["yard", "exits"], ["inn", "well"])

      assert_raise ArgumentError, ~s(location yard exit "well" missing from locations), fn ->
        Pack.validate_graph!("inn", graph)
      end
    end

    test "a door that is not an exit" do
      graph = put_in(@graph, ["yard", "door"], "gate")

      assert_raise ArgumentError, ~s(location yard door "gate" is not one of its exits), fn ->
        Pack.validate_graph!("inn", graph)
      end
    end

    test "a non-binary door is not checked" do
      assert Pack.validate_graph!("inn", put_in(@graph, ["yard", "door"], 7)) == :ok
    end
  end

  describe "validate_tree!/1" do
    test "a good tree, five places deep" do
      tree = %{
        "a" => %{},
        "b" => %{"parent" => "a"},
        "c" => %{"parent" => "b"},
        "d" => %{"parent" => "c"},
        "e" => %{"parent" => "d"}
      }

      assert Pack.validate_tree!(tree) == :ok
    end

    test "a chain of six places" do
      tree =
        Map.new(~w(a b c d e f), &{&1, %{}})
        |> Map.merge(%{
          "b" => %{"parent" => "a"},
          "c" => %{"parent" => "b"},
          "d" => %{"parent" => "c"},
          "e" => %{"parent" => "d"},
          "f" => %{"parent" => "e"}
        })

      assert_raise ArgumentError,
                   "location f: the parent chain has 6 places, more than 5",
                   fn -> Pack.validate_tree!(tree) end
    end

    test "a parent that is not a place id" do
      assert_raise ArgumentError, "location a: parent must be a place id, got 3", fn ->
        Pack.validate_tree!(%{"a" => %{"parent" => 3}})
      end
    end

    test "a parent missing from the places" do
      assert_raise ArgumentError, ~s(location b parent "x" missing from locations), fn ->
        Pack.validate_tree!(%{"a" => %{}, "b" => %{"parent" => "x"}})
      end
    end

    test "a loop, named from the place the chain starts at" do
      tree = %{"a" => %{"parent" => "b"}, "b" => %{"parent" => "c"}, "c" => %{"parent" => "a"}}

      assert_raise ArgumentError, "location a: the parent chain has a loop (a, b, c, a)", fn ->
        Pack.validate_tree!(tree)
      end
    end

    test "a place that is its own parent" do
      assert_raise ArgumentError, "location a: the parent chain has a loop (a, a)", fn ->
        Pack.validate_tree!(%{"a" => %{"parent" => "a"}})
      end
    end
  end

  describe "validate_positions!/1" do
    test "good positions" do
      places = %{
        "v" => %{"scale" => "region", "cell_m" => 100},
        "inn" => %{"parent" => "v", "at" => [1.5, 2], "scale" => "building", "cell_m" => 0.5}
      }

      assert Pack.validate_positions!(places) == :ok
    end

    test "at needs a parent" do
      assert_raise ArgumentError, "location inn: at needs a parent", fn ->
        Pack.validate_positions!(%{"inn" => %{"at" => [1, 2]}})
      end
    end

    test "at must be two numbers" do
      for {at, shown} <- [{[1], "[1]"}, {[1, "2"], ~s([1, "2"])}, {"1,2", ~s("1,2")}] do
        assert_raise ArgumentError, "location inn: at must be [x, y], got #{shown}", fn ->
          Pack.validate_positions!(%{"inn" => %{"parent" => "v", "at" => at}})
        end
      end
    end

    test "a bad scale" do
      assert_raise ArgumentError,
                   ~s(location inn: scale must be building, settlement or region, got "room"),
                   fn -> Pack.validate_positions!(%{"inn" => %{"scale" => "room"}}) end
    end

    test "a bad cell_m" do
      for {cell, shown} <- [{0, "0"}, {-1, "-1"}, {"5", ~s("5")}] do
        assert_raise ArgumentError,
                     "location inn: cell_m must be a positive number, got #{shown}",
                     fn -> Pack.validate_positions!(%{"inn" => %{"cell_m" => cell}}) end
      end
    end

    test "at is checked before scale, scale before cell_m" do
      assert_raise ArgumentError, "location inn: at needs a parent", fn ->
        Pack.validate_positions!(%{"inn" => %{"at" => [1, 2], "scale" => "room", "cell_m" => 0}})
      end

      assert_raise ArgumentError,
                   ~s(location inn: scale must be building, settlement or region, got "room"),
                   fn ->
                     Pack.validate_positions!(%{"inn" => %{"scale" => "room", "cell_m" => 0}})
                   end
    end
  end
end
