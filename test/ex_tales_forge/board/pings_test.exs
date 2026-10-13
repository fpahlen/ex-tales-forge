defmodule TalesForge.Board.PingsTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Board

  doctest TalesForge.Board.Mentions

  @fredrik "fredrik@whyse.se"
  @hakan "hawkan.fredriksson@gmail.com"
  # GitHub logins (founders sign in with GitHub); case-insensitive.
  @fredrik_gh "fpahlen"
  @hakan_gh "Hawkan-Fredriksson"

  test "the founder handles map the GitHub team logins" do
    team = Workflow.Team.Source.team()

    assert Workflow.Team.github_handles(team) == %{
             "fpahlen" => "fredrik",
             "jpa71" => "jeanette",
             "tsjokvist" => "thobias",
             "hawkan-fredriksson" => "hakan",
             "maxpahlen" => "max"
           }

    assert Enum.sort(TalesForge.Board.Mentions.handles(team)) ==
             ~w(fredrik hakan jeanette max thobias)
  end

  test "a comment makes an inbox item for the founders it names, never the author" do
    {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Fishing"})

    {:ok, idea} =
      Board.add_comment(idea, @fredrik, "@hakan and @fredrik, what do you think?",
        login: @fredrik_gh
      )

    # Each founder has inbox rules, so the inbox replaces the pings.
    assert [%{idea_id: id, title: "Fishing", author: @fredrik}] =
             Workflow.Inbox.Store.open("hakan")

    assert id == idea.id
    assert Workflow.Inbox.Store.open("fredrik") == []
    assert Board.unread_pings(@hakan_gh) == []
    assert Board.unread_pings(@fredrik_gh) == []

    {:ok, _} = Board.add_comment(idea, "bot:case", "@Håkan one more question.")
    assert [_, _] = Workflow.Inbox.Store.open("hakan")
  end

  test "@founders pings every founder except the author; bot mentions add no pings" do
    {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Inn"})

    {:ok, _} =
      Board.add_comment(idea, @hakan, "@founders vote please. @case too",
        login: "hawkan-fredriksson"
      )

    # Each founder gets an inbox item, not a ping.
    for handle <- ~w(fredrik jeanette thobias max) do
      assert [%{recipient: ^handle}] = Workflow.Inbox.Store.open(handle)
    end

    assert Workflow.Inbox.Store.open("hakan") == []
    assert Board.unread_pings(@fredrik_gh) == []
    assert Board.unread_pings("MaxPahlen") == []
    assert Board.unread_pings(@hakan_gh) == []
    assert Board.unread_pings("tf-tester") == []
  end

  test "saving the same answer twice writes one history line" do
    {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Questions"})
    {:ok, idea} = Board.vote(idea, @fredrik, 1)
    {:ok, idea} = Board.move(idea, {:founder, @fredrik}, "refining")

    {:ok, idea} =
      Board.refine(idea, %{
        "details" => "d",
        "open_questions" => ["Why?"],
        "rough_cost" => "S",
        "verdict" => "feasible"
      })

    {:ok, _} = Board.answer_question(idea, @fredrik, "Why?", %{"answer" => "Fun."})
    {:ok, idea} = Board.answer_question(idea, @fredrik, "Why?", %{"answer" => "Fun."})
    {:ok, idea} = Board.answer_question(idea, @fredrik, "Why?", %{"deferred" => false})
    assert Enum.count(idea.transitions, &((&1.note || "") =~ "Why?")) == 1
  end

  test "an archived card closes its inbox items" do
    {:ok, idea} = Board.create_idea(@fredrik, %{"title" => "Fishing"})
    {:ok, idea} = Board.add_comment(idea, @fredrik, "@hakan look", login: @fredrik_gh)
    assert [_] = Workflow.Inbox.Store.open("hakan")
    {:ok, _} = Board.archive(idea, @fredrik, "Duplicate")
    assert Workflow.Inbox.Store.open("hakan") == []
    assert Board.unread_pings(@hakan_gh) == []
  end
end
