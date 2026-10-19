defmodule TalesForge.Playtest.ReportsTest do
  use TalesForge.DataCase, async: true

  alias TalesForge.GameSessions
  alias TalesForge.Playtest.Reports
  alias TalesForge.Repo
  alias TalesForge.Schemas.{SessionEvent, Turn}

  doctest Reports

  @t0 ~U[2026-10-18 12:00:00Z]

  describe "turn_records/1" do
    test "lists each turn's code-layer events, placed by tick and by when they were written" do
      {:ok, session} = GameSessions.create_session(%{name: "Report events"})

      # Turns 1 and 2 share tick 5 (turn 2 cost no game time); turn 3 is at tick 7.
      for {n, tick, at} <- [{1, 5, 0}, {2, 5, 10}, {3, 7, 20}] do
        turn(session.id, n, at)

        event(session.id, "gm_reasoning", tick, at, false, %{
          "turn_number" => n,
          "gm_reply" => %{}
        })
      end

      event(session.id, "time.passed", 5, 0, true, %{"delta_ticks" => 5})
      event(session.id, "player.travel", 5, 1, true, %{"from" => "inn", "to" => "square"})
      event(session.id, "turn.outcome", 5, 10, false, outcome())
      event(session.id, "world_fact", 5, 11, false, %{"text" => "The well is dry."})
      event(session.id, "npc.down", 7, 21, true, %{"npc_id" => "orc", "name" => "Orc"})

      assert [t1, t2, t3] = Reports.turn_records(session.id)

      assert t1.events == ["time.passed: delta_ticks 5", "player.travel: from inn, to square"]

      assert t2.events == [
               "(hidden) turn.outcome: Rejected: sell (smith). Reason: not in inventory " <>
                 "Coins: no change (30 copper in total). Items: no change. " <>
                 "Time: no change. Location: inn (no move)."
             ]

      assert t3.events == ["npc.down: name Orc, npc_id orc"]
      refute Map.has_key?(t1, :gm_notes)
    end

    test "a turn without events has an empty list" do
      {:ok, session} = GameSessions.create_session(%{name: "Report no events"})
      turn(session.id, 1, 0)

      assert [%{turn_number: 1, events: []}] = Reports.turn_records(session.id)
    end
  end

  defp turn(session_id, n, at) do
    Repo.insert!(%Turn{
      game_session_id: session_id,
      turn_number: n,
      player_action: "act #{n}",
      narrative: "narration #{n}",
      inserted_at: DateTime.add(@t0, at)
    })
  end

  defp event(session_id, kind, tick, at, aware, payload) do
    Repo.insert!(%SessionEvent{
      game_session_id: session_id,
      kind: kind,
      actor: "server",
      player_aware: aware,
      tick: tick,
      payload: payload,
      inserted_at: DateTime.add(@t0, at)
    })
  end

  defp outcome do
    %{
      "actions" => [
        %{
          "type" => "sell",
          "target" => "smith",
          "status" => "rejected",
          "reason" => "not in inventory"
        }
      ],
      "coins" => %{"before_copper" => 30, "after_copper" => 30, "delta_copper" => 0},
      "items" => %{"gained" => [], "lost" => []},
      "clock" => %{"tick_before" => 5, "tick_after" => 5, "time" => nil},
      "location" => %{"from" => "inn", "to" => "inn"}
    }
  end
end
