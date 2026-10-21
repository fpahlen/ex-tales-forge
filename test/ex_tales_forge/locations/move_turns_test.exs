defmodule TalesForge.Locations.MoveTurnsTest do
  @moduledoc """
  Moves through the real turn path (`TalesForge.Game.TurnProcessor.run/3`)
  with LOCATION_GRID and TURN_APPLY_OUTCOMES on: the intent is Jev's reading
  through `TalesForge.IntentJev.decide/1` (band, clarify step and validation
  against the session's intent context), as in `TalesForge.GameSessions`.
  Playtest sessions 9747d773 and 39fcbc9d (2026-10-21).
  """

  use TalesForge.DataCase, async: false

  import Ecto.Query
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.{Context, JevIntent}
  alias TalesForge.Game.Schemas.PlayerAction
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameSessions
  alias TalesForge.IntentJev
  alias TalesForge.IntentJev.Read
  alias TalesForge.Locations.{Grid, Pack, Position, Positions}
  alias TalesForge.Schemas.{GameSession, SessionEvent}

  doctest TalesForge.Locations.Destination
  doctest TalesForge.Locations.NoMove
  doctest TalesForge.Locations.Named

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

  test "a refused move costs no time: the clock is the same before and after", %{id: id} do
    for {text, target} <- [
          {"I walk to the castle.", "market_square"},
          {"I walk to the dragon.", nil}
        ] do
      before = stored_world(id)["world_tick"]
      play(id, {text, :move, target})
      after_turn = stored_world(id)
      assert after_turn["location_id"] == "valley_inn", text
      assert after_turn["world_tick"] == before, text
    end
  end

  # Session 39fcbc9d turn 2: move to the bar desk, raw 0.41, move 0.89 /
  # interact 0.10; the band was clarify and nothing moved.
  @t2 %{confidence: 0.41, actions: %{move: 0.89, interact: 0.10}}
  # Session 39fcbc9d turn 5: move to the inn yard, raw 0.40, move 1.0.
  @t5 %{confidence: 0.40, actions: %{move: 1.0}}

  defp play(id, {text, type, target}), do: play(id, {text, type, target}, %{})

  # Jev's reading of `text` (action `type`, target the candidate `target`),
  # decided as in `TalesForge.GameSessions`, then played.
  defp play(id, {text, type, target}, recorded) do
    session = GameSessions.get_session!(id)
    context = Context.build_intent_context(session)
    candidates = JevIntent.candidates(context)
    cand = Enum.find(candidates, &(&1.id == target))

    reply = %{
      action: type,
      target: if(cand, do: cand.label, else: :none),
      skill: :none,
      later: :none,
      safety: :benign,
      confidence: %{action: recorded[:confidence] || 0.95, target: 0.9, safety: 0.97},
      probabilities: %{action: recorded[:actions] || %{type => 1.0}}
    }

    reading = JevIntent.decode(reply, candidates, text: text, context: context)

    {band, action, _gm, _meta} =
      IntentJev.decide(%Read{
        reading: reading,
        candidates: candidates,
        context: context,
        raw_action: text,
        latency_ms: 1
      })

    assert {:ok, _payload} = TurnProcessor.run(id, {text, PlayerAction.encode(action)})
    band
  end

  test "I go to the bar (39fcbc9d turn 2): the words name the bar desk, the PC walks there",
       %{id: id, pc: pc} do
    # The bar is offered once, as the spot (no "bar counter" fixture beside it).
    context = Context.build_intent_context(GameSessions.get_session!(id))
    refute Enum.any?(JevIntent.candidates(context), &(&1.kind == :fixture and &1.id =~ "bar"))

    assert play(id, {"I go to the bar.", :move, "bar desk"}, @t2) == :act

    pos = Positions.get(stored_world(id), pc)
    grid = Pack.grid(Pack.grids("tin_valley"), "valley_inn", 0)
    assert Grid.at(grid, Position.neighbour(pos.cell, pos.facing)).item == "bar desk"
  end

  test "back to the inn from the square (39fcbc9d turn 5) ends in the inn", %{id: id} do
    play(id, {"I flee out the door.", :move, "main door"})
    assert stored_world(id)["location_id"] == "market_square"

    assert play(id, {"I go back to the inn.", :move, "inn_yard"}, @t5) == :act
    assert stored_world(id)["location_id"] == "valley_inn"
  end

  test "after a clarify turn, walk to the dragon does not reuse Jev's old target",
       %{id: id, pc: pc} do
    assert play(id, {"I go over there.", :move, "bar desk"}, @t2) == :clarify
    before = Positions.get(stored_world(id), pc)

    play(id, {"I walk to the dragon.", :move, "bar desk"})

    assert Positions.get(stored_world(id), pc) == before
    assert stored_world(id)["location_id"] == "valley_inn"
    assert inspect(events(id)) =~ "You can't see a dragon here."
  end

  test "walk to the castle: the GM prompt has one note, the new one", %{id: id} do
    {:ok, prompts} = Agent.start_link(fn -> [] end)

    stub_llm(fn _kind, user, system ->
      Agent.update(prompts, &[system <> "\n" <> user | &1])
      :default
    end)

    play(id, {"I walk to the castle.", :move, "market_square"})
    prompt = Agent.get(prompts, &Enum.join(&1, "\n"))

    assert length(String.split(prompt, "There's no castle you know of.")) >= 2
    refute prompt =~ "There is no place called"
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
