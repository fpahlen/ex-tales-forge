defmodule TalesForgeWeb.TeamWorkLogLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.{Chat, Repo}
  alias TalesForge.WorkLog.Entry

  test "signed out, the log and the CSV redirect to the login page" do
    assert redirected_to(get(build_conn(), "/team/work-log")) =~ ~r{^/admin/login}
    assert redirected_to(get(build_conn(), "/team/work-log.csv")) =~ ~r{^/admin/login}
  end

  test "the /team menu links the work log", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/team")
    assert has_element?(view, ~s(#team-nav a[href="/team/work-log"]), "Work log")
  end

  test "a founder sees all sessions and adds a manual entry", %{conn: conn} do
    {:ok, _} = Chat.post("other@example.com", "Hello")
    {:ok, view, html} = live(log_in_admin(conn), ~p"/team/work-log")

    assert html =~ "other@example.com"
    assert html =~ "1 action: team chat"

    view
    |> form("#work-log-entry-form",
      entry: %{
        date: Date.to_iso8601(TalesForge.WorkLog.Report.today()),
        hours: "1.5",
        reason: "Design meeting"
      }
    )
    |> render_submit()

    assert [%Entry{founder: "founder@example.com", minutes: 90, added_by: "founder@example.com"}] =
             Repo.all(Entry)

    assert render(view) =~ "Design meeting"
    assert has_element?(view, ~s(#work-log-total-founder\\@example\\.com), "1.50 h")
    assert has_element?(view, ~s(#work-log-pie-founder\\@example\\.com), "1.50")
    assert has_element?(view, ~s(#work-log-pie svg path))
    assert has_element?(view, "#work-log-pie", "%")
  end

  test "an empty log shows no pie", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/team/work-log")
    assert has_element?(view, "#work-log-pie-empty")
  end

  test "a bad entry shows the errors and saves nothing", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/team/work-log")

    html =
      view
      |> form("#work-log-entry-form", entry: %{hours: "", reason: ""})
      |> render_submit()

    assert html =~ "Correct the entry"
    assert Repo.all(Entry) == []
  end

  test "the CSV download", %{conn: conn} do
    {:ok, _} = Chat.post("other@example.com", "Hello")
    today = Date.to_iso8601(TalesForge.WorkLog.Report.today())
    conn = get(log_in_admin(conn), "/team/work-log.csv?from=#{today}&to=#{today}")

    assert response_content_type(conn, :csv) =~ "text/csv"
    assert conn.resp_body =~ "date,founder,auto_hours,manual_hours,total_hours,notes"
    assert conn.resp_body =~ "#{today},other@example.com,0.00"
  end

  test "the CSV refuses a reversed range", %{conn: conn} do
    conn = get(log_in_admin(conn), "/team/work-log.csv?from=2026-10-12&to=2026-10-01")
    assert conn.status == 400
  end
end
