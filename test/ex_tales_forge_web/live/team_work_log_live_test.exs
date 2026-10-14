defmodule TalesForgeWeb.TeamWorkLogLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.Chat
  alias TalesForge.Workflow.Repo
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
        founders: ["fredrik@whyse.se"],
        date: Date.to_iso8601(TalesForge.WorkLog.Report.today()),
        hours: "1.5",
        reason: "Design meeting"
      }
    )
    |> render_submit()

    assert [%Entry{founder: "fredrik@whyse.se", minutes: 90, added_by: "founder@example.com"}] =
             Repo.all(Entry)

    assert render(view) =~ "Saved 1 entry: 1.50 h each for Fredrik."
    assert render(view) =~ "Design meeting"
    assert has_element?(view, ~s(#work-log-total-fredrik\\@whyse\\.se), "1.50 h")
    assert has_element?(view, ~s(#work-log-pie svg path))
    assert has_element?(view, "#work-log-pie", "%")
  end

  test "the form shows a checkbox with the name of each founder and today's date", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/team/work-log")

    for name <- ~w(Fredrik Thobias Håkan Jeanette),
        do: assert(has_element?(view, "#work-log-entry-founders label", name))

    assert has_element?(
             view,
             ~s(#work-log-entry-form input[type="date"][value="#{TalesForge.WorkLog.Report.today()}"])
           )
  end

  test "one save adds one entry for each picked founder", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/team/work-log")

    html =
      view
      |> form("#work-log-entry-form",
        entry: %{
          founders: ["fredrik@whyse.se", "jeanette@pahlen.net", "hawkan.fredriksson@gmail.com"],
          date: "2026-03-09",
          hours: "12",
          reason: "Coding weekend"
        }
      )
      |> render_submit()

    assert html =~ "Saved 3 entries: 12.00 h each for Fredrik, Jeanette, Håkan."

    assert Repo.all(Entry) |> Enum.map(& &1.founder) |> Enum.sort() ==
             ~w(fredrik@whyse.se hawkan.fredriksson@gmail.com jeanette@pahlen.net)

    assert Repo.all(Entry) |> Enum.all?(&(&1.added_by == "founder@example.com"))
  end

  test "no founder picked: the form asks for one and saves nothing", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/team/work-log")

    html =
      view
      |> form("#work-log-entry-form", entry: %{hours: "2", reason: "Planning"})
      |> render_submit()

    assert html =~ "Pick one or more founders."
    assert Repo.all(Entry) == []
  end

  test "hours must be more than 0 and at most 24; a bad entry saves nothing", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/team/work-log")

    for hours <- ["0", "25", ""] do
      html =
        view
        |> form("#work-log-entry-form",
          entry: %{
            founders: ["fredrik@whyse.se", "jeanette@pahlen.net"],
            hours: hours,
            reason: "Planning"
          }
        )
        |> render_submit()

      assert html =~ "Correct the entry"
    end

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
