defmodule TalesForge.Game.HierarchicalLocationsTest do
  @moduledoc "Hierarchical locations (board card 7aba0394): the place tree, movement and pack checks."
  use ExUnit.Case, async: true

  alias TalesForge.Game.{Features, Movement, Pack}

  doctest TalesForge.Game.Pack, only: [validate_tree!: 1]

  @tree "hierarchical_locations"

  defp world(features), do: Pack.materialize("tin_valley", features)

  describe "the Tin Valley pack" do
    test "the place files hold the tree, and world_agents.json has no parent" do
      parents = Pack.parents("tin_valley")

      assert parents["valley_inn"] == "tin_valley_village"
      assert parents["tin_valley_village"] == "tin_valley_region"
      assert parents["tin_valley_region"] == nil
      assert parents["orc_nest"] == "orc_approach"
      assert parents["inn_yard"] == "tin_valley_village"

      raw =
        Path.join([:code.priv_dir(:ex_tales_forge), "adventures/tin_valley/world_agents.json"])
        |> File.read!()
        |> Jason.decode!()

      refute Enum.any?(raw["locations"], &Map.has_key?(&1, "parent"))
    end

    test "without the feature the session has no areas and the same exits" do
      w = world([])
      refute Map.has_key?(w["locations"], "tin_valley_village")
      refute Map.has_key?(w["locations"], "tin_valley_region")
      assert Movement.exits(w, "valley_inn") == ["market_square"]
      assert Movement.way_out(w, "market_square") == nil
    end

    test "with the feature the areas are places and link to their children" do
      w = world([@tree])
      assert Map.has_key?(w["locations"], "tin_valley_village")
      assert Features.on?(w, @tree)
      assert Movement.exits(w, "valley_inn") == ["market_square", "tin_valley_village"]
      assert "valley_inn" in Movement.exits(w, "tin_valley_village")
    end
  end

  describe "movement with the tree" do
    setup do: {:ok, w: world([@tree])}

    test "leave uses the only exit, then the parent", %{w: w} do
      assert Movement.way_out(w, "valley_inn") == "market_square"
      assert Movement.way_out(w, "market_square") == "tin_valley_village"
      assert Movement.way_out(w, "tin_valley_village") == "tin_valley_region"
      assert Movement.way_out(w, "tin_valley_region") == nil
    end

    test "go in selects a child by name or the only child", %{w: w} do
      assert Movement.way_in(w, "tin_valley_village", "I go into the tavern") == "valley_inn"
      assert Movement.way_in(w, "tin_valley_village", "I go inside") == nil
      assert Movement.way_in(w, "orc_approach", "I go in") == "orc_nest"
    end

    test "travel goes up the tree and down again within 3 steps", %{w: w} do
      assert Movement.route(w, "valley_inn", "mine_workings") == {:ok, "mine_workings"}
      assert Movement.route(w, "valley_inn", "tin_valley_region") == {:ok, "tin_valley_region"}
    end

    test "checkpoints still stop travel", %{w: w} do
      assert Movement.route(w, "tin_valley_region", "orc_nest") == {:ok, "orc_approach"}
    end

    test "the intent step reads go out, go in and go back to the village", %{w: w} do
      ctx = fn here ->
        %{"location_id" => here, "places" => w["locations"], "features" => w["features"]}
      end

      assert TalesForge.Game.Intent.resolve_move_target("the village", ctx.("valley_inn")) ==
               {:ok, "tin_valley_village"}

      assert TalesForge.Game.Intent.resolve_move_target("Valley Inn", ctx.("tin_valley_region")) ==
               {:ok, "valley_inn"}
    end

    test "Jev sees the parent in the place candidates", %{w: w} do
      ctx = %{
        "location_id" => "market_square",
        "places" => w["locations"],
        "features" => w["features"],
        "exits" => Movement.exits(w, "market_square"),
        "exit_names" => %{"valley_inn" => "Valley Inn"}
      }

      texts = ctx |> TalesForge.Game.JevIntent.candidates() |> Enum.map(& &1.text)
      assert "Valley Inn (exit, in Tin Valley village)" in texts
    end
  end

  describe "validate_tree!/1" do
    test "a missing parent fails" do
      assert_raise ArgumentError, ~r/parent "nowhere" missing/, fn ->
        Pack.validate_tree!(%{"inn" => %{"parent" => "nowhere"}})
      end
    end

    test "a loop fails" do
      assert_raise ArgumentError, ~r/loop/, fn ->
        Pack.validate_tree!(%{
          "a" => %{"parent" => "b"},
          "b" => %{"parent" => "c"},
          "c" => %{"parent" => "a"}
        })
      end
    end

    test "a chain of more than 5 places fails" do
      deep =
        for n <- 1..6,
            into: %{},
            do: {"p#{n}", if(n > 1, do: %{"parent" => "p#{n - 1}"}, else: %{})}

      assert_raise ArgumentError, ~r/more than 5/, fn -> Pack.validate_tree!(deep) end
      assert Pack.validate_tree!(Map.delete(deep, "p6")) == :ok
    end
  end
end
