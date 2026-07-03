defmodule TalesForge.NPCInitiativeTest do
  use TalesForge.DataCase, async: false

  alias Jido.AgentServer
  alias Jido.Signal
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.NPC
  alias TalesForge.NPCRegistry
  alias TalesForge.NPCSignals
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.NpcInstance

  setup do
    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
    end)

    :ok
  end

  test "marta initiative broadcasts after four in-game ticks of worry" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Initiative"})

    SessionPubSub.subscribe(session.id)

    aid = NPCRegistry.agent_id(session.id, "marta_kellen")
    pid = Jido.whereis(aid)
    world_tick = Map.get(session.world_state, "world_tick")

    signal =
      Signal.new!(
        "world.time.passed",
        %{"delta_ticks" => 1, "world_tick" => world_tick},
        source: "/test"
      )

    for _ <- 1..4 do
      assert {:ok, _agent} = AgentServer.call(pid, signal)
    end

    assert_receive {:npc_initiative, payload}, 1000
    assert payload.npc_id == "marta_kellen"
    assert payload.npc_name == "Marta Kellen"
    assert payload.text =~ "ledger"

    inst = NPC.get_instance(session.id, "marta_kellen")
    assert Map.get(inst.runtime_state, "initiative_emitted")
  end

  test "initiative does not repeat on subsequent ticks" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Initiative Once"})

    SessionPubSub.subscribe(session.id)

    aid = NPCRegistry.agent_id(session.id, "marta_kellen")
    pid = Jido.whereis(aid)
    world_tick = Map.get(session.world_state, "world_tick")

    signal =
      Signal.new!(
        "world.time.passed",
        %{"delta_ticks" => 1, "world_tick" => world_tick},
        source: "/test"
      )

    for _ <- 1..5 do
      AgentServer.call(pid, signal)
    end

    assert_receive {:npc_initiative, _payload}, 1000
    refute_receive {:npc_initiative, _payload}, 50
  end

  test "freeform player speech overheard by present NPCs" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Overhear"})

    world_tick = Map.get(session.world_state, "world_tick")

    handler = %{
      handler: "freeform",
      target: nil,
      skill: nil,
      notes: "test"
    }

    :ok =
      NPCSignals.emit_turn_signals(
        session.id,
        session.world_state,
        handler,
        "I study the chalk marks on the slate"
      )

    Process.sleep(100)

    inst = NPC.get_instance(session.id, "marta_kellen")

    memories = Map.get(inst.runtime_state, "memories", [])

    assert Enum.any?(memories, fn mem ->
             mem["summary"] =~ "chalk marks" and mem["tick"] == world_tick
           end)
  end

  test "direct speak does not duplicate overhear memory on target NPC" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Speak Only"})

    handler = %{
      handler: "speak",
      target: "marta_kellen",
      skill: "persuasion",
      notes: "test"
    }

    :ok =
      NPCSignals.emit_turn_signals(
        session.id,
        session.world_state,
        handler,
        "Marta, tell me about the ledger"
      )

    Process.sleep(100)

    inst = NPC.get_instance(session.id, "marta_kellen")
    memories = Map.get(inst.runtime_state, "memories", [])

    assert length(memories) == 1
    assert hd(memories)["summary"] =~ "spoke to me"
    refute hd(memories)["summary"] =~ "Overheard"
  end

  test "concern priority surfaces in world npc_state" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Concern UI"})

    inst = NPC.get_instance(session.id, "marta_kellen")

    inst
    |> NpcInstance.changeset(%{
      runtime_state:
        inst.runtime_state
        |> Map.put("concern_wait_ticks", 4)
        |> put_in(["current_concern", "priority"], 9)
    })
    |> Repo.update!()

    {:ok, session} = NPC.refresh_session_world_state(session)
    marta = get_in(session.world_state, ["npc_state", "marta_kellen"])

    assert marta["concern_priority"] == 9
  end
end
