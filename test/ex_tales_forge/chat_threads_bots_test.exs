defmodule TalesForge.ChatThreadsBotsTest do
  # Bots and threads: /internal/chat carries thread_id, a bot answers in the
  # thread that woke it, a bot can never reach a 1:1, and card comments have
  # threads the same as the team chat.
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Board.Api
  alias TalesForge.Chat

  @fredrik "fredrik@whyse.se"

  setup do
    Application.put_env(:ex_tales_forge, :board_bots,
      case: [webhook_url: "https://case.test/hook", webhook_key: "case-key"],
      bobby: [webhook_url: "https://bobby.test/hook", webhook_key: "bobby-key"]
    )

    on_exit(fn -> Application.delete_env(:ex_tales_forge, :board_bots) end)
  end

  defp jobs(event), do: Oban.Job |> Repo.all() |> Enum.filter(&(&1.args["event"] == event))

  describe "/internal/chat" do
    test "a bot reads and posts in a subject thread by thread_id" do
      {:ok, t} = Chat.start_subject({:founder, "max"}, "Release")
      {:ok, _} = Chat.post("max@example.com", "Plan?", login: "maxpahlen", thread_id: t.id)

      assert {201, %{"thread_id" => id, "body" => "Here."}} =
               Chat.api(:create, :case, %{"thread_id" => t.id, "body" => "Here."})

      assert id == t.id

      {200, %{"thread" => %{"id" => ^id}, "messages" => messages, "threads" => threads}} =
        Chat.api(:index, :case, %{"thread_id" => t.id})

      assert Enum.map(messages, & &1["body"]) == ["Plan?", "Here."]
      assert Enum.all?(messages, &(&1["thread_id"] == t.id))
      assert t.id in Enum.map(threads, & &1["id"])
      {200, %{"messages" => []}} = Chat.api(:index, :case, %{})
    end

    test "a bot starts a subject thread with subject" do
      {201, %{"thread_id" => id}} =
        Chat.api(:create, :bobby, %{"subject" => "Deploy notes", "body" => "PR is up."})

      assert {:ok, %{subject: "Deploy notes", created_by: "bot:bobby"}} =
               Chat.thread({:founder, "max"}, id)
    end

    test "a bot gets 404 for a 1:1, a card thread and an unknown thread" do
      {:ok, direct} = Chat.start_direct({:founder, "fredrik"}, "max")
      {:ok, _} = Chat.post(@fredrik, "private", login: "fpahlen", thread_id: direct.id)
      {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "A card"})
      {:ok, card_thread} = Chat.start_card_thread({:founder, "max"}, idea.id, "Card talk")

      for id <- [direct.id, card_thread.id, Ecto.UUID.generate(), "bad"] do
        assert {404, _} = Chat.api(:index, :case, %{"thread_id" => id})
        assert {404, _} = Chat.api(:create, :case, %{"thread_id" => id, "body" => "x"})
      end

      {200, %{"threads" => threads}} = Chat.api(:index, :case, %{})
      ids = Enum.map(threads, & &1["id"])
      refute direct.id in ids
      refute card_thread.id in ids
      assert {:ok, [%{body: "private"}]} = Chat.recent({:founder, "max"}, direct.id)
    end

    test "the wake carries the thread, and the context comes from that thread only" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, t} = Chat.start_subject({:founder, "fredrik"}, "Bugs")
        {:ok, _} = Chat.post(@fredrik, "in General", login: "fpahlen")
        {:ok, _} = Chat.post(@fredrik, "in Bugs", login: "fpahlen", thread_id: t.id)
        {:ok, m} = Chat.post(@fredrik, "@case look", login: "fpahlen", thread_id: t.id)

        assert [job] = jobs("chat.mention")
        chat = job.args["payload"]["chat"]
        assert chat["thread"]["id"] == t.id
        assert chat["thread"]["subject"] == "Bugs"
        assert chat["message"]["thread_id"] == t.id
        assert chat["reply_params"] == %{"thread_id" => t.id}
        assert chat["message"]["id"] == m.id
        assert Enum.map(chat["recent"], & &1["body"]) == ["in Bugs"]
      end)
    end
  end

  describe "card threads" do
    setup do
      {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Threads on cards"})
      %{idea: idea}
    end

    test "old comments stay in General; a comment goes to its card thread", %{idea: idea} do
      {:ok, _} = Board.add_comment(idea, @fredrik, "general note")
      {:ok, t} = Chat.start_card_thread({:founder, "fredrik"}, idea.id, "Design")
      {:ok, idea} = Board.add_comment(idea, @fredrik, "design note", thread_id: t.id)

      assert [%{thread_id: nil}, %{thread_id: tid}] = idea.comments
      assert tid == t.id
      assert [%{id: ^tid, subject: "Design"}] = Chat.card_threads(idea.id)
      refute t.id in Enum.map(Chat.threads({:founder, "fredrik"}), & &1.id)
    end

    test "a thread of another card or a chat thread is refused", %{idea: idea} do
      {:ok, other} = Board.create_idea(@fredrik, %{"title" => "Other"})
      {:ok, t} = Chat.start_card_thread({:founder, "fredrik"}, other.id, "Elsewhere")
      {:ok, chat_thread} = Chat.start_subject({:founder, "fredrik"}, "Chat")

      for id <- [t.id, chat_thread.id, Ecto.UUID.generate(), "bad"] do
        assert {:error, "No such thread on this card."} =
                 Board.add_comment(idea, @fredrik, "x", thread_id: id)
      end
    end

    test "a bot mention in a card thread wakes the bot with the thread_id", %{idea: idea} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, t} = Chat.start_card_thread({:founder, "fredrik"}, idea.id, "Scope")

        {:ok, _} =
          Board.add_comment(idea, @fredrik, "@case is this L?", thread_id: t.id, login: "fpahlen")

        assert [job] = jobs("mention")
        assert job.args["payload"]["comment"]["thread_id"] == t.id
      end)
    end

    test "the board API reads card threads and answers in a thread", %{idea: idea} do
      {:ok, t} = Chat.start_card_thread({:founder, "fredrik"}, idea.id, "Cost")

      assert {200, card} =
               Api.handle(:comment, :case, %{"id" => idea.id, "thread_id" => t.id, "body" => "M"})

      assert [%{"thread_id" => tid, "body" => "M"}] = card["comments"]
      assert tid == t.id
      assert [%{"id" => ^tid, "subject" => "Cost"}] = card["threads"]

      assert {200, card} =
               Api.handle(:comment, :case, %{
                 "id" => idea.id,
                 "subject" => "Risks",
                 "body" => "One risk."
               })

      assert Enum.map(card["threads"], & &1["subject"]) |> Enum.sort() == ["Cost", "Risks"]

      assert {422, %{"error" => "No such thread on this card."}} =
               Api.handle(:comment, :case, %{
                 "id" => idea.id,
                 "thread_id" => Ecto.UUID.generate(),
                 "body" => "x"
               })
    end
  end
end
