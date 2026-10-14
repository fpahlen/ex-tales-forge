defmodule TalesForge.ChatThreadParticipantsTest do
  # Each new message in a thread notifies each participant of the thread:
  # the founder or bot that started the thread, posted in it, or was
  # @mentioned in it. Founders get an inbox item (rule thread_message), bots
  # get the wake chat.thread_message with thread_id. The author is never
  # notified. A bot author wakes no bot. A 1:1 has only its two members as
  # participants and wakes no bot. Card threads use the card access.
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Chat
  alias TalesForge.Workflow.Repo
  alias Workflow.Inbox.Store

  @fredrik "fredrik@whyse.se"
  @max "max@example.com"
  @thobias "thobias@example.com"

  setup do
    Application.put_env(:ex_tales_forge, :board_bots,
      case: [webhook_url: "https://case.test/hook", webhook_key: "case-key"],
      bobby: [webhook_url: "https://bobby.test/hook", webhook_key: "bobby-key"],
      gentry: [webhook_url: "https://gentry.test/hook", webhook_key: "gentry-key"]
    )

    on_exit(fn -> Application.delete_env(:ex_tales_forge, :board_bots) end)
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  defp jobs(event),
    do: Oban.Job |> Repo.all(prefix: "workflow") |> Enum.filter(&(&1.args["event"] == event))

  defp woken(event), do: event |> jobs() |> Enum.map(& &1.args["bot"]) |> Enum.sort()

  defp items(handle), do: Store.open(handle)

  defp rules(handle), do: handle |> items() |> Enum.map(& &1.rule)

  defp post(email, login, body, thread_id),
    do: {:ok, _} = Chat.post(email, body, login: login, thread_id: thread_id)

  describe "chat subject threads" do
    test "a new message notifies the starter and the earlier authors, not the author" do
      manual(fn ->
        {:ok, t} = Chat.start_subject({:founder, "fredrik"}, "Release")
        post(@max, "maxpahlen", "I can test it.", t.id)

        assert rules("fredrik") == ["thread_message"]
        assert items("max") == []
        assert items("thobias") == []

        post(@thobias, "tsjokvist", "Me too.", t.id)
        assert rules("fredrik") == ["thread_message", "thread_message"]
        assert rules("max") == ["thread_message"]
        assert items("thobias") == []
      end)
    end

    test "a founder that the message names gets one item, the mention item" do
      manual(fn ->
        {:ok, t} = Chat.start_subject({:founder, "fredrik"}, "Release")
        post(@fredrik, "fpahlen", "@max can you look?", t.id)
        assert rules("max") == ["mention"]

        post(@thobias, "tsjokvist", "@max and @fredrik, look", t.id)
        assert Enum.sort(rules("max")) == ["mention", "mention"]
        assert rules("fredrik") == ["mention"]
      end)
    end

    test "a mention makes a founder a participant of later messages" do
      manual(fn ->
        {:ok, t} = Chat.start_subject({:founder, "fredrik"}, "Release")
        post(@fredrik, "fpahlen", "@hakan please read", t.id)
        post(@max, "maxpahlen", "Read it.", t.id)
        assert Enum.sort(rules("hakan")) == ["mention", "thread_message"]
      end)
    end

    test "a bot participant gets chat.thread_message with thread_id, and one wake for a mention" do
      manual(fn ->
        {:ok, t} = Chat.start_subject({:founder, "fredrik"}, "Bugs")
        {201, _} = Chat.api(:create, :case, %{"thread_id" => t.id, "body" => "On it."})
        post(@max, "maxpahlen", "Thanks.", t.id)

        assert [job] = jobs("chat.thread_message")
        assert job.args["bot"] == "case"
        assert job.args["payload"]["thread_id"] == t.id
        assert job.args["payload"]["chat"]["message"]["body"] == "Thanks."

        post(@max, "maxpahlen", "@case one more", t.id)
        assert woken("chat.mention") == ["case"]
        assert woken("chat.thread_message") == ["case"]
      end)
    end

    test "a message by a bot wakes no bot, and founders still get items" do
      manual(fn ->
        {:ok, t} = Chat.start_subject({:bot, :bobby}, "Deploy")
        post(@fredrik, "fpahlen", "Go.", t.id)
        {201, _} = Chat.api(:create, :case, %{"thread_id" => t.id, "body" => "@bobby done"})

        assert woken("chat.thread_message") == ["bobby"]
        assert jobs("chat.mention") == []
        assert rules("fredrik") == ["thread_message"]
      end)
    end

    test "the author is never notified, also as the thread starter" do
      manual(fn ->
        {:ok, t} = Chat.start_subject({:bot, :case}, "Notes")
        {201, _} = Chat.api(:create, :case, %{"thread_id" => t.id, "body" => "First."})
        post(@fredrik, "fpahlen", "Second.", t.id)
        post(@fredrik, "fpahlen", "Third.", t.id)

        assert items("fredrik") == []
        assert woken("chat.thread_message") == ["case", "case"]
      end)
    end
  end

  describe "1:1 threads" do
    test "only the two members are participants, and no bot wakes" do
      manual(fn ->
        {:ok, d} = Chat.start_direct({:founder, "fredrik"}, "max")
        post(@fredrik, "fpahlen", "@hakan @case private", d.id)
        post(@max, "maxpahlen", "Answer.", d.id)

        assert rules("fredrik") == ["thread_message"]
        assert items("hakan") == []
        assert jobs("chat.thread_message") == []
        assert jobs("chat.mention") == []
      end)
    end
  end

  describe "card threads" do
    test "a comment notifies the card thread participants with the card access" do
      manual(fn ->
        {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Card"})
        {:ok, t} = Chat.start_card_thread({:founder, "max"}, idea.id, "Talk")
        {:ok, _} = Board.add_comment(idea, "bot:gentry", "Checked.", thread_id: t.id)
        {:ok, _} = Board.add_comment(idea, @fredrik, "Good.", login: "fpahlen", thread_id: t.id)

        assert rules("max") == ["thread_message", "thread_message"]
        assert items("fredrik") == []
        assert [job] = jobs("chat.thread_message")
        assert job.args["bot"] == "gentry"
        assert job.args["payload"]["thread_id"] == t.id
        assert job.args["payload"]["comment"]["thread_id"] == t.id
      end)
    end

    test "the General thread of a card has its own participants" do
      manual(fn ->
        {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Card"})
        {:ok, t} = Chat.start_card_thread({:founder, "max"}, idea.id, "Talk")
        {:ok, _} = Board.add_comment(idea, @thobias, "General.", login: "tsjokvist")
        {:ok, _} = Board.add_comment(idea, @fredrik, "Also general.", login: "fpahlen")

        assert rules("thobias") == ["thread_message"]
        assert items("max") == []
        assert [_] = Chat.card_threads(idea.id) |> Enum.filter(&(&1.id == t.id))
      end)
    end

    test "a comment by a bot wakes no bot" do
      manual(fn ->
        {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Card"})
        {:ok, _} = Board.add_comment(idea, "bot:case", "First.")
        {:ok, _} = Board.add_comment(idea, "bot:bobby", "Second.")

        assert jobs("chat.thread_message") == []
      end)
    end

    test "an archived card notifies nobody" do
      manual(fn ->
        {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Card"})
        {:ok, _} = Board.add_comment(idea, "bot:case", "First.")
        {:ok, _} = Board.add_comment(idea, @max, "Second.", login: "maxpahlen")
        idea = Repo.update!(Ecto.Changeset.change(idea, column: "archived"))
        before = length(jobs("chat.thread_message"))
        {:ok, _} = Board.add_comment(idea, @thobias, "Late.", login: "tsjokvist")

        assert length(jobs("chat.thread_message")) == before
        assert rules("max") == []
      end)
    end
  end
end
