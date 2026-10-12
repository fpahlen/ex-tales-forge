defmodule TalesForge.Board.NotifyTest do
  # Board webhooks survive deploys and go out promptly (card 42fd5696 woke Case
  # 33 min late on 2026-10-12: five 15 s timeouts with 1-2-4-8-16 min backoff).
  use ExUnit.Case, async: false

  alias TalesForge.Board.Workers.Notify

  setup do
    test_pid = self()
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(__MODULE__, fn conn ->
      n = Agent.get_and_update(calls, &{&1 + 1, &1 + 1})
      send(test_pid, {:request, n, Plug.Conn.get_req_header(conn, "x-board-delivery")})

      case Process.get(:mode) || :persistent_term.get({__MODULE__, :mode}, :ok) do
        :closed_once when n == 1 -> Req.Test.transport_error(conn, :closed)
        :closed_always -> Req.Test.transport_error(conn, :closed)
        _ -> Req.Test.json(conn, %{"ok" => true})
      end
    end)

    Application.put_env(:ex_tales_forge, :board_req_options, plug: {Req.Test, __MODULE__})

    Application.put_env(:ex_tales_forge, :board_bots,
      case: [webhook_url: "https://case.example/hook", webhook_key: "case-key"]
    )

    on_exit(fn ->
      :persistent_term.erase({__MODULE__, :mode})
      for k <- [:board_req_options, :board_bots], do: Application.delete_env(:ex_tales_forge, k)
    end)

    :ok
  end

  defp job(attempt \\ 1) do
    %Oban.Job{
      attempt: attempt,
      args: %{
        "bot" => "case",
        "event" => "idea.to_refining",
        "delivery_id" => "d-1",
        "payload" => %{"idea" => %{"id" => "42fd5696"}}
      }
    }
  end

  test "the first retries come within seconds, later ones back off up to 4 h" do
    assert Enum.map(1..10, &Notify.backoff(%Oban.Job{attempt: &1})) ==
             [10, 30, 60, 120, 120, 240, 480, 960, 1920, 3840]

    assert Notify.backoff(%Oban.Job{attempt: 20}) == 4 * 3600
    # Ten attempts reach the bot within about 2 h 10 min.
    assert Enum.sum(Enum.map(1..9, &Notify.backoff(%Oban.Job{attempt: &1}))) < 2 * 3600 + 600
  end

  test "a job ends well before Lifeline would rescue it" do
    assert Notify.timeout(job()) <= :timer.seconds(30)
  end

  test "a connection the bot closed is retried at once in the same attempt" do
    :persistent_term.put({__MODULE__, :mode}, :closed_once)
    assert :ok = Notify.perform(job())
    assert_received {:request, 1, ["d-1"]}
    assert_received {:request, 2, ["d-1"]}
  end

  test "only once: a second :closed is an error for Oban to retry" do
    :persistent_term.put({__MODULE__, :mode}, :closed_always)
    assert {:error, %Req.TransportError{reason: :closed}} = Notify.perform(job())
    refute_received {:request, 3, _}
  end

  test "idempotent: every attempt (and a rescued job) sends the same delivery id" do
    assert :ok = Notify.perform(job(1))
    assert :ok = Notify.perform(job(4))
    assert_received {:request, _, ["d-1"]}
    assert_received {:request, _, ["d-1"]}
  end

  test "Oban rescues orphaned jobs and stops gracefully inside Fly's kill_timeout" do
    config = Application.fetch_env!(:ex_tales_forge, Oban)

    assert {Oban.Plugins.Lifeline, opts} =
             List.keyfind(config[:plugins], Oban.Plugins.Lifeline, 0)

    assert opts[:rescue_after] <= :timer.minutes(5)

    [_, kill] = Regex.run(~r/^kill_timeout = "(\d+)s"/m, File.read!("fly.toml"))
    assert config[:shutdown_grace_period] < String.to_integer(kill) * 1000
  end
end
