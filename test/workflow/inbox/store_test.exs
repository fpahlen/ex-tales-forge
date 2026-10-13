defmodule Workflow.Inbox.StoreTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Chat
  alias Workflow.Inbox.Store

  # The team config of this app gives the inbox rule "mention" to one founder.
  @team Workflow.Team.Source.team()
  @owner Enum.find(@team.founders, &(&1.inbox != []))
  @other Enum.find(@team.founders, &(&1.inbox == []))
  @owner_email "owner@example.com"
  @other_email "other@example.com"

  defp card do
    {:ok, idea} = Board.create_idea(@other_email, %{"title" => "Inbox card"})
    idea
  end

  test "a card comment that names the founder makes one item in the same transaction" do
    idea = card()
    {:ok, _} = Board.add_comment(idea, @other_email, "@#{@owner.handle} what do you think?")

    assert [item] = Store.open(@owner.handle)
    assert item.kind == :answer
    assert item.state == "new"
    assert item.idea_id == idea.id
    assert item.url == "/team#idea-" <> idea.id
    assert item.position == 1
    assert Store.count(@other.handle) == 0
  end

  test "a comment by the recipient on the card closes the item" do
    idea = card()
    {:ok, _} = Board.add_comment(idea, @other_email, "@#{@owner.handle} look")
    {:ok, _} = Board.add_comment(idea, @owner_email, "Yes, go.", login: @owner.github)

    assert Store.open(@owner.handle) == []
    assert [%{state: "done", acted_at: %DateTime{}}] = Repo.all(Workflow.Inbox.Record)
  end

  test "a chat message makes an item, and a chat message by the recipient closes it" do
    {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} lunch?")
    assert [%{source: :chat, url: "/team#chat"}] = Store.open(@owner.handle)

    {:ok, _} = Chat.post(@owner_email, "Yes", login: @owner.github)
    assert Store.open(@owner.handle) == []
  end

  test "a card that moves to the Archive closes its items" do
    idea = card()
    {:ok, _} = Board.add_comment(idea, @other_email, "@#{@owner.handle} look")
    {:ok, _} = Board.archive(idea, @other_email, "duplicate")
    assert Store.open(@owner.handle) == []
  end

  test "skip puts the item at the end of the queue" do
    idea = card()
    {:ok, _} = Board.add_comment(idea, @other_email, "@#{@owner.handle} one")
    {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} two")
    [first, second] = Store.open(@owner.handle)

    assert :ok = Store.skip(first.id, @owner.handle)
    assert Enum.map(Store.open(@owner.handle), & &1.id) == [second.id, first.id]
  end

  test "close_item sets the state and acted_at once" do
    {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} hi")
    [item] = Store.open(@owner.handle)

    assert :ok = Store.close_item(item.id, @owner.handle, :discard)
    assert {:error, :not_open} = Store.close_item(item.id, @owner.handle, :done)
    assert %{state: "discarded", acted_at: %DateTime{}} = Store.get(item.id)
  end

  test "the inbox replaces the pings and the chat badge only for a founder with rules" do
    idea = card()

    {:ok, _} =
      Board.add_comment(idea, @owner_email, "@#{@other.handle} look", login: @owner.github)

    {:ok, _} =
      Board.add_comment(idea, @other_email, "@#{@owner.handle} look", login: @other.github)

    {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} hi", login: @other.github)
    {:ok, _} = Chat.post(@owner_email, "@#{@other.handle} hi", login: @owner.github)

    assert Board.unread_pings(@owner.github) == []
    assert Chat.unread(@owner.github) == 0
    assert [%{count: 1}] = Board.unread_pings(@other.github)
    assert Chat.unread(@other.github) == 1
  end
end
