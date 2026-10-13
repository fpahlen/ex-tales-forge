defmodule TalesForge.ChatThreadsTest do
  # The access tests of the chat threads. A direct (1:1) thread is the main
  # risk: each test below tries one path into a direct thread as a founder
  # who is not a member, as a bot, or as a guest, and expects no access.
  use TalesForge.DataCase, async: false

  alias TalesForge.Chat
  alias TalesForge.Chat.{Message, Read, Thread}
  alias Workflow.Inbox.Store, as: InboxStore

  doctest TalesForge.Chat.ThreadRules

  # Founders of the team config (priv/team/data.json): GitHub login, handle.
  @fredrik %{email: "fredrik@whyse.se", login: "fpahlen", handle: "fredrik"}
  @max %{email: "max@example.com", login: "maxpahlen", handle: "max"}
  @hakan %{email: "hakan@example.com", login: "hawkan-fredriksson", handle: "hakan"}
  @thobias %{email: "thobias@example.com", login: "tsjokvist", handle: "thobias"}

  defp v(%{handle: h}), do: {:founder, h}

  defp post(who, body, thread, opts \\ []),
    do: Chat.post(who.email, body, [login: who.login, thread_id: thread.id] ++ opts)

  defp direct!(a, b) do
    {:ok, t} = Chat.start_direct(v(a), b.handle)
    t
  end

  defp wakes, do: Oban.Job |> Repo.all() |> Enum.filter(&(&1.args["event"] == "chat.mention"))

  describe "General" do
    test "old messages and posts with no thread are in the General thread" do
      {:ok, m} = Chat.post(@max.email, "Hello", login: @max.login)
      general = Chat.general()
      assert m.thread_id == general.id
      assert general.subject == "General"
      assert {:ok, [%{body: "Hello"}]} = Chat.recent(v(@thobias), nil)
      assert {:ok, [%{body: "Hello"}]} = Chat.recent({:bot, :case}, general.id)
    end
  end

  describe "subject threads" do
    test "founders and bots start subject threads, and all can read them" do
      assert {:ok, a} = Chat.start_subject(v(@max), "Release plan")
      assert {:ok, b} = Chat.start_subject({:bot, :case}, "Board review")
      assert b.created_by == "bot:case"
      assert {:error, :forbidden} = Chat.start_subject(:guest, "Guest")
      assert {:error, :forbidden} = Chat.start_subject(:nobody, "Nobody")
      assert {:error, %Ecto.Changeset{}} = Chat.start_subject(v(@max), "  ")

      ids = v(@thobias) |> Chat.threads() |> Enum.map(& &1.id)
      assert a.id in ids and b.id in ids
      assert {:ok, _} = Chat.post("bot:case", "Agenda", thread_id: a.id)
    end

    test "the thread list is sorted by the last message" do
      {:ok, old} = Chat.start_subject(v(@max), "Old")
      {:ok, new} = Chat.start_subject(v(@max), "New")
      {:ok, _} = post(@max, "bump", old)

      ids = v(@max) |> Chat.threads() |> Enum.map(& &1.id)
      assert Enum.find_index(ids, &(&1 == old.id)) < Enum.find_index(ids, &(&1 == new.id))
    end
  end

  describe "direct threads: who can start them" do
    test "a founder starts one 1:1 with one other founder, once for each pair" do
      t = direct!(@fredrik, @max)
      assert t.kind == "direct"
      assert t.members == ["fredrik", "max"]
      assert {:ok, %{id: id}} = Chat.start_direct(v(@max), "fredrik")
      assert id == t.id
      assert Repo.aggregate(from(x in Thread, where: x.kind == "direct"), :count) == 1
    end

    test "a 1:1 with yourself, with an unknown handle, or by a bot or guest is refused" do
      assert {:error, :forbidden} = Chat.start_direct(v(@max), "max")
      assert {:error, :forbidden} = Chat.start_direct(v(@max), "nobody")
      assert {:error, :forbidden} = Chat.start_direct(v(@max), nil)
      assert {:error, :forbidden} = Chat.start_direct({:bot, :case}, "max")
      assert {:error, :forbidden} = Chat.start_direct(:guest, "max")
      assert {:error, :forbidden} = Chat.start_direct({:founder, "nobody"}, "max")
    end

    test "the database refuses a direct thread with one member" do
      cs =
        Thread.changeset(%Thread{}, %{
          kind: "direct",
          subject: "1:1",
          members: ["max"],
          last_message_at: DateTime.utc_now()
        })

      assert {:error, %Ecto.Changeset{}} = Repo.insert(cs)
    end
  end

  describe "direct threads: only the two members get access" do
    setup do
      t = direct!(@fredrik, @max)
      {:ok, m} = post(@fredrik, "private note", t)
      %{t: t, m: m}
    end

    test "the members read and post", %{t: t} do
      assert {:ok, [%{body: "private note"}]} = Chat.recent(v(@max), t.id)
      assert {:ok, _} = post(@max, "reply", t)
      assert t.id in Enum.map(Chat.threads(v(@max)), & &1.id)
    end

    test "another founder cannot list, read, post or mark it", %{t: t} do
      refute t.id in Enum.map(Chat.threads(v(@thobias)), & &1.id)
      assert {:error, :not_found} = Chat.thread(v(@thobias), t.id)
      assert {:error, :not_found} = Chat.recent(v(@thobias), t.id)
      assert {:error, :not_found} = post(@thobias, "let me in", t)

      :ok = Chat.mark_read(@thobias.login, t.id)
      refute Repo.get_by(Read, handle: "thobias", thread_id: t.id)
      assert Repo.aggregate(from(m in Message, where: m.thread_id == ^t.id), :count) == 1
    end

    test "a bot can never read or post in it", %{t: t} do
      for bot <- [:case, :bobby, :gentry] do
        refute t.id in Enum.map(Chat.threads({:bot, bot}), & &1.id)
        assert {:error, :not_found} = Chat.thread({:bot, bot}, t.id)
        assert {:error, :not_found} = Chat.recent({:bot, bot}, t.id)
        assert {:error, :not_found} = Chat.post("bot:#{bot}", "hi", thread_id: t.id)
      end

      assert {404, _} = Chat.api(:index, :case, %{"thread_id" => t.id})
      assert {404, _} = Chat.api(:create, :case, %{"thread_id" => t.id, "body" => "hi"})
      {200, %{"messages" => messages}} = Chat.api(:index, :case, %{})
      refute Enum.any?(messages, &(&1["body"] == "private note"))
    end

    test "a guest, an unknown bot and an unknown actor have no access", %{t: t} do
      assert {:error, :not_found} = Chat.recent(:guest, t.id)
      assert {:error, :not_found} = Chat.recent(:nobody, t.id)
      assert {:error, :not_found} = Chat.post("guest@example.com", "hi", thread_id: t.id)
      assert {:error, :not_found} = Chat.post("bot:nobot", "hi", thread_id: t.id)
      assert {:error, :not_found} = Chat.post(@max.email, "hi", thread_id: t.id)
    end

    test "a forbidden thread and a missing thread give the same result", %{t: t} do
      assert Chat.recent(v(@thobias), t.id) == Chat.recent(v(@thobias), Ecto.UUID.generate())
      assert {:error, :not_found} = Chat.recent(v(@thobias), "not-a-uuid")
      assert {:error, :not_found} = Chat.recent(v(@thobias), 42)
    end

    test "a mention of a non-member makes no mention, no badge and no inbox item", %{t: t} do
      {:ok, m} = post(@max, "@thobias @fredrik @founders look", t)
      assert m.mentions == ["fredrik"]
      assert Chat.unread(@thobias.login) == 0
      assert Chat.unread_by_thread(v(@thobias), @thobias.email)[t.id] == nil

      u = direct!(@max, @thobias)
      {:ok, _} = post(@max, "@fredrik secret", u)
      refute Enum.any?(InboxStore.open("fredrik"), &(&1.body =~ "secret"))
    end

    test "a bot mention in a 1:1 wakes no bot", %{t: t} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, m} = post(@fredrik, "@case @devops read this", t)
        assert m.bots == []
        assert wakes() == []
      end)
    end

    test "a bot woken in a subject thread gets no direct message as context", %{t: t} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _} = post(@fredrik, "second private note", t)
        {:ok, _} = Chat.post(@fredrik.email, "@case look", login: @fredrik.login)

        assert [job] = wakes()
        bodies = Enum.map(job.args["payload"]["chat"]["recent"], & &1["body"])
        refute Enum.any?(bodies, &(&1 =~ "private"))
      end)
    end
  end

  describe "PubSub" do
    test "a direct message goes only to the two members" do
      t = direct!(@fredrik, @max)
      parent = self()

      listen = fn viewer ->
        spawn_link(fn ->
          Chat.subscribe(viewer)
          send(parent, {:ready, viewer})

          receive do
            {:team_chat, m} -> send(parent, {:got, viewer, m.body})
          after
            500 -> send(parent, {:none, viewer})
          end
        end)
      end

      viewers = [v(@max), v(@thobias), {:bot, :case}, :guest, :nobody]
      Enum.each(viewers, listen)
      for viewer <- viewers, do: assert_receive({:ready, ^viewer})

      {:ok, _} = post(@fredrik, "for max only", t)

      assert_receive {:got, {:founder, "max"}, "for max only"}
      assert_receive {:none, {:founder, "thobias"}}, 1_000
      assert_receive {:none, {:bot, :case}}, 1_000
      assert_receive {:none, :guest}, 1_000
      assert_receive {:none, :nobody}, 1_000
    end

    test "a new direct thread is announced only to its members" do
      Chat.subscribe(v(@thobias))
      %{id: other} = direct!(@fredrik, @hakan)
      refute_receive {:team_chat_thread, %{id: ^other}}, 200
      Chat.subscribe(v(@max))
      %{id: id} = direct!(@fredrik, @max)
      assert_receive {:team_chat_thread, %{id: ^id}}
      # The test process gets the event once, through the topic of the member.
      refute_receive {:team_chat_thread, %{id: ^id}}, 200
    end
  end

  describe "unread" do
    test "each thread has its own unread count for each founder" do
      {:ok, a} = Chat.start_subject(v(@max), "A")
      t = direct!(@max, @thobias)
      {:ok, _} = post(@max, "one", a)
      {:ok, _} = post(@max, "two", a)
      {:ok, _} = post(@max, "dm", t)

      counts = Chat.unread_by_thread(v(@thobias), @thobias.email)
      assert counts[a.id] == 2
      assert counts[t.id] == 1
      # The author has read their own messages.
      assert Chat.unread_by_thread(v(@max), @max.email) == %{}
      # The direct message counts on the chat button. Each founder has an
      # inbox, so a mention goes to the inbox and not to the button.
      {:ok, _} = post(@max, "@thobias look", a)
      assert Chat.unread(@thobias.login) == 1

      :ok = Chat.mark_read(@thobias.login, t.id)
      assert Chat.unread_by_thread(v(@thobias), @thobias.email)[t.id] == nil
      assert Chat.unread_by_thread(v(@thobias), @thobias.email)[a.id] == 3
      assert Chat.unread(@thobias.login) == 0
      assert Chat.unread_by_thread({:bot, :case}, nil) == %{}
    end
  end
end
