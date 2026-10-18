defmodule TalesForgeWeb.AppComponentsTest do
  @moduledoc false
  # The environment badge and the cross-app links (admin split, 2026-10-10).
  # Sets the global app name, so not async.
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.GameSessions
  alias TalesForgeWeb.AppComponents

  doctest TalesForgeWeb.AppComponents

  setup do
    on_exit(fn -> Application.delete_env(:ex_tales_forge, :app_name) end)
  end

  describe "env_badge/1" do
    test "names the role, colours it, and shows the short commit" do
      html = render_component(&AppComponents.env_badge/1, role: :production, sha: "abcdef1234567")
      assert html =~ "PRODUCTION"
      assert html =~ "abcdef1"
      refute html =~ "abcdef12"
      assert html =~ "bg-red-700"

      html = render_component(&AppComponents.env_badge/1, role: :playtest, sha: nil)
      assert html =~ "PLAYTEST"
      assert html =~ "bg-amber-300"

      assert render_component(&AppComponents.env_badge/1, role: :local) =~ "LOCAL"
    end
  end

  describe "lives_on/1" do
    test "links to the home app, and shows nothing where the page lives" do
      for role <- [:playtest, :production] do
        html =
          render_component(&AppComponents.lives_on/1,
            area: :board,
            path: "/team",
            what: "The idea board",
            role: role
          )

        assert html =~ ~s(href="https://whyse-workflow.fly.dev/team")
        assert html =~ "The idea board lives on Workflow ↗"
      end

      assert render_component(&AppComponents.lives_on/1,
               area: :playtest_runs,
               path: "/admin/play/runs",
               what: "Playtest runs",
               role: :playtest
             ) =~ ~r/^\s*$/
    end
  end

  describe "other_app_link/1" do
    test "same page on the other app; nothing locally" do
      html =
        render_component(&AppComponents.other_app_link/1,
          path: "/admin/play/sessions",
          role: :production
        )

      assert html =~ ~s(href="https://tales-forge-playtest.fly.dev/admin/play/sessions")
      assert html =~ "Same page on playtest ↗"

      html =
        render_component(&AppComponents.other_app_link/1,
          path: "/admin/play/sessions",
          role: :playtest
        )

      assert html =~ "Same page on production ↗"

      assert render_component(&AppComponents.other_app_link/1, path: "/admin", role: :local) =~
               ~r/^\s*$/
    end
  end

  describe "the badge switches to the other app" do
    setup %{conn: conn}, do: {:ok, conn: log_in_admin(conn)}

    test "on production the badge links to the same page on playtest", %{conn: conn} do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge")

      for path <- ["/admin/play/sessions", "/admin/operate/costs"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(
                 view,
                 ~s(a#env-badge[href="https://tales-forge-playtest.fly.dev#{path}"][title="You are on production. Switch to playtest."]),
                 "PRODUCTION"
               )

        assert has_element?(
                 view,
                 "#env-badge .sr-only",
                 "You are on production. Switch to playtest."
               )

        assert has_element?(view, "#env-badge", "⇄")
        assert has_element?(view, "#env-badge.min-h-11")
      end
    end

    test "on playtest the badge links to the same page on production", %{conn: conn} do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
      {:ok, view, _html} = live(conn, ~p"/admin/play/sessions")

      assert has_element?(
               view,
               ~s(a#env-badge[href="https://tales-forge.fly.dev/admin/play/sessions"]),
               "PLAYTEST"
             )

      assert has_element?(
               view,
               "#env-badge .sr-only",
               "You are on playtest. Switch to production."
             )
    end

    test "other admin pages open the other app's admin start page", %{conn: conn} do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge")

      for path <- ["/admin", "/admin/operate/code-heat"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(
                 view,
                 ~s(a#env-badge[href="https://tales-forge-playtest.fly.dev/admin"])
               )
      end

      Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, ~s(a#env-badge[href="https://tales-forge.fly.dev/admin"]))
    end

    test "locally the badge is a label without a link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/play/sessions")
      assert has_element?(view, "span#env-badge", "LOCAL")
      refute has_element?(view, "a#env-badge")
      refute has_element?(view, "#env-badge", "⇄")

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "span#env-badge", "LOCAL")
      refute has_element?(view, "a#env-badge")
    end

    test "the play pages' top bar links to the other app's game list", %{conn: conn} do
      {:ok, session} =
        GameSessions.create_session(%{name: "Switch test", adventure_id: "tin_valley"})

      Application.put_env(:ex_tales_forge, :app_name, "tales-forge")
      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

      assert has_element?(
               view,
               ~s(a#play-env-badge[href="https://tales-forge-playtest.fly.dev/"]),
               "PRODUCTION"
             )

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, ~s(a#env-badge[href="https://tales-forge-playtest.fly.dev/"]))

      Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

      assert has_element?(
               view,
               ~s(a#play-env-badge[href="https://tales-forge.fly.dev/"]),
               "PLAYTEST"
             )
    end
  end

  describe "on the pages" do
    setup %{conn: conn}, do: {:ok, conn: log_in_admin(conn)}

    test "every admin page has the badge; sessions link to the same page on the other app", %{
      conn: conn
    } do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge")
      {:ok, view, _html} = live(conn, ~p"/admin/play/sessions")
      assert has_element?(view, ~s(#env-badge[data-role="production"]), "PRODUCTION")

      assert has_element?(
               view,
               ~s(#other-app-link[href="https://tales-forge-playtest.fly.dev/admin/play/sessions"]),
               "Same page on playtest ↗"
             )

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#env-badge", "PRODUCTION")
      assert has_element?(view, ~s(#lives-on-board[href="https://whyse-workflow.fly.dev/team"]))

      assert has_element?(
               view,
               ~s(#lives-on-runs[href="https://tales-forge-playtest.fly.dev/admin/playtest"]),
               "Playtest runs lives on playtest ↗"
             )
    end

    test "on playtest the badge says so and the home links to the board on Workflow", %{
      conn: conn
    } do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, ~s(#env-badge[data-role="playtest"]), "PLAYTEST")

      assert has_element?(
               view,
               ~s(#lives-on-board[href="https://whyse-workflow.fly.dev/team"]),
               "The idea board lives on Workflow ↗"
             )
    end

    test "telemetry links to the same page on the other app", %{conn: conn} do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge")
      html = conn |> get("/admin/operate/telemetry/home") |> html_response(200)

      assert html =~
               ~s(id="telemetry-other-app" data-cross-app href="https://tales-forge-playtest.fly.dev/admin/operate/telemetry/home")
    end
  end
end
