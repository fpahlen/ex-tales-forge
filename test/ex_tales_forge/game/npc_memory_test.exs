defmodule TalesForge.Game.NpcMemoryTest do
  @moduledoc """
  NPC dialogue memory and the repetition guard (`TalesForge.Game.NpcMemory`,
  `NPC_DIALOGUE_MEMORY`). Brenna says the same line on two turns: the second
  turn shows the memory in the GM prompt and records a `turn.npc_repeat`.
  """
  use TalesForge.DataCase, async: false

  import Ecto.Query
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, SessionEvent}

  doctest TalesForge.Game.NpcMemory

  @env ~w(NPC_DIALOGUE_MEMORY INN_WORLD)

  setup do
    saved = Map.new(@env, &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)

      Enum.each(saved, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("XAI_API_KEY")
    end)

    System.put_env("INN_WORLD", "on")
    test_pid = self()

    stub_llm(fn
      :gm, user, _system ->
        send(test_pid, {:gm_prompt, user})

        %{
          "narrative" => ~s(Brenna Holt sets down a mug. "We close at midnight, traveller."),
          "gm_notes" => "n"
        }

      _kind, _user, _system ->
        :default
    end)

    :ok
  end

  defp play(session_id, n) do
    action = %{
      "overall_intent" => "I ask Brenna when the inn closes.",
      "action" => %{"action_type" => "speak", "target" => "innkeep", "parameters" => %{}},
      "deferred_actions" => [],
      "confidence" => 0.9
    }

    {:ok, _} = TurnProcessor.run(session_id, "Ask Brenna, turn #{n}.", action)
    assert_received {:gm_prompt, prompt}
    prompt
  end

  defp new_session do
    {:ok, session} = GameSessions.create_session(%{name: "Memory", adventure_id: "tin_valley"})
    Repo.get!(GameSession, session.id)
  end

  defp repeats(session_id) do
    SessionEvent
    |> where([e], e.game_session_id == ^session_id and e.kind == "turn.npc_repeat")
    |> Repo.all()
  end

  test "flag on: the server writes the memory, the GM sees it, and a repeat is logged" do
    System.put_env("NPC_DIALOGUE_MEMORY", "on")
    session = new_session()
    assert "innkeep" in session.world_state["present_npcs"]

    first = play(session.id, 1)
    refute first =~ "NPC dialogue memory"

    memory = Repo.get!(GameSession, session.id).world_state["npc_memory"]
    assert memory == %{"innkeep" => ["We close at midnight, traveller."]}

    second = play(session.id, 2)
    assert second =~ "NPC dialogue memory"
    assert second =~ ~s(- "We close at midnight, traveller.")

    assert [%{payload: %{"count" => 1, "repeats" => [%{"npc_id" => "innkeep"}]}}] =
             repeats(session.id)

    assert Repo.get!(GameSession, session.id).world_state["npc_memory"] == memory
  end

  test "flag off: no memory and no repeat events" do
    System.put_env("NPC_DIALOGUE_MEMORY", "off")
    session = new_session()
    play(session.id, 1)
    refute play(session.id, 2) =~ "NPC dialogue memory"
    assert Repo.get!(GameSession, session.id).world_state["npc_memory"] == nil
    assert repeats(session.id) == []
  end
end
