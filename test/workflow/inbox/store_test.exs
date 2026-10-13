defmodule Workflow.Inbox.StoreTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Chat
  alias Workflow.Inbox.Store

  # The team config of this app gives every founder the rule "mention". One
  # founder (the owner) has more rules.
  @team Workflow.Team.Source.team()
  @owner Enum.find(@team.founders, &(&1.inbox != []))
  @other Enum.find(@team.founders, &(&1.inbox == ["mention"]))
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

  test "the inbox replaces the pings and the chat badge for each founder with rules" do
    idea = card()

    {:ok, _} =
      Board.add_comment(idea, @owner_email, "@#{@other.handle} look", login: @owner.github)

    {:ok, _} =
      Board.add_comment(idea, @other_email, "@#{@owner.handle} look", login: @other.github)

    {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} hi", login: @other.github)
    {:ok, _} = Chat.post(@owner_email, "@#{@other.handle} hi", login: @owner.github)

    assert Board.unread_pings(@owner.github) == []
    assert Chat.unread(@owner.github) == 0
    assert Board.unread_pings(@other.github) == []
    assert Chat.unread(@other.github) == 0
    # The comment of @other on the card closed the card item of @other.
    assert [%{source: :chat}] = Store.open(@other.handle)
  end

  describe "rule pr_approval" do
    @pr %{
      "number" => 301,
      "url" => "https://github.com/whyse-ab/ex-tales-forge/pull/301",
      "head_sha" => "abc1234def",
      "player_note" => "Nothing changes for players.",
      "title" => "Inbox approve test"
    }

    test "a PR that waits for an OK makes one approve item, and Approve closes it" do
      {:ok, idea} = Board.link_pr(@pr)

      assert [item] = Store.open(@owner.handle)
      assert item.kind == :approve
      assert item.rule == "pr_approval"
      assert item.source == :pr
      assert item.idea_id == idea.id
      assert item.body =~ "PR #301 (abc1234) waits for a founder's OK"
      assert Store.open(@other.handle) == []

      {:ok, _} = Board.answer_pr(idea, @other_email, :approve, nil)
      assert Store.open(@owner.handle) == []
    end

    test "a new head replaces the open approve item" do
      {:ok, _} = Board.link_pr(@pr)
      {:ok, _} = Board.link_pr(%{@pr | "head_sha" => "beef000"})

      assert [%{source_id: "pr-301-beef000"}] = Store.open(@owner.handle)
    end
  end

  describe "rule founder_check" do
    defp check_card(questions) do
      idea = card()

      {:ok, idea} = Board.vote(idea, @other_email, 1)
      {:ok, idea} = Board.move(idea, {:founder, @other_email}, "refining")

      {:ok, idea} =
        Board.refine(idea, %{
          "open_questions" => questions,
          "rough_cost" => "S",
          "verdict" => "feasible"
        })

      {:ok, idea} = Board.move(idea, {:bot, Workflow.Team.bot(@team, :refiner)}, "check")
      idea
    end

    test "a move to Founder check makes one item for each open question" do
      idea = check_card(["How big?", "Which page?"])

      assert [one, two] = Store.open(@owner.handle)
      assert {one.kind, one.source, one.body} == {:answer, :question, "How big?"}
      assert two.body == "Which page?"
      assert one.idea_id == idea.id
      assert Store.open(@other.handle) == []
    end

    test "an answer on the card closes the item of that question" do
      idea = check_card(["How big?", "Which page?"])
      {:ok, _} = Board.answer_question(idea, @other_email, "How big?", %{"answer" => "Small"})

      assert [%{body: "Which page?"}] = Store.open(@owner.handle)
    end
  end

  describe "rules ci_failed and deploy_failed (GitHub runs on main)" do
    alias TalesForge.Board.GitHubEvents
    alias TalesForge.GitEvents.GitEvent

    defp run_on_main(workflow, ci, sha) do
      %GitEvent{type: :workflow_run, repo: "o/r", action: "completed", branch: "main"}
      |> Map.merge(%{workflow: workflow, ci: ci, sha: sha, actor: "someone"})
      |> GitHubEvents.plan()
      |> Enum.each(fn
        {:inbox, event} -> {:ok, _} = Store.record(@team, event)
        _step -> :ok
      end)
    end

    test "a failed CI run makes one ack item, and a passed CI run closes it" do
      run_on_main("CI", :failed, "abc1234")

      assert [item] = Store.open(@owner.handle)
      assert {item.kind, item.source, item.rule, item.title} == {:ack, :github, "ci_failed", "CI"}
      assert item.url == "https://github.com/o/r/commit/abc1234"
      assert Store.open(@other.handle) == []

      run_on_main("Deploy to playtest", :failed, "abc1234")
      run_on_main("CI", :passed, "def5678")
      assert [%{rule: "deploy_failed"}] = Store.open(@owner.handle)
    end

    test "the same failed run twice makes one item" do
      run_on_main("CI", :failed, "abc1234")
      run_on_main("CI", :failed, "abc1234")
      assert [_one] = Store.open(@owner.handle)
    end
  end
end
