defmodule TalesForgeWeb.AdminBreadcrumbsTest do
  @moduledoc """
  Every admin page shows the breadcrumbs, Admin > Section > Page
  (`TalesForgeWeb.Layouts.admin_breadcrumbs/1`), drawn from the regroup's
  section map (`TalesForgeWeb.AdminSections.breadcrumbs/3`).
  """
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForgeWeb.AdminSections

  # The admin LiveView routes without path params; the ones with params are
  # covered by `@with_params` below, each with the record it needs.
  defp admin_live_paths do
    TalesForgeWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug and String.starts_with?(&1.path, "/admin")))
    |> Enum.map(& &1.path)
    # The login page has no admin shell; LiveDashboard (telemetry) is a
    # third-party page with its own header.
    |> Enum.reject(&(&1 == "/admin/login" or String.starts_with?(&1, "/admin/operate/telemetry")))
  end

  setup do
    TalesForge.SurveyFixtures.snapshot_only()
    :ok
  end

  defp assert_crumbs(conn, path) do
    {:ok, view, _html} = live(conn, path)
    assert has_element?(view, "#admin-breadcrumbs ol li"), path
    assert has_element?(view, "#admin-breadcrumbs [aria-current=page]"), path
  end

  test "every admin LiveView without params renders the breadcrumbs", %{conn: conn} do
    conn = log_in_admin(conn)
    paths = admin_live_paths() |> Enum.reject(&String.contains?(&1, ":"))
    paths = Enum.reject(paths, &String.contains?(&1, "*"))
    assert "/admin" in paths
    assert length(paths) > 5

    for path <- paths do
      assert_crumbs(conn, path)
    end
  end

  test "every admin LiveView with params renders the breadcrumbs", %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, session} = TalesForge.GameSessions.create_session(%{name: "Crumbs"})
    [npc | _] = TalesForge.Admin.list_npcs(session.id)
    [definition | _] = TalesForge.Admin.list_npc_definitions()

    run =
      TalesForge.Repo.insert!(%TalesForge.Schemas.PlaytestRun{
        game_session_id: session.id,
        persona: "paul",
        module: "tin_valley",
        build: "0.1.0",
        turn_limit: 1,
        status: "finished",
        started_at: ~U[2026-10-06 15:00:00Z]
      })

    paths = %{
      "/admin/founders/canon-review/:id" => "/admin/founders/canon-review/#{session.id}",
      "/admin/play/sessions/:id" => "/admin/play/sessions/#{session.id}",
      "/admin/play/sessions/:id/npcs" => "/admin/play/sessions/#{session.id}/npcs",
      "/admin/play/sessions/:id/npcs/:npc_id" =>
        "/admin/play/sessions/#{session.id}/npcs/#{npc.npc_id}",
      "/admin/play/sessions/:id/turns" => "/admin/play/sessions/#{session.id}/turns",
      "/admin/archive/npc-definitions/:id" => "/admin/archive/npc-definitions/#{definition.id}",
      "/admin/play/runs/:id" => "/admin/play/runs/#{run.id}",
      "/admin/founders/surveys/:id" => "/admin/founders/surveys/founder-survey-3",
      "/admin/founders/surveys/:id/results" => "/admin/founders/surveys/founder-survey-3/results"
    }

    with_params = Enum.filter(admin_live_paths(), &String.contains?(&1, [":", "*"]))

    for route <- with_params do
      path = Map.get(paths, route) || flunk("add an example path for #{route} to this test")
      assert_crumbs(conn, path)
    end
  end

  test "the admin home has its breadcrumb back", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    assert has_element?(view, "#admin-breadcrumbs [aria-current=page]", "Admin")
  end

  test "a section page: Admin > Section > Page, with links up", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin/operate/costs")
    assert has_element?(view, ~s(#admin-breadcrumbs a[href="/admin"]), "Admin")

    assert has_element?(
             view,
             ~s(#admin-breadcrumbs a[href="/admin#section-operate"]),
             "Operate"
           )

    assert has_element?(view, "#admin-breadcrumbs [aria-current=page]", "Costs")
  end

  test "every nav key has a section and a label for its crumb" do
    for section <- AdminSections.sections(), item <- section.items, key = item[:key] do
      assert [{"Admin", "/admin"}, {_, "/admin#section-" <> _}, {label, nil}] =
               AdminSections.breadcrumbs(key)

      assert String.starts_with?(item.label, label)
    end
  end
end
