defmodule TalesForgeWeb.TeamGoalsLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.Board
  alias TalesForge.Board.Goal
  alias TalesForge.Workflow.Repo

  doctest TalesForgeWeb.TeamGoals

  setup %{conn: conn}, do: {:ok, conn: log_in_admin(conn)}

  defp g2, do: Repo.get_by!(Goal, key: "G2")

  test "the strip: north star, goals, progress, countdown, Unassigned", %{conn: conn} do
    {:ok, view, _} = live(conn, "/team")

    assert has_element?(
             view,
             "#board-north-star",
             "First paying customer we don't personally know"
           )

    assert has_element?(view, "#board-north-star-countdown")

    assert has_element?(
             view,
             ~s(#goal-#{g2().id}[data-key="G2"]),
             "Playable game on the Elixir rewrite"
           )

    assert has_element?(view, ~s(#goal-#{g2().id} [role="progressbar"]))
    assert has_element?(view, ~s(#goal-#{g2().id} [data-role="countdown"]))
    assert has_element?(view, "#board-goals-unassigned")
    assert has_element?(view, ~s(#goal-#{g2().id} [data-role="score"]), "0")
  end

  test "goals sort by score, then sort order; the score shows", %{conn: conn} do
    g5 = Repo.get_by!(Goal, key: "G5")
    {:ok, view, _} = live(conn, "/team")
    view |> element("#goal-#{g5.id}-up") |> render_click()
    assert has_element?(view, ~s(#goal-#{g5.id} [data-role="score"]), "+1")

    keys =
      view |> render() |> then(&Regex.scan(~r/data-key="(G\d+)"/, &1)) |> Enum.map(&List.last/1)

    assert hd(keys) == "G5"
    assert tl(keys) == Enum.sort_by(tl(keys), &String.to_integer(String.trim_leading(&1, "G")))
  end

  test "a goal downvote needs a reason", %{conn: conn} do
    g = g2()
    {:ok, view, _} = live(conn, "/team")
    view |> element("#goal-#{g.id}-down") |> render_click()
    assert has_element?(view, "#goal-#{g.id}-downvote")
    view |> form("#goal-#{g.id}-downvote", %{reason: "Too big"}) |> render_submit()
    assert has_element?(view, ~s(#goal-#{g.id}-down[aria-pressed="true"]))
    view |> element("#goal-#{g.id}-up") |> render_click()
    assert has_element?(view, ~s(#goal-#{g.id}-up[aria-pressed="true"]))
  end

  test "a founder changes the goal on the card", %{conn: conn} do
    {:ok, idea} = Board.create_idea("bo@example.com", %{"title" => "Pick a goal"})
    g = g2()
    {:ok, view, _} = live(conn, "/team")
    view |> element("#tile-#{idea.id} button[aria-haspopup]") |> render_click()
    view |> form("#card-#{idea.id}-goal-form", %{goal_id: g.id}) |> render_change()
    assert Board.get_idea!(idea.id).goal_id == g.id
  end

  describe "an open goal" do
    test "Show cards is disabled in the static render and enabled when the LiveView connects",
         %{conn: conn} do
      g = g2()
      static = conn |> get("/team") |> html_response(200)
      assert static =~ ~r/id="goal-#{g.id}-toggle"[^>]*disabled/

      {:ok, view, _} = live(conn, "/team")
      assert has_element?(view, "#goal-#{g.id}-toggle:not([disabled])")
    end

    test "the phone sheet has the scroll-lock hook", %{conn: conn} do
      g = g2()
      {:ok, view, _} = live(conn, "/team")
      view |> element("#goal-#{g.id}-toggle") |> render_click()
      assert has_element?(view, ~s(#goal-#{g.id}-cards[phx-hook$="GoalSheetScrollLock"]))
    end

    test "lists its cards with the column; Done cards are not listed", %{conn: conn} do
      g = g2()
      {:ok, parked} = Board.create_idea("bo@example.com", %{"title" => "Parked card"})
      {:ok, done} = Board.create_idea("bo@example.com", %{"title" => "Done card"})

      for {idea, column} <- [{parked, "parked"}, {done, "done"}] do
        idea |> Ecto.Changeset.change(goal_id: g.id, column: column) |> Repo.update!()
      end

      {:ok, view, _} = live(conn, "/team")
      refute has_element?(view, "#goal-#{g.id}-cards")
      view |> element("#goal-#{g.id}-toggle") |> render_click()
      assert has_element?(view, ~s(#goal-#{g.id}-toggle[aria-expanded="true"]))

      assert has_element?(
               view,
               ~s(#goal-#{g.id}-card-#{parked.id}[data-column="parked"]),
               "Parked card"
             )

      assert has_element?(
               view,
               ~s(#goal-#{g.id}-card-#{parked.id} [data-role="column"]),
               "Parked"
             )

      refute has_element?(view, "#goal-#{g.id}-card-#{done.id}")
      view |> element("#goal-#{g.id}-toggle") |> render_click()
      refute has_element?(view, "#goal-#{g.id}-cards")
    end

    test "a founder adds and removes a card; progress follows", %{conn: conn} do
      g = g2()
      {:ok, idea} = Board.create_idea("bo@example.com", %{"title" => "Loose card"})
      {:ok, view, _} = live(conn, "/team")
      view |> element("#goal-#{g.id}-toggle") |> render_click()
      before = TalesForge.Board.Goals.strip().goals |> Enum.find(&(&1.goal.id == g.id))

      view |> form("#goal-#{g.id}-add", %{card_id: idea.id}) |> render_submit()
      assert Board.get_idea!(idea.id).goal_id == g.id
      assert has_element?(view, "#goal-#{g.id}-card-#{idea.id}", "Loose card")

      assert has_element?(
               view,
               ~s(#goal-#{g.id} [data-role="progress"]),
               "of #{before.total + 1} done"
             )

      view |> element("#goal-#{g.id}-remove-#{idea.id}") |> render_click()
      assert Board.get_idea!(idea.id).goal_id == nil
      refute has_element?(view, "#goal-#{g.id}-card-#{idea.id}")
    end

    test "a founder creates a new Idea card with the goal set", %{conn: conn} do
      g = g2()
      {:ok, view, _} = live(conn, "/team")
      view |> element("#goal-#{g.id}-toggle") |> render_click()
      view |> form("#goal-#{g.id}-new", %{title: "Fresh goal card"}) |> render_submit()

      idea = Repo.get_by!(TalesForge.Board.Idea, title: "Fresh goal card")
      assert idea.goal_id == g.id
      assert idea.column == "ideas"
      assert has_element?(view, "#goal-#{g.id}-card-#{idea.id}", "Fresh goal card")
    end

    test "on a phone the open goal is a full-screen sheet with a close button", %{conn: conn} do
      g = g2()
      {:ok, view, _} = live(conn, "/team")
      view |> element("#goal-#{g.id}-toggle") |> render_click()
      assert has_element?(view, "#goal-#{g.id}-cards.fixed.inset-0")
      view |> element("#goal-#{g.id}-close") |> render_click()
      refute has_element?(view, "#goal-#{g.id}-cards")
    end
  end

  test "bots and the QA session cannot change the goal of a card" do
    {:ok, idea} = Board.create_idea("bo@example.com", %{"title" => "Guarded"})
    g = g2()

    assert {:error, _} = TalesForge.Board.Goals.set_card_goal(idea, "bot:bobby", g.id)

    assert {:error, _} =
             TalesForge.Board.Goals.set_card_goal(idea, TalesForge.QaLogin.email(), g.id)

    assert Board.get_idea!(idea.id).goal_id == nil
  end
end
