defmodule TalesForge.Locations.MoveTurnsTest do
  @moduledoc """
  Moves through the real turn path (`TalesForge.Game.TurnProcessor.run/3`)
  with LOCATION_GRID and TURN_APPLY_OUTCOMES on: the intent is Jev's reading,
  validated against the session's intent context, as in
  `TalesForge.GameSessions`. Playtest session 9747d773 (2026-10-21).
  """

  use TalesForge.DataCase, async: false

  import Ecto.Query
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.Context
  alias TalesForge.Game.Intent
  alias TalesForge.Game.Schemas.{IntentExtraction, PlayerAction, SingleAction}
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameSessions
  alias TalesForge.Locations.{Grid, Pack, Position, Positions}
  alias TalesForge.Schemas.{GameSession, SessionEvent}

  doctest TalesForge.Locations.Destination

  setup do
    for flag <- ~w(LOCATION_GRID TURN_APPLY_OUTCOMES INN_WORLD WORLD_ANTAGONIST),
        do: System.put_env(flag, "on")

    on_exit(fn ->
      for flag <-
            ~w(LOCATION_GRID TURN_APPLY_OUTCOMES INN_WORLD WORLD_ANTAGONIST LLM_PROVIDER XAI_API_KEY),
          do: System.delete_env(flag)
    end)

    stub_llm(fn _kind, _user -> :default end)
    {:ok, session} = GameSessions.create_session(%{name: "Moves", adventure_id: "tin_valley"})
    %{id: session.id, pc: session.world_state["character"]["id"]}
  end

  test "walk to the hearth stores the PC's position next to it", %{id: id, pc: pc} do
    play(id, {"I walk over to the hearth.", :move, "open hearth"})

    assert %Position{grid_id: "valley_inn"} = pos = Positions.get(stored_world(id), pc)
    grid = Pack.grid(Pack.grids("tin_valley"), "valley_inn", 0)
    assert Grid.at(grid, Position.neighbour(pos.cell, pos.facing)).item == "open hearth"
  end

  test "flee out the door from the inn ends in the market square", %{id: id} do
    play(id, {"I flee out the door.", :move, "main door"})

    assert stored_world(id)["location_id"] == "market_square"
    assert travels(id) == [%{"from" => "valley_inn", "to" => "market_square"}]
  end

  test "walk back to the inn from the forge ends in the inn", %{id: id} do
    play(id, {"I go to the forge.", :move, "smithy"})
    assert stored_world(id)["location_id"] == "smithy"

    play(id, {"I walk back to the inn.", :move, "inn_yard"})
    assert stored_world(id)["location_id"] == "valley_inn"
  end

  test "walk to the castle from the inn: no move, and the GM is told", %{id: id} do
    play(id, {"I walk to the castle.", :move, "market_square"})

    assert stored_world(id)["location_id"] == "valley_inn"
    assert travels(id) == []
    assert inspect(events(id)) =~ "There's no castle you know of."
  end

  defp play(id, {text, type, target}) do
    session = GameSessions.get_session!(id)

    extraction = %IntentExtraction{
      overall_intent: text,
      actions: [%SingleAction{action_type: type, target: target, parameters: %{}}],
      confidence: 0.95
    }

    action = Intent.validate_player_action(extraction, Context.build_intent_context(session))
    assert {:ok, _payload} = TurnProcessor.run(id, {text, PlayerAction.encode(action)})
  end

  defp stored_world(id), do: Repo.get!(GameSession, id).world_state

  defp events(id),
    do:
      Repo.all(
        from e in SessionEvent, where: e.game_session_id == ^id, select: {e.kind, e.payload}
      )

  defp travels(id) do
    Repo.all(
      from e in SessionEvent,
        where: e.game_session_id == ^id and e.kind == "player.travel",
        select: e.payload
    )
  end
end
