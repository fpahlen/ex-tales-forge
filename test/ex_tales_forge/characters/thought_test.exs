defmodule TalesForge.Characters.ThoughtTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Characters
  alias TalesForge.Characters.Thought
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.Repo
  alias TalesForge.Schemas.{AICall, Turn}

  doctest Thought

  setup do
    on_exit(fn -> for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id) end)
    {:ok, session} = GameSessions.create_session(%{name: "Thought", adventure_id: "tin_valley"})
    chars = Characters.list_for_session(session.id)
    pc = Enum.find(chars, &(&1.controller != "gm"))
    npc = Enum.find(chars, &(&1.controller == "gm"))
    %{session: session, pc: pc, npc: npc}
  end

  defp remember!(pc, about, weight) do
    {:ok, _} =
      Characters.add_memory(pc, %{
        kind: "memory",
        tier: "long",
        text: "warm: shared bread at the inn",
        about: [about],
        weight: weight,
        tick: 3
      })
  end

  @rest [%{"kind" => "time.passed", "location_id" => "inn", "payload" => %{"delta_ticks" => 40}}]

  test "off makes no call", %{session: session} do
    assert Thought.for_turn(session.id, @rest, %{}, 1, :off) == nil
    refute Repo.exists?(AICall)
  end

  test "a sleep trigger gives a sleep thought, logged as purpose thought", %{
    session: session,
    pc: pc
  } do
    remember!(pc, "inn", 1.0)
    thought = Thought.for_turn(session.id, @rest, %{"location_id" => "inn"}, 1, :shadow)
    assert thought["trigger"] == "sleep"
    refute Map.has_key?(thought, "about_name")
    assert String.length(thought["text"]) <= 220
    refute thought["text"] =~ ~r/\d/
    assert Repo.get_by!(AICall, purpose: "thought").call_type == "llm"
  end

  test "a person trigger beats a sleep trigger; one person thought per scene", %{
    session: session,
    pc: pc,
    npc: npc
  } do
    remember!(pc, npc.slug, 1.0)
    world = %{"location_id" => "inn", "present_npcs" => [npc.slug]}

    thought = Thought.for_turn(session.id, @rest, world, 1, :on)
    assert thought["trigger"] == "person"
    assert thought["about_name"] == npc.name

    Repo.insert!(%Turn{
      game_session_id: session.id,
      turn_number: 1,
      player_action: "x",
      narrative: "y",
      thought: thought
    })

    assert Thought.for_turn(session.id, [], world, 2, :on) == nil
    assert Thought.for_turn(session.id, @rest, world, 2, :on)["trigger"] == "sleep"
  end

  test "no memory, no thought", %{session: session} do
    assert Thought.for_turn(session.id, @rest, %{}, 1, :on) == nil
  end

  test "a long text is cut to 220 characters" do
    long = String.duplicate("soft ", 80)
    assert String.length(Thought.clean(long)) <= 220
  end

  test "the transcript shows a stored thought after its GM entry only with the flag on", %{
    session: session
  } do
    Repo.insert!(%Turn{
      game_session_id: session.id,
      turn_number: 1,
      player_action: "sleep",
      narrative: "You sleep.",
      thought: %{"text" => "The day sits softly with me.", "trigger" => "sleep"}
    })

    old = System.get_env("CHARACTER_MEMORY")

    on_exit(fn ->
      if old,
        do: System.put_env("CHARACTER_MEMORY", old),
        else: System.delete_env("CHARACTER_MEMORY")
    end)

    load = fn -> session.id |> GameSessions.get_session!() |> Repo.preload([:turns, :scenes]) end

    System.put_env("CHARACTER_MEMORY", "on")
    roles = load.() |> GameSessions.transcript() |> Enum.map(& &1.role)
    assert Enum.take(roles, -3) == ["player", "gm", "thought"]

    System.put_env("CHARACTER_MEMORY", "shadow")
    refute "thought" in (load.() |> GameSessions.transcript() |> Enum.map(& &1.role))
  end
end
