defmodule TalesForge.WorkLogTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.{Board, Chat, WorkLog}
  alias TalesForge.Workflow.Repo
  alias TalesForge.WorkLog.{Event, Peer}

  @ada "ada@example.com"

  setup do
    on_exit(fn ->
      Application.delete_env(:ex_tales_forge, :costs_peer)
      Application.delete_env(:ex_tales_forge, :work_log_peer_req_options)
    end)

    :ok
  end

  defp kinds, do: Event |> Repo.all() |> Enum.map(&{&1.founder, &1.kind}) |> Enum.sort()

  test "founder comments, moves, card edits and chat messages write events" do
    {:ok, idea} = Board.create_idea(@ada, %{"title" => "Work log card"})
    {:ok, idea} = Board.vote(idea, @ada, 1)
    {:ok, idea} = Board.move(idea, {:founder, @ada}, "refining")
    {:ok, idea} = Board.refine(idea, %{"details" => "Text"}, @ada)
    {:ok, _} = Board.add_comment(idea, @ada, "A comment")
    {:ok, _} = Chat.post(@ada, "Hello team")

    assert kinds() == [{@ada, "card_edit"}, {@ada, "chat"}, {@ada, "comment"}, {@ada, "move"}]
    assert Enum.all?(Repo.all(Event), &(&1.app == "local"))
  end

  test "bots write no events" do
    {:ok, idea} = Board.create_idea(@ada, %{"title" => "Bot card"})
    {:ok, _} = Board.add_comment(idea, "bot:case", "A bot comment")
    {:ok, _} = Chat.post("bot:bobby", "A bot message")
    assert kinds() == []
  end

  test "sessions/2 reads the stored events" do
    {:ok, _} = WorkLog.record(@ada, "chat", "r1")
    now = DateTime.utc_now()

    assert [%{founder: @ada, actions: 1}] =
             WorkLog.sessions(DateTime.add(now, -60), DateTime.add(now, 60))
  end

  test "put_peer_events/2 stores new rows once and skips bad rows" do
    list = [
      %{
        "founder" => "Ada@Example.com",
        "kind" => "turn",
        "ref" => "t1",
        "at" => "2026-10-12T10:00:00Z"
      },
      %{"founder" => "bot:case", "kind" => "turn", "ref" => "t2", "at" => "2026-10-12T10:00:00Z"},
      %{"founder" => @ada, "kind" => "read", "ref" => "t3", "at" => "2026-10-12T10:00:00Z"}
    ]

    assert WorkLog.put_peer_events(list, "playtest") == 1
    assert WorkLog.put_peer_events(list, "playtest") == 0
    assert [%Event{founder: @ada, app: "playtest"}] = Repo.all(Event)
  end

  test "the peer syncs playtest events after the newest stored one" do
    Application.put_env(:ex_tales_forge, :costs_peer, token: "secret")
    Application.put_env(:ex_tales_forge, :work_log_peer_req_options, plug: {Req.Test, Peer})

    Req.Test.stub(Peer, fn conn ->
      assert conn.query_params["since"] == "2026-01-01T00:00:00Z"

      Req.Test.json(conn, %{
        "events" => [
          %{"founder" => @ada, "kind" => "turn", "ref" => "t1", "at" => "2026-10-12T10:00:00Z"}
        ]
      })
    end)

    assert {:ok, 1} = Peer.sync()
    assert WorkLog.latest_at("playtest") == ~U[2026-10-12 10:00:00.000000Z]
  end

  test "the peer does nothing without the token" do
    assert {:error, :not_configured} = Peer.sync()
  end
end
