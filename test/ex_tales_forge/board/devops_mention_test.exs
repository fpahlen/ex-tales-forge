defmodule TalesForge.Board.DevopsMentionTest do
  # @devops names Case, Bobby and Gentry, like @founders names every founder.
  use TalesForge.DataCase, async: false

  import ExUnit.CaptureLog

  alias TalesForge.Board
  alias TalesForge.Board.Mentions
  alias TalesForge.Chat

  @fredrik "fredrik@whyse.se"

  # Case and Bobby have a webhook. Gentry has none (as in production today).
  setup do
    Application.put_env(:ex_tales_forge, :board_bots,
      case: [webhook_url: "https://case.test/hook", webhook_key: "case-key"],
      bobby: [webhook_url: "https://bobby.test/hook", webhook_key: "bobby-key"]
    )

    on_exit(fn -> Application.delete_env(:ex_tales_forge, :board_bots) end)
  end

  defp woken(event) do
    Oban.Job
    |> Repo.all()
    |> Enum.filter(&(&1.args["event"] == event))
    |> Enum.map(& &1.args["bot"])
    |> Enum.sort()
  end

  defp with_debug_log(fun) do
    level = Logger.level()
    Logger.configure(level: :debug)

    try do
      capture_log([level: :debug], fun)
    after
      Logger.configure(level: level)
    end
  end

  test "@devops expands to the three bots, in highlighting and in autocomplete" do
    assert Mentions.parse("@devops please", []).bots == [:case, :bobby, :gentry]
    assert Mentions.parse("@DevOps and @Bobby", []).bots == [:case, :bobby, :gentry]
    assert {:mention, "@devops"} in Mentions.segments("Hi @devops", [])
    assert Mentions.suggestions() |> Enum.take(-5) == ~w(founders devops case bobby gentry)
    assert Chat.suggestions() == Mentions.suggestions()
  end

  test "on a board card, one @devops wakes each bot with a webhook once, and skips Gentry quietly" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Deploys"})

      log =
        with_debug_log(fn ->
          {:ok, _} = Board.add_comment(idea, @fredrik, "@devops and @case, look at the deploy")
        end)

      assert woken("mention") == ["bobby", "case"]
      assert log =~ "[debug]"
      assert log =~ "gentry has no webhook"
      refute log =~ "[error]"
      refute log =~ "[warning]"
    end)
  end

  test "in team chat, one @devops wakes each bot with a webhook once" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      log =
        with_debug_log(fn ->
          {:ok, m} = Chat.post(@fredrik, "@devops @bobby @devops standup", login: "fpahlen")
          assert m.bots == ["case", "bobby", "gentry"]
        end)

      assert woken("chat.mention") == ["bobby", "case"]
      refute log =~ "[error]"
      refute log =~ "[warning]"
    end)
  end

  test "a direct mention of a bot without a webhook still makes its job, as before" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _} = Chat.post(@fredrik, "@gentry and @devops", login: "fpahlen")
      assert woken("chat.mention") == ["bobby", "case", "gentry"]
    end)
  end

  test "a bot's @devops wakes nobody in chat" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _} = Chat.post("bot:case", "@devops done")
      assert woken("chat.mention") == []
    end)
  end
end
