defmodule TalesForgeWeb.TeamGoalsLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.Board
  alias TalesForge.Board.Goal
  alias TalesForge.Repo

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
end
