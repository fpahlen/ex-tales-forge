defmodule TalesForge.World.InstanceTest do
  # Refactor step 10f, PR 1: one World.Instance per session runs its turns
  # one at a time.
  use TalesForge.DataCase, async: false

  import Ecto.Query
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.Turn
  alias TalesForge.Workers.ProcessTurn
  alias TalesForge.World.{Instance, TurnRequest}

  setup do
    # stub_llm/1 points the LLM at the stub through the environment.
    on_exit(fn ->
      System.delete_env("XAI_API_KEY")
      System.put_env("LLM_PROVIDER", "mock")
    end)
  end

  defp turns(session_id) do
    Repo.all(
      from(t in Turn,
        where: t.game_session_id == ^session_id,
        order_by: t.turn_number,
        select: {t.turn_number, t.player_action}
      )
    )
  end

  defp job(session_id, text) do
    %Oban.Job{
      args: %{
        "session_id" => session_id,
        "raw_action" => text,
        "player_action" => %{
          "overall_intent" => text,
          "action" => %{"action_type" => "wait", "target" => nil, "parameters" => %{}},
          "deferred_actions" => [],
          "confidence" => 0.9
        }
      }
    }
  end

  defp await_until(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(10) && await_until(fun, tries - 1)
    end
  end

  test "two concurrent submits give turns 1 and 2, in the order they came" do
    test_pid = self()

    # The first GM call waits for :go, so the second submit arrives while
    # the first turn is still running.
    stub_llm(fn
      :gm, user, _system ->
        send(test_pid, {:gm, self(), user})

        receive do
          :go -> :default
        after
          5_000 -> :default
        end

      _kind, _user, _system ->
        :default
    end)

    {:ok, session} = GameSessions.create_session(%{name: "Serialize"})

    first = Task.async(fn -> GameSessions.submit_message(session.id, "I wait a moment") end)
    assert_receive {:gm, gm_first, _}, 5_000

    second =
      Task.async(fn -> GameSessions.submit_message(session.id, "I look around the room") end)

    pid = Instance.whereis(session.id)
    await_until(fn -> :queue.len(:sys.get_state(pid).queue) == 1 end)

    # Only one turn runs: the second GM call has not started.
    refute_received {:gm, _, _}
    send(gm_first, :go)

    assert_receive {:gm, gm_second, _}, 5_000
    send(gm_second, :go)

    assert {:ok, %{status: :processing}} = Task.await(first, 10_000)
    assert {:ok, %{status: :processing}} = Task.await(second, 10_000)

    assert turns(session.id) == [{1, "I wait a moment"}, {2, "I look around the room"}]
  end

  test "an instance that dies mid-turn gives an error Oban retries, and the retry plays the turn" do
    test_pid = self()
    key = {__MODULE__, :crash_session}
    on_exit(fn -> :persistent_term.erase(key) end)

    stub_llm(fn
      :gm, _user, _system ->
        case :persistent_term.get(key, nil) do
          nil ->
            :default

          session_id ->
            :persistent_term.erase(key)
            pid = Instance.whereis(session_id)
            send(test_pid, {:killing, pid})
            Process.exit(pid, :kill)
            Process.sleep(1_000)
            :default
        end

      _kind, _user, _system ->
        :default
    end)

    {:ok, session} = GameSessions.create_session(%{name: "Crash"})
    :persistent_term.put(key, session.id)

    # The first attempt: the instance is killed during the GM call, so the
    # turn dies with it and nothing is stored.
    assert {:error, {:turn_down, _reason}} = ProcessTurn.perform(job(session.id, "I wait"))
    assert_received {:killing, killed}
    refute Process.alive?(killed)
    assert turns(session.id) == []

    # The next turn job (the player acts again) starts a new instance and
    # plays the turn once.
    assert :ok = ProcessTurn.perform(job(session.id, "I wait"))
    assert turns(session.id) == [{1, "I wait"}]
    assert Instance.whereis(session.id) not in [nil, killed]
  end

  test "an idle instance stops, and its state is the session's cache" do
    stub_llm(fn _kind, _user, _system -> :default end)
    previous = Application.get_env(:ex_tales_forge, :world_instance_idle_ms)
    Application.put_env(:ex_tales_forge, :world_instance_idle_ms, 200)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ex_tales_forge, :world_instance_idle_ms, previous),
        else: Application.delete_env(:ex_tales_forge, :world_instance_idle_ms)
    end)

    {:ok, session} = GameSessions.create_session(%{name: "Idle"})
    assert :ok = ProcessTurn.perform(job(session.id, "I wait"))

    pid = Instance.whereis(session.id)
    state = :sys.get_state(pid)
    assert state.world_tick == GameSessions.get_session!(session.id).world_state["world_tick"]
    assert "elara_voss" in Enum.map(state.characters, & &1.slug)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    # The Registry drops the name on its own monitor, just after.
    await_until(fn -> Instance.whereis(session.id) == nil end)

    refute Enum.any?(
             DynamicSupervisor.which_children(TalesForge.World.Supervisor),
             &match?({_, ^pid, _, _}, &1)
           )
  end

  # Refactor step 10f, PR 2: the instance, not the turn's store, broadcasts
  # the NPCs that spoke up, once the turn has committed.
  test "an NPC that speaks up in a turn is broadcast after the turn has committed" do
    stub_llm(fn _kind, _user, _system -> :default end)
    {:ok, session} = GameSessions.create_session(%{name: "Initiative After Commit"})

    # Marta's concern has waited long enough, so she speaks up this turn.
    marta = NPC.get_person(session.id, "marta_kellen")
    concern = Map.put(marta.runtime_state["current_concern"], "priority", 8)

    NPC.put_state!(
      marta,
      Map.merge(marta.runtime_state, %{"current_concern" => concern, "concern_wait_ticks" => 4})
    )

    SessionPubSub.subscribe(session.id)
    assert :ok = ProcessTurn.perform(job(session.id, "I wait a moment"))

    assert [{:turn_completed, _}, {:npc_initiative, initiative}] = turn_messages([])
    assert %{npc_id: "marta_kellen", npc_name: "Marta Kellen"} = initiative
    assert initiative.text =~ "ledger"

    # Committed: the speak-up is stored before anyone hears it.
    assert NPC.get_person(session.id, "marta_kellen").runtime_state["initiative_emitted"]
  end

  # The turn's broadcasts, in the order they came.
  defp turn_messages(acc) do
    receive do
      {:turn_completed, _} = message -> turn_messages([message | acc])
      {:npc_initiative, _} = message -> turn_messages([message | acc])
    after
      200 -> Enum.reverse(acc)
    end
  end

  test "run_turn/2 only takes a request for its own session" do
    request = TurnRequest.new(Ecto.UUID.generate(), {"I wait", %{}})
    assert_raise FunctionClauseError, fn -> Instance.run_turn(Ecto.UUID.generate(), request) end
  end
end
