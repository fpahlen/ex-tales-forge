defmodule TalesForgeWeb.AdminLive.CanonReviewLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.Canon
  alias TalesForge.GameSessions
  alias TalesForge.World

  setup %{conn: conn} do
    Application.put_env(:ex_tales_forge, :canon_stub_pid, self())
    on_exit(fn -> Application.delete_env(:ex_tales_forge, :canon_stub_pid) end)

    {:ok, session} = GameSessions.create_session(%{name: "Review Me", adventure_id: "tin_valley"})

    World.store_facts(
      session.id,
      [{"valley_inn", %{"kind" => "fact", "text" => "The inn has a blue door."}}],
      2
    )

    %{session: session, conn: conn}
  end

  test "the founder tools list the session and link to its review", %{
    conn: conn,
    session: session
  } do
    {:ok, _view, html} = live(log_in_admin(conn), ~p"/admin/founders/canon-review")
    assert html =~ "Review Me"
    assert html =~ ~p"/admin/founders/canon-review/#{session.id}"
  end

  test "the review starts only on the button", %{conn: conn, session: session} do
    {:ok, view, html} = live(log_in_admin(conn), ~p"/admin/founders/canon-review/#{session.id}")

    refute html =~ "The inn has a blue door."
    html = view |> element("#start-review") |> render_click()
    assert html =~ "The inn has a blue door."
  end

  test "each action stores the decision with the founder email", %{conn: conn, session: session} do
    {:ok, view, _} =
      live(
        log_in_admin(conn, "fredrik@example.com"),
        ~p"/admin/founders/canon-review/#{session.id}"
      )

    view |> element("#start-review") |> render_click()

    html = view |> element("button", "Add to canon") |> render_click()
    assert html =~ "Added to canon (seed patch proposed) by fredrik@example.com"
    assert html =~ "world_agents.json"

    html = view |> element("button", "Keep as session-only") |> render_click()
    assert html =~ "Kept as session-only by fredrik@example.com"

    html = view |> element("button", "Mark as error") |> render_click()
    assert html =~ "Marked as error by fredrik@example.com"

    assert [%{action: "error", founder: "fredrik@example.com"}] =
             Map.values(Canon.decisions(session.id))
  end

  test "a signed-out visitor gets the login page", %{conn: conn, session: session} do
    assert {:error, {:redirect, %{to: "/admin/login" <> _}}} =
             live(conn, ~p"/admin/founders/canon-review/#{session.id}")
  end
end
