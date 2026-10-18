defmodule TalesForge.Workers.ProcessTurnTest do
  # A GM transport error fails the turn, and the page shows "Turn failed".
  # Before the fix, Oban (max_attempts: 3) ran the whole turn again: the
  # retry streamed a new narrative onto that page and committed a turn.
  use TalesForge.DataCase, async: false

  import Ecto.Query
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.GameSessions
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.Turn
  alias TalesForge.Workers.ProcessTurn

  setup do
    on_exit(fn ->
      System.delete_env("XAI_API_KEY")
      System.put_env("LLM_PROVIDER", "mock")
    end)
  end

  test "after a GM error the turn is not run again: no second narrative, no commit" do
    gm_calls = :counters.new(1, [])

    # The first GM call drops; any later one would succeed.
    stub_llm(fn
      :gm, _user ->
        :counters.add(gm_calls, 1, 1)
        if :counters.get(gm_calls, 1) == 1, do: {:transport_error, :closed}, else: :default

      _kind, _user ->
        :default
    end)

    {:ok, session} = GameSessions.create_session(%{name: "GM drop"})
    SessionPubSub.subscribe(session.id)

    args = %{
      "session_id" => session.id,
      "raw_action" => "I wait",
      "player_action" => %{
        "overall_intent" => "I wait",
        "action" => %{"action_type" => "wait", "target" => nil, "parameters" => %{}},
        "deferred_actions" => [],
        "confidence" => 0.9
      }
    }

    drained =
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _job} = args |> ProcessTurn.new() |> Oban.insert()
        Oban.drain_queue(queue: :llm, with_scheduled: true, with_recursion: true)
      end)

    assert %{success: 0, discard: 1} = drained
    assert :counters.get(gm_calls, 1) == 1

    assert_received {:turn_failed, _reason}
    refute_received {:turn_stream, {:text, _}}
    refute_received {:turn_completed, _}

    assert Repo.aggregate(from(t in Turn, where: t.game_session_id == ^session.id), :count) == 0
  end
end
