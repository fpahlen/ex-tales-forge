defmodule TalesForge.Characters.CompressionTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Characters
  alias TalesForge.Characters.Compression
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.Repo
  alias TalesForge.Schemas.{AICall, CharacterMemory}

  doctest Compression

  setup do
    key = Application.get_env(:jev, :api_key)
    Application.put_env(:jev, :api_key, "test-key")

    on_exit(fn ->
      Application.put_env(:jev, :api_key, key)
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
    end)

    {:ok, session} = GameSessions.create_session(%{name: "Comp", adventure_id: "tin_valley"})
    [pc | _] = Enum.filter(Characters.list_for_session(session.id), &(&1.controller != "gm"))
    %{session: session, pc: pc}
  end

  defp short!(pc, text, about, tick, kind \\ "memory") do
    {:ok, row} =
      Characters.add_memory(pc, %{kind: kind, tier: "short", text: text, about: about, tick: tick})

    row
  end

  defp tiers(pc), do: pc |> Characters.list_memories() |> Enum.map(&{&1.tier, &1.text})

  describe "timing (option 4)" do
    test "a long rest is always due" do
      assert Compression.due?(
               %Compression.Trigger{long_rest: true, scene_end: false, now: 10},
               nil
             )
    end

    test "a scene end is due after a dawn and one game day" do
      refute Compression.due?(
               %Compression.Trigger{long_rest: false, scene_end: true, now: 50},
               10
             )

      refute Compression.due?(
               %Compression.Trigger{long_rest: false, scene_end: false, now: 200},
               10
             )

      assert Compression.due?(
               %Compression.Trigger{long_rest: false, scene_end: true, now: 110},
               10
             )

      refute Compression.due?(
               %Compression.Trigger{long_rest: false, scene_end: true, now: 110},
               nil
             )
    end
  end

  test "engine events stay out of the call" do
    assert Compression.engine?("turn.started")
    assert Compression.engine?("player.dawdled (delta_ticks: 2)")
    refute Compression.engine?("player.noticed (item: lamp)")
  end

  test "a long rest compresses: one Jev call, gists, beliefs, rows fade", %{
    session: session,
    pc: pc
  } do
    short!(pc, "Mags promised to help me with the debt of 12 coins", ["mags"], 5, "promise")
    short!(pc, "Mags laughed at the bar", ["mags"], 6)
    short!(pc, "turn.started", ["mags"], 6)
    short!(pc, "A crow sat on the fence", ["crow"], 7)

    Req.Test.stub(Jev.HTTP, fn conn ->
      {request, conn} = Jev.Test.request(conn)
      send(self(), {:jev_state, request["state"]})

      Jev.Test.respond(conn,
        a0_weight: 3.0,
        a0_feeling: :grateful,
        a0_belief: :ally,
        a0_key: :r0,
        a1_weight: 0.2,
        a1_feeling: :indifferent,
        a1_belief: :none
      )
    end)

    rest = [
      %{"kind" => "time.passed", "location_id" => "inn", "payload" => %{"delta_ticks" => 40}}
    ]

    assert :ok = Compression.after_turn(session.id, rest, now: 50, mode: :shadow)

    [long] = pc |> Characters.list_memories() |> Enum.filter(&(&1.tier == "long"))
    assert long.text =~ "grateful: "
    assert long.text =~ "promised to help me"
    assert long.kind == "promise"
    assert long.belief == "mags is on my side"
    assert long.about == ["mags"]
    assert length(String.split(long.text)) <= 20

    assert {"short", "turn.started"} in tiers(pc)
    assert Enum.count(tiers(pc), &(elem(&1, 0) == "faded")) == 3
    assert Repo.reload!(pc).memory_compressed_tick == 50
    assert Repo.get_by!(AICall, purpose: "memory.compress").call_type == "jev"
  end

  # Playtest drift run 2026-10-18: a rest with only self-about rows raised
  # "at least one question is required" in the compression task.
  test "rows about no one else fade without a Jev call", %{session: session, pc: pc} do
    short!(pc, "I slept badly", [], 5)
    short!(pc, "I counted my coins", [pc.slug], 6)

    Req.Test.stub(Jev.HTTP, fn _conn -> flunk("no Jev call without associations") end)

    rest = [
      %{"kind" => "time.passed", "location_id" => "inn", "payload" => %{"delta_ticks" => 40}}
    ]

    assert :ok = Compression.after_turn(session.id, rest, now: 50, mode: :shadow)
    assert Enum.all?(tiers(pc), &(elem(&1, 0) == "faded"))
    assert Repo.reload!(pc).memory_compressed_tick == 50
    refute Repo.get_by(AICall, purpose: "memory.compress")
  end

  test "no compression without a scene end or a rest", %{session: session, pc: pc} do
    short!(pc, "Mags laughed", ["mags"], 5)
    assert :ok = Compression.after_turn(session.id, [], now: 500, mode: :shadow)
    assert :ok = Compression.after_turn(session.id, [], now: 500, mode: :off)
    assert Repo.aggregate(CharacterMemory, :count) >= 1
    assert {"short", "Mags laughed"} in tiers(pc)
  end
end
