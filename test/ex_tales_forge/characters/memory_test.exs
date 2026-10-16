defmodule TalesForge.Characters.MemoryTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Characters
  alias TalesForge.Characters.Memory
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, SessionEvent}

  doctest Memory

  setup do
    on_exit(fn -> for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id) end)
    :ok
  end

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
    assert Memory.on_turn(Ecto.UUID.generate(), [], :off) == :ok
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
    assert :ok = Memory.on_turn(session.id, travel, :shadow)
    assert :ok = Memory.on_turn(session.id, travel, :shadow)

    pc = Repo.reload!(pc)
    [row] = Characters.list_memories(pc)
    assert row.tier == "short"
    assert "lamp" in row.about
    assert [_] = Memory.recall(pc, ["lamp"])
    assert [] = Memory.recall(pc, ["nothing"])
    assert Enum.any?(Memory.overview(session.id), &(&1.short == 1))
  end
end
