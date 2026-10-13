defmodule Workflow.InboxTest do
  use ExUnit.Case, async: true

  alias Workflow.Inbox
  alias Workflow.Inbox.Event

  doctest Workflow.Inbox

  @team Workflow.Team.example()

  test "each rule has a test in this file" do
    tested = ~w(mention founder_check)
    assert Enum.map(Inbox.rules(), & &1.id) == tested
  end

  describe "rule mention" do
    test "a comment that names a founder with the rule makes one answer item" do
      event = %Event{
        type: :comment,
        source_id: "c1",
        idea_id: "i1",
        title: "Dark mode",
        author: "lin@example.com",
        author_handle: "lin",
        mentions: ["ada", "orjan"],
        body: "@ada @orjan look"
      }

      assert [item] = Inbox.route(@team, event)
      assert item.recipient == "ada"
      assert item.rule == "mention"
      assert item.kind == :answer
      assert item.source == :comment
      assert item.url == "/team#idea-i1"
      assert item.title == "Dark mode"
    end

    test "a chat message that names the founder makes one item with the chat link" do
      event = %Event{type: :chat, source_id: "m1", mentions: ["ada"], body: "@ada hi"}
      assert [%{recipient: "ada", source: :chat, url: "/team#chat"}] = Inbox.route(@team, event)
    end

    test "the author gets no item for their own name" do
      event = %Event{type: :chat, source_id: "m1", author_handle: "ada", mentions: ["ada"]}
      assert Inbox.route(@team, event) == []
    end

    test "a founder with no rules gets no item" do
      event = %Event{type: :comment, idea_id: "i1", source_id: "c1", mentions: ["lin"]}
      assert Inbox.route(@team, event) == []
    end
  end

  describe "rule founder_check" do
    # Ada has the rule founder_check here; Örjan and Lin have no rules.
    setup do
      [ada | rest] = @team.founders
      %{team: %{@team | founders: [%{ada | inbox: ["mention", "founder_check"]} | rest]}}
    end

    test "a card in Founder check makes one answer item for each open question",
         %{team: team} do
      event = %Event{
        type: :check_questions,
        idea_id: "i1",
        title: "Dark mode",
        questions: ["How big?", "Which page?"]
      }

      assert [one, two] = Inbox.route(team, event)

      assert {one.recipient, one.rule, one.kind, one.source} ==
               {"ada", "founder_check", :answer, :question}

      assert {one.body, two.body} == {"How big?", "Which page?"}
      assert one.source_id == Inbox.question_id("i1", "How big?")
      assert one.url == "/team#idea-i1"
      assert Inbox.route(@team, event) == []
    end

    test "an answer closes the item of that question for all founders" do
      event = %Event{type: :question_answered, idea_id: "i1", questions: ["How big?"]}

      assert Inbox.closes(@team, event) ==
               [
                 %{
                   recipient: :all,
                   scope: {:source, :question, Inbox.question_id("i1", "How big?")}
                 }
               ]
    end

    test "a card that leaves Founder check closes its question items" do
      assert Inbox.closes(@team, %Event{type: :check_left, idea_id: "i1"}) ==
               [%{recipient: :all, scope: {:idea_rule, "i1", "founder_check"}}]
    end
  end

  test "a card that closes makes no item" do
    assert Inbox.route(@team, %Event{type: :card_closed, idea_id: "i1", mentions: ["ada"]}) ==
             []
  end

  test "a comment by the recipient closes the items of that card" do
    assert Inbox.closes(@team, %Event{type: :comment, idea_id: "i1", author_handle: "ada"}) ==
             [%{recipient: "ada", scope: {:idea, "i1"}}]
  end

  test "a chat message by the recipient closes the chat items" do
    assert Inbox.closes(@team, %Event{type: :chat, author_handle: "ada"}) ==
             [%{recipient: "ada", scope: :chat}]
  end

  test "an unknown rule id in the team config gives no inbox" do
    team = %{@team | founders: [%{name: "Zed", handle: "zed", github: nil, inbox: ["other"]}]}
    refute Inbox.has_inbox?(team, "zed")
  end
end
