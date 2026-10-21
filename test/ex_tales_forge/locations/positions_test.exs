defmodule TalesForge.Locations.PositionsTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Schemas.{GMStructuredResponse, PlayerAction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Positions
  alias TalesForge.Schemas.GameSession
  alias TalesForge.Schemas.WorldState

  doctest TalesForge.Locations.Positions.Json

  @door %Position{grid_id: "valley_inn", cell: {9, 0, 0}, facing: :s}

  describe "the world_state boundary" do
    test "positions round-trip as %Position{} structs" do
      at_bar = %Position{grid_id: "valley_inn", cell: {7, 1, 0}, facing: :w}
      {:ok, dumped} = WorldState.dump(%{"positions" => %{"pc" => at_bar}})

      assert dumped["positions"]["pc"] == %{
               "grid_id" => "valley_inn",
               "cell" => [7, 1, 0],
               "facing" => "w"
             }

      assert {:ok, %{"positions" => %{"pc" => ^at_bar}}} = WorldState.load(dumped)
    end

    test "a stored position with a missing field fails loudly" do
      assert_raise ArgumentError, ~r/bad stored position/, fn ->
        WorldState.load(%{"positions" => %{"pc" => %{"grid_id" => "valley_inn"}}})
      end
    end

    test "a position encodes as JSON" do
      assert Jason.encode!(@door) =~ ~s("cell":[9,0,0])
    end
  end

  describe "settle/3" do
    setup do: %{grids: Pack.grids("tin_valley")}

    test "a character in a place with a grid starts on the main door, facing in", %{grids: grids} do
      world = Positions.settle(%{}, grids, {"pc", "valley_inn"})
      assert Positions.get(world, "pc") == @door
    end

    test "a stored position on the place's grid is kept", %{grids: grids} do
      at_bar = %Position{@door | cell: {7, 1, 0}, facing: :w}
      world = Positions.put(%{}, "pc", at_bar)

      assert world |> Positions.settle(grids, {"pc", "valley_inn"}) |> Positions.get("pc") ==
               at_bar
    end

    test "a place with no grid drops the position", %{grids: grids} do
      world = Positions.put(%{}, "pc", @door)

      assert world |> Positions.settle(grids, {"pc", "market_square"}) |> Positions.get("pc") ==
               nil
    end
  end

  describe "a turn with LOCATION_GRID" do
    test "a new session starts on the main door and the position persists across turns" do
      {:ok, session} = GameSessions.create_session(%{name: "Grid", adventure_id: "tin_valley"})
      id = session.world_state["character"]["id"]

      play(session, 1, true)
      stored = Repo.get!(GameSession, session.id)
      assert %Position{} = pos = Positions.get(stored.world_state, id)
      assert pos == @door

      turned = Positions.put(stored.world_state, id, %Position{pos | facing: :e})
      stored |> GameSession.changeset(%{world_state: turned}) |> Repo.update!()

      assert Positions.get(Repo.get!(GameSession, session.id).world_state, id).facing == :e
      play(Repo.get!(GameSession, session.id), 2, true)
      assert Positions.get(Repo.get!(GameSession, session.id).world_state, id).facing == :e
    end

    test "with the flag off no position is stored" do
      {:ok, session} = GameSessions.create_session(%{name: "Grid", adventure_id: "tin_valley"})
      play(session, 1, false)
      refute Map.has_key?(Repo.get!(GameSession, session.id).world_state, "positions")
    end
  end

  defp play(session, number, on?) do
    adapters = %Turn.Adapters{
      gm: fn _call -> {:ok, %GMStructuredResponse{narrative: "The fire crackles."}} end,
      stream: fn _id, _chunk -> :ok end
    }

    action = %PlayerAction{
      overall_intent: "look around",
      action: %SingleAction{action_type: :observe, target: nil}
    }

    flags = Map.put(Turn.read_flags(), :location_grid, on?)

    {TalesForge.Characters.put_sheet(session), number}
    |> Turn.new({"look around", action}, flags: flags, role: :playtest, adapters: adapters)
    |> Turn.Premise.check()
    |> Turn.Mechanics.apply()
    |> Turn.Reactions.react()
    |> Turn.Place.settle()
    |> Turn.Prompt.build()
    |> Turn.Gm.narrate()
    |> Turn.Outcome.persist()
  end
end
