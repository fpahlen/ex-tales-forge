defmodule Workflow.Inbox.FoundersTest do
  @moduledoc """
  Each founder in the team config has the rule `mention`. An @mention of a
  founder makes one item in the inbox of that founder. The inbox replaces the
  board pings of that founder. The chat button also counts the message.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Chat
  alias Workflow.Inbox.Store

  @team Workflow.Team.Source.team()
  @author "author@example.com"

  test "the team config gives the rule mention to each founder" do
    assert Enum.map(@team.founders, & &1.handle) == ~w(fredrik thobias hakan jeanette max)
    assert Enum.all?(@team.founders, &("mention" in &1.inbox))
  end

  for founder <- Workflow.Team.Source.team().founders do
    @founder founder

    test "an @mention of #{founder.name} goes to the inbox of #{founder.name}" do
      %{handle: handle, github: github} = @founder
      {:ok, idea} = Board.create_idea(@author, %{"title" => "Card for #{handle}"})
      {:ok, _} = Board.add_comment(idea, @author, "@#{handle} please look")
      {:ok, _} = Chat.post(@author, "@#{handle} a question")

      assert [%{source: :comment, idea_id: id}, %{source: :chat}] = Store.open(handle)
      assert id == idea.id
      assert Enum.all?(@team.founders -- [@founder], &(Store.open(&1.handle) == []))
      assert Board.unread_pings(github) == []
      # The chat button counts the mention too (the inbox shows what needs an answer).
      assert %{count: 1, latest: %{preview: "@" <> _}} = Chat.bar(github, hd(@founder.emails))
    end
  end
end
