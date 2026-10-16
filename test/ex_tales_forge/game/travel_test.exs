defmodule TalesForge.Game.TravelTest do
  @moduledoc "Travel time from the place tree (board card 7aba0394, PR 2)."
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{Pack, Travel}
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  doctest TalesForge.Game.Travel
  doctest TalesForge.Game.Pack, only: [validate_positions!: 1]

  @tree ["inn_world", "hierarchical_locations"]

  describe "Tin Valley positions" do
    setup do: {:ok, w: Pack.materialize("tin_valley", @tree)}

    test "steps inside the village cost no tick", %{w: w} do
      for {a, b} <- [
            {"valley_inn", "market_square"},
            {"valley_inn", "tin_valley_village"},
            {"inn_yard", "smithy"}
          ],
          do: assert(Travel.ticks(w, a, b) == 0, "#{a} -> #{b}")
    end

    test "travel at region scale costs ticks by distance", %{w: w} do
      assert Travel.ticks(w, "market_square", "mine_workings") == 1
      assert Travel.ticks(w, "valley_inn", "orc_approach") == 2

      assert Travel.minutes(w, "valley_inn", "orc_approach") >
               Travel.minutes(w, "valley_inn", "mine_workings")
    end

    test "the pack gives numbers for at and cell_m", %{w: w} do
      assert w["locations"]["west_road"]["at"] == [-4, 0]
      assert w["locations"]["west_road"]["cell_m"] == 200
      assert w["locations"]["tin_valley_region"]["scale"] == "region"
    end

    test "without the feature there is no travel time", %{w: w} do
      assert Travel.ticks(Map.delete(w, "features"), "valley_inn", "orc_approach") == nil
    end

    test "a place with no position keeps the old cost" do
      world = %{
        "features" => ["hierarchical_locations"],
        "locations" => %{"a" => %{}, "b" => %{}}
      }

      assert Travel.ticks(world, "a", "b") == nil
    end
  end

  describe "validate_positions!/1" do
    test "bad keys fail at load" do
      for {loc, msg} <- [
            {%{"parent" => "v", "at" => [1]}, ~r/at must be/},
            {%{"scale" => "planet"}, ~r/scale must be/},
            {%{"cell_m" => 0}, ~r/cell_m must be/}
          ] do
        assert_raise ArgumentError, msg, fn ->
          Pack.validate_positions!(%{"v" => %{}, "x" => loc})
        end
      end
    end
  end

  describe "a turn" do
    setup do
      previous =
        for k <- ~w(INN_WORLD HIERARCHICAL_LOCATIONS), into: %{}, do: {k, System.get_env(k)}

      on_exit(fn ->
        for {k, v} <- previous, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
        for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
      end)

      :ok
    end

    defp walk(env) do
      System.put_env("INN_WORLD", "on")
      System.put_env("HIERARCHICAL_LOCATIONS", env)
      {:ok, session} = GameSessions.create_session(%{adventure_id: "tin_valley"})
      before = session.world_state["world_tick"]
      {:ok, _} = GameSessions.submit_message(session.id, "I walk out to the market square.")
      world = Repo.get!(GameSession, session.id).world_state
      {world["location_id"], world["world_tick"] - before}
    end

    test "a short walk costs no tick with the feature, and one tick without" do
      assert walk("on") == {"market_square", 0}
      assert walk("off") == {"market_square", 1}
    end
  end
end
