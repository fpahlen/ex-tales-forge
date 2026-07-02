defmodule TalesForge.GameSessionsTest do
  use TalesForge.DataCase, async: false

  alias Jido.AgentServer
  alias TalesForge.GameSessions
  alias TalesForge.Jido

  setup do
    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents() do
        Jido.stop_agent(id)
      end
    end)

    :ok
  end

  describe "create_session/1 and submit_message/2" do
    test "persists a turn and updates the player session agent" do
      assert {:ok, session} = GameSessions.create_session(%{name: "Test Session"})
      assert {:ok, state} = GameSessions.submit_message(session.id, "look around the tavern")

      assert state.turn_count == 1
      assert length(state.entries) == 2

      pid = Jido.whereis(GameSessions.agent_id(session.id))
      assert is_pid(pid)
      {:ok, agent_state} = AgentServer.state(pid)
      assert agent_state.agent.state.turn_count == 1
    end
  end
end
