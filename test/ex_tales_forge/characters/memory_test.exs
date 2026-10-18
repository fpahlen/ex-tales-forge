defmodule TalesForge.Characters.MemoryTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Characters
  alias TalesForge.Characters.{Memory, Moment}
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, SessionEvent}

  doctest Memory

  test "a pack interests list replaces the defaults" do
    c = %Character{definition: %{"interests" => ["ore"]}, ocean: nil, concerns: []}
    assert Memory.interests(c) == ["ore"]
  end

  test "scene end: travel gives the place left, a long rest the place of rest" do
    assert Memory.scene_end([%{"kind" => "player.travel", "payload" => %{"from" => "inn"}}]) ==
             "inn"

    rest = %{"kind" => "time.passed", "location_id" => "inn", "payload" => %{"delta_ticks" => 40}}
    assert Memory.scene_end([rest]) == "inn"
    short = put_in(rest, ["payload", "delta_ticks"], 1)
    assert Memory.scene_end([short]) == nil
  end

  test "off mode writes nothing" do
    assert Memory.on_turn(%Moment{session_id: Ecto.UUID.generate(), mode: :off}) == :ok
  end

  test "scene end writes short-term rows once, and recall finds them by association" do
    {:ok, session} = GameSessions.create_session(%{name: "Mem", adventure_id: "tin_valley"})
    [pc | _] = Characters.list_for_session(session.id) |> Enum.filter(&(&1.controller != "gm"))

    Repo.insert!(%SessionEvent{
      game_session_id: session.id,
      kind: "player.noticed",
      actor: "player",
      player_aware: true,
      tick: 5,
      location_id: "inn",
      payload: %{"item" => "lamp"}
    })

    travel = [%{"kind" => "player.travel", "payload" => %{"from" => "inn", "to" => "square"}}]
    moment = %Moment{session_id: session.id, events: travel, mode: :shadow, actor: pc.slug}
    assert :ok = Memory.on_turn(moment)
    assert :ok = Memory.on_turn(moment)

    pc = Repo.reload!(pc)
    [row] = Characters.list_memories(pc)
    assert row.tier == "short"
    assert "lamp" in row.about
    assert [_] = Memory.recall(pc, ["lamp"])
    assert [] = Memory.recall(pc, ["nothing"])
    assert Enum.any?(Memory.overview(session.id), &(&1.short == 1))
  end

  # Refactor 10e: who remembers comes from the turn's actor and the place,
  # never from who controls a character.
  test "the actor remembers what it saw wherever it went; the people there remember everything" do
    {:ok, session} = GameSessions.create_session(%{name: "Mem actor", adventure_id: "tin_valley"})
    chars = Characters.list_for_session(session.id)
    actor = Enum.find(chars, &(&1.slug == get_in(session.world_state, ["character", "id"])))
    [here, away | _] = Enum.reject(chars, &(&1.slug == actor.slug))

    here |> Ecto.Changeset.change(location_id: "inn") |> Repo.update!()
    away |> Ecto.Changeset.change(location_id: "square") |> Repo.update!()
    actor |> Ecto.Changeset.change(location_id: "square") |> Repo.update!()

    for {kind, aware?} <- [{"player.noticed", true}, {"npc.whisper", false}] do
      Repo.insert!(%SessionEvent{
        game_session_id: session.id,
        kind: kind,
        actor: "someone",
        player_aware: aware?,
        tick: 5,
        location_id: "inn",
        payload: %{"item" => "lamp"}
      })
    end

    travel = [%{"kind" => "player.travel", "payload" => %{"from" => "inn", "to" => "square"}}]

    assert :ok =
             Memory.on_turn(%Moment{
               session_id: session.id,
               events: travel,
               mode: :shadow,
               actor: actor.slug
             })

    kinds = fn c -> c |> Repo.reload!() |> Characters.list_memories() |> Enum.map(& &1.text) end
    assert [noticed] = kinds.(actor)
    assert noticed =~ "player.noticed"
    assert length(kinds.(here)) == 2
    assert kinds.(away) == []
  end
end
