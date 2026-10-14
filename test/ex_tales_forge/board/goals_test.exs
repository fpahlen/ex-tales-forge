defmodule TalesForge.Board.GoalsTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Board.{Goal, Goals}
  alias TalesForge.QaLogin
  alias TalesForge.Workflow.Repo

  doctest TalesForge.Board.Goals

  @ada "ada@example.com"
  @bo "bo@example.com"

  defp goal!(key, attrs \\ %{}) do
    %Goal{}
    |> Goal.changeset(Map.merge(%{key: key, title: "Goal #{key}", sort: 100}, attrs))
    |> Repo.insert!()
    |> Repo.preload(:votes)
  end

  defp card!(title, goal, column \\ "ideas") do
    {:ok, idea} = Board.create_idea(@ada, %{"title" => title})
    {:ok, idea} = Goals.set_card_goal(idea, @ada, goal && goal.id)

    if column != "ideas",
      do: Repo.update!(Ecto.Changeset.change(idea, column: column)),
      else: idea
  end

  defp row(strip, goal), do: Enum.find(strip.goals, &(&1.goal.id == goal.id))

  describe "seed" do
    test "the migration adds G2 to G7 with the month-end target dates" do
      seeded = Map.new(Repo.all(Goal), &{&1.key, &1})

      assert %{
               "G2" => %{target_date: ~D[2026-12-31]},
               "G3" => %{target_date: ~D[2026-11-30]},
               "G4" => %{target_date: ~D[2027-03-31]},
               "G5" => %{target_date: ~D[2027-06-30]},
               "G6" => %{target_date: ~D[2027-05-31]},
               "G7" => %{target_date: ~D[2026-10-31]}
             } = seeded

      assert seeded["G2"].title == "Playable game on the Elixir rewrite"
      assert seeded["G7"].title == "Our shared workspace (team tools)"
      for {_k, g} <- seeded, do: assert(g.outcome != "")
    end
  end

  describe "countdown (Stockholm days)" do
    test "24 days remaining, due today, overdue" do
      assert Goals.days_left(~D[2026-11-05], ~U[2026-10-12 10:00:00Z]) == 24
      assert Goals.countdown(24) == "24 days remaining"
      assert Goals.days_left(~D[2026-10-12], ~U[2026-10-12 21:59:59Z]) == 0
      assert Goals.days_left(~D[2026-10-12], ~U[2026-10-12 22:00:00Z]) == -1
      assert Goals.countdown(-3) == "3 days overdue"
      assert Goals.days_left(nil, ~U[2026-10-12 10:00:00Z]) == nil
    end

    test "the day starts at Stockholm midnight, not at UTC midnight" do
      # 23:30 UTC on 12 Oct is 01:30 on 13 Oct in Stockholm (CEST, UTC+2).
      assert Goals.days_left(~D[2026-10-31], ~U[2026-10-12 21:30:00Z]) == 19
      assert Goals.days_left(~D[2026-10-31], ~U[2026-10-12 22:30:00Z]) == 18
      # In winter (CET, UTC+1) the day changes at 23:00 UTC.
      assert Goals.days_left(~D[2026-12-31], ~U[2026-12-30 22:59:59Z]) == 1
      assert Goals.days_left(~D[2026-12-31], ~U[2026-12-30 23:00:00Z]) == 0
    end

    test "DST changes do not change the count" do
      # Clocks go back on 25 Oct 2026 (03:00 CEST -> 02:00 CET).
      assert Goals.days_left(~D[2026-10-31], ~U[2026-10-24 21:59:59Z]) == 7
      assert Goals.days_left(~D[2026-10-31], ~U[2026-10-24 22:00:00Z]) == 6
      assert Goals.days_left(~D[2026-10-31], ~U[2026-10-25 22:59:59Z]) == 6
      assert Goals.days_left(~D[2026-10-31], ~U[2026-10-25 23:00:00Z]) == 5
      # Clocks go forward on 28 Mar 2027 (02:00 CET -> 03:00 CEST).
      assert Goals.days_left(~D[2027-04-30], ~U[2027-03-27 22:59:59Z]) == 34
      assert Goals.days_left(~D[2027-04-30], ~U[2027-03-27 23:00:00Z]) == 33
      assert Goals.days_left(~D[2027-04-30], ~U[2027-03-28 21:59:59Z]) == 33
      assert Goals.days_left(~D[2027-04-30], ~U[2027-03-28 22:00:00Z]) == 32
    end

    test "the north star counts down to the end of April 2027" do
      ns = Goals.strip(~U[2026-10-12 10:00:00Z]).north_star
      assert ns.text == "First paying customer we don't personally know"
      assert ns.target_date == ~D[2027-04-30]
      assert ns.days == 200
      assert ns.countdown == "200 days remaining"
    end

    test "an overdue goal is marked" do
      g = goal!("GX", %{target_date: ~D[2026-10-01]})
      r = row(Goals.strip(~U[2026-10-12 10:00:00Z]), g)
      assert r.overdue
      assert r.countdown == "11 days overdue"
    end
  end

  describe "votes" do
    test "+1, the same again takes it back, -1 needs a reason" do
      g = goal!("GV")
      assert {:ok, g} = Goals.vote(g, @ada, 1)
      assert Goals.score(g) == 1
      assert Goals.vote_of(g, @ada) == 1
      assert {:ok, g} = Goals.vote(g, @ada, 1)
      assert Goals.score(g) == 0

      assert {:error, "A downvote needs a reason." <> _} = Goals.vote(g, @bo, -1)
      assert {:error, _} = Goals.vote(g, @bo, -1, "   ")
      assert {:ok, g} = Goals.vote(g, @bo, -1, "Too vague")
      assert [%{reason: "Too vague", value: -1}] = g.votes
      assert {:ok, g} = Goals.vote(g, @bo, 1)
      assert [%{reason: nil, value: 1}] = g.votes
    end

    test "goals are in score order" do
      a = goal!("GA", %{sort: 1000})
      b = goal!("GB", %{sort: 1001})
      {:ok, _} = Goals.vote(b, @ada, 1)
      {:ok, _} = Goals.vote(b, @bo, 1)
      {:ok, _} = Goals.vote(a, @ada, -1, "Not now")
      keys = Enum.map(Goals.list(), & &1.key)
      assert hd(keys) == "GB"
      assert List.last(keys) == "GA"
    end

    test "bots and the QA session do not vote" do
      g = goal!("GQ")
      assert {:error, _} = Goals.vote(g, "bot:case", 1)
      assert {:error, _} = Goals.vote(g, QaLogin.email(), 1)
    end
  end

  describe "progress" do
    test "Done cards over all cards of the goal; archived cards are not counted" do
      g = goal!("GP")
      card!("Card done one", g, "done")
      card!("Card in ideas", g)
      card!("Card building", g, "building")
      card!("Card archived", g, "archived")
      card!("Card done archived later", g, "archived")
      before = Goals.strip().unassigned
      card!("Card without goal", nil)

      strip = Goals.strip()
      r = row(strip, g)
      assert {r.done, r.total} == {1, 3}
      assert strip.unassigned == before + 1
      assert TalesForgeWeb.TeamGoals.percent(r.done, r.total) == 33
    end
  end

  describe "authorization" do
    test "a founder sets and removes the goal of a card" do
      g = goal!("GF")
      {:ok, idea} = Board.create_idea(@ada, %{"title" => "Goal me"})
      assert {:ok, idea} = Goals.set_card_goal(idea, @bo, g.id)
      assert idea.goal_id == g.id
      assert idea.goal.key == "GF"
      assert {:ok, idea} = Goals.set_card_goal(idea, @bo, "")
      assert idea.goal_id == nil
    end

    test "bots and the QA session cannot change the goal of a card" do
      g = goal!("GN")
      {:ok, idea} = Board.create_idea(@ada, %{"title" => "Not for bots"})

      for actor <- ["bot:case", "bot:bobby", "bot:gentry", QaLogin.email(), {:founder, @ada}, nil] do
        assert {:error, "Only a founder changes the goal of a card."} =
                 Goals.set_card_goal(idea, actor, g.id)
      end

      assert Board.get_idea!(idea.id).goal_id == nil
    end

    test "an unknown goal is refused" do
      {:ok, idea} = Board.create_idea(@ada, %{"title" => "Unknown goal"})

      assert {:error, "That goal is gone."} =
               Goals.set_card_goal(idea, @ada, Ecto.UUID.generate())
    end
  end

  test "the bots' card JSON includes the goal" do
    g = goal!("GJ", %{target_date: ~D[2027-01-31], target_label: "Jan 2027"})
    {:ok, idea} = Board.create_idea(@ada, %{"title" => "Json goal"})
    {:ok, idea} = Goals.set_card_goal(idea, @ada, g.id)

    assert %{"key" => "GJ", "target_date" => "2027-01-31", "id" => id} =
             TalesForge.Board.Api.card(idea)["goal"]

    assert id == g.id

    {:ok, other} = Board.create_idea(@ada, %{"title" => "Json no goal"})
    assert TalesForge.Board.Api.card(Board.get_idea!(other.id))["goal"] == nil
  end
end
