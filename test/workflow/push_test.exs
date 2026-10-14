defmodule Workflow.PushTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Chat
  alias TalesForge.Workflow.Repo
  alias Workflow.Push
  alias Workflow.Push.Subscription

  doctest Workflow.Push

  @team Workflow.Team.Source.team()
  @owner Enum.find(@team.founders, &(&1.inbox != []))
  @other Enum.find(@team.founders, &(&1.inbox == ["mention", "thread_message"]))
  @other_email "other@example.com"

  # The fake push service: it sends each request to the test process and
  # gives the status in the process dictionary of the test (default 201).
  defmodule FakeClient do
    def post(%WebPushEx.Request{} = request) do
      pid = Application.get_env(:ex_tales_forge, :push_test_pid)
      send(pid, {:push, request})
      {:ok, Application.get_env(:ex_tales_forge, :push_test_status, 201)}
    end
  end

  setup do
    vapid = Application.get_env(:web_push_ex, :vapid)
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)

    Application.put_env(:web_push_ex, :vapid,
      public_key: Base.url_encode64(public, padding: false),
      private_key: Base.url_encode64(private, padding: false)
    )

    Application.put_env(:ex_tales_forge, Workflow.Push, client: FakeClient)
    Application.put_env(:ex_tales_forge, :push_test_pid, self())
    Application.delete_env(:ex_tales_forge, :push_test_status)

    on_exit(fn ->
      if vapid,
        do: Application.put_env(:web_push_ex, :vapid, vapid),
        else: Application.delete_env(:web_push_ex, :vapid)

      Application.delete_env(:ex_tales_forge, Workflow.Push)
      Application.delete_env(:ex_tales_forge, :push_test_pid)
    end)

    :ok
  end

  defp browser(n) do
    {client_public, _client_private} = :crypto.generate_key(:ecdh, :prime256v1)

    %{
      "endpoint" => "https://push.example.com/send/#{n}",
      "keys" => %{
        "p256dh" => Base.url_encode64(client_public, padding: false),
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      },
      "user_agent" => "Test browser #{n}"
    }
  end

  describe "the subscription store" do
    test "stores one row for each founder and browser profile" do
      assert {:ok, _} = Push.subscribe(@owner.handle, browser(1))
      assert {:ok, _} = Push.subscribe(@owner.handle, browser(2))
      assert {:ok, _} = Push.subscribe(@other.handle, browser(3))

      assert length(Push.subscriptions(@owner.handle)) == 2
      assert length(Push.subscriptions(@other.handle)) == 1
    end

    test "the same browser profile keeps one row and gets the new keys and founder" do
      first = browser(1)
      again = put_in(browser(1)["keys"]["auth"], "bmV3LWF1dGgta2V5")

      {:ok, _} = Push.subscribe(@owner.handle, first)
      {:ok, _} = Push.subscribe(@other.handle, again)

      assert [%Subscription{handle: handle, auth: "bmV3LWF1dGgta2V5"}] = Repo.all(Subscription)
      assert handle == @other.handle
    end

    test "accepts only an https endpoint with both keys" do
      assert {:error, cs} =
               Push.subscribe(@owner.handle, %{browser(1) | "endpoint" => "http://x"})

      assert %{endpoint: [_]} = errors_on(cs)
      assert {:error, cs} = Push.subscribe(@owner.handle, Map.delete(browser(1), "keys"))
      assert %{p256dh: [_], auth: [_]} = errors_on(cs)
    end

    test "stores the times in UTC" do
      {:ok, sub} = Push.subscribe(@owner.handle, browser(1))
      assert sub.inserted_at.time_zone == "Etc/UTC"
    end

    test "push is off without the VAPID keys: no key, no job" do
      Application.put_env(:web_push_ex, :vapid, [])
      refute Push.enabled?()
      assert Push.public_key() == nil
      assert Push.job(%Workflow.Inbox.Record{id: Ecto.UUID.generate()}) == nil
    end
  end

  describe "the send paths" do
    test "a new inbox item for a founder sends a push to each browser of that founder" do
      {:ok, _} = Push.subscribe(@owner.handle, browser(1))
      {:ok, _} = Push.subscribe(@owner.handle, browser(2))
      {:ok, _} = Push.subscribe(@other.handle, browser(3))

      {:ok, idea} = Board.create_idea(@other_email, %{"title" => "Push card"})
      {:ok, _} = Board.add_comment(idea, @other_email, "@#{@owner.handle} look at this")

      assert_receive {:push, %{endpoint: %URI{path: "/send/1"}} = request}
      assert_receive {:push, %{endpoint: %URI{path: "/send/2"}}}
      refute_receive {:push, %{endpoint: %URI{path: "/send/3"}}}

      assert request.headers["Content-Encoding"] == "aes128gcm"
      assert request.headers["Authorization"] =~ ~r/^vapid t=.+, k=.+/
      assert [%{last_sent_at: %DateTime{}} | _] = Push.subscriptions(@owner.handle)
    end

    test "a chat message that the inbox rules route to a founder sends a chat push" do
      {:ok, _} = Push.subscribe(@owner.handle, browser(1))
      {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} lunch?", login: @other.github)

      assert_receive {:push, %{endpoint: %URI{path: "/send/1"}}}
      assert [%{source: :chat} = item] = Workflow.Inbox.Store.open(@owner.handle)
      assert %{title: "New chat message", url: "/team#chat"} = Push.message(item)
    end

    test "a chat message that routes to nobody sends no push" do
      {:ok, _} = Push.subscribe(@owner.handle, browser(1))
      {:ok, _} = Chat.post(@other_email, "Hello all", login: @other.github)

      refute_receive {:push, _}
    end

    test "an expired subscription (410) is deleted" do
      {:ok, _} = Push.subscribe(@owner.handle, browser(1))
      Application.put_env(:ex_tales_forge, :push_test_status, 410)

      {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} hi", login: @other.github)

      assert_receive {:push, _}
      assert Push.subscriptions(@owner.handle) == []
    end
  end
end
