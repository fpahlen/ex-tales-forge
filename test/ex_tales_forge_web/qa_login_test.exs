defmodule TalesForgeWeb.QaLoginTest do
  @moduledoc """
  Gentry's QA sign-in (`TalesForge.QaLogin`, `/team/qa-login`): the token
  checks, the read-only session on `/team` (every write refused on the
  server), no ping or chat-read changes, and no "Online now" entry.
  """

  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.Board
  alias TalesForge.Chat
  alias TalesForge.QaLogin
  alias TalesForge.Repo

  doctest TalesForge.QaLogin

  @token "qa-test-token-0123456789abcdef"

  @tables ~w(board_ideas board_votes board_pings board_transitions board_approvals
             board_links board_comments board_answers team_chat_messages team_chat_reads
             team_images board_deletions board_goal_votes)

  setup do
    Application.put_env(:ex_tales_forge, :qa_login, token: @token)

    on_exit(fn ->
      Application.delete_env(:ex_tales_forge, :qa_login)
      Application.delete_env(:ex_tales_forge, :app_name)
    end)

    :ok
  end

  defp qa_conn(token \\ @token) do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> post("/team/qa-login", %{"token" => token})

    assert redirected_to(conn) == "/team"
    recycle(conn)
  end

  # A fingerprint of every board and chat table: equal before and after means
  # nothing was written.
  defp snapshot do
    for table <- @tables, into: %{} do
      %{rows: [[sum]]} =
        Repo.query!(
          "SELECT md5(coalesce(string_agg(t::text, ',' ORDER BY t::text), '')) FROM #{table} t"
        )

      {table, sum}
    end
  end

  describe "token checks" do
    test "the form shows while the token is set; 404 while it is unset or blank" do
      assert build_conn() |> get("/team/qa-login") |> html_response(200) =~ "QA sign-in"

      for value <- [nil, "", "   "] do
        Application.put_env(:ex_tales_forge, :qa_login, token: value)
        assert build_conn() |> get("/team/qa-login") |> response(404)

        conn = build_conn() |> init_test_session(%{}) |> post("/team/qa-login", %{"token" => ""})
        assert response(conn, 404)
      end
    end

    test "a wrong token gets 401 and no session" do
      for token <- ["wrong", String.slice(@token, 0..-2//1), @token <> "x", String.upcase(@token)] do
        conn =
          build_conn() |> init_test_session(%{}) |> post("/team/qa-login", %{"token" => token})

        assert html_response(conn, 401) =~ "That token is not correct."
        refute QaLogin.valid_session?(conn)
        assert conn |> recycle() |> get("/team") |> redirected_to() =~ ~r{^/admin/login}
      end
    end

    test "a missing or blank token gets 401" do
      for params <- [%{}, %{"token" => ""}, %{"token" => "  "}, %{"token" => ["x"]}] do
        conn = build_conn() |> init_test_session(%{}) |> post("/team/qa-login", params)
        assert response(conn, 401)
      end
    end

    test "the compare is timing safe: SHA-256 digests and Plug.Crypto.secure_compare" do
      assert QaLogin.token_valid?(@token)
      assert QaLogin.token_valid?(" " <> @token <> "\n")
      refute QaLogin.token_valid?("q")
      refute QaLogin.token_valid?(nil)

      source = File.read!("lib/ex_tales_forge/qa_login.ex")
      assert source =~ "Plug.Crypto.secure_compare(:crypto.hash(:sha256, given)"
      refute source =~ ~r/given\s*==\s*expected/
    end

    test "the session holds no token, and a new token ends old sessions" do
      signed_in =
        build_conn() |> init_test_session(%{}) |> post("/team/qa-login", %{"token" => @token})

      refute inspect(get_session(signed_in)) =~ @token
      conn = recycle(signed_in)
      assert conn |> get("/team") |> html_response(200)

      Application.put_env(:ex_tales_forge, :qa_login, token: "a-new-token-value")
      assert conn |> recycle() |> get("/team") |> redirected_to() =~ ~r{^/admin/login}
    end

    test "sign-out ends the QA session" do
      conn = qa_conn() |> delete("/admin/logout") |> recycle()
      assert conn |> get("/team") |> redirected_to() =~ ~r{^/admin/login}
    end
  end

  describe "the QA session" do
    test "opens /team and /team/presentation as Gentry (QA)" do
      conn = qa_conn()
      assert conn |> get("/team") |> html_response(200) =~ "Signed in as Gentry (QA)."
      assert conn |> recycle() |> get("/team/presentation") |> html_response(200)

      {:ok, view, _} = live(conn, "/team")
      assert has_element?(view, "#qa-banner", "cannot change it")
      assert has_element?(view, "#idea-board-live")
      {:ok, pres, _} = live(conn, "/team/presentation")
      assert has_element?(pres, "#qa-banner", "Signed in as Gentry (QA).")
      assert has_element?(pres, "#qa-banner", "cannot change it")
    end

    test "opens /team/work-log read-only: no CSV link, no manual form, add_entry refused" do
      conn = qa_conn()
      assert conn |> get("/team/work-log") |> html_response(200)

      {:ok, view, _} = live(conn, "/team/work-log")
      assert has_element?(view, "#work-log-rows")
      assert has_element?(view, "#work-log-range-form")
      refute has_element?(view, "#work-log-csv")
      refute has_element?(view, "#work-log-add")
      refute has_element?(view, "#work-log-entry-form")

      view
      |> element("#work-log-range-form")
      |> render_submit(%{"range" => %{"from" => "2026-10-01", "to" => "2026-10-09"}})

      refute render(view) =~ QaLogin.refused_message()

      assert render_hook(view, "add_entry", %{
               "entry" => %{
                 "founder" => "x@example.com",
                 "date" => "2026-10-09",
                 "hours" => "1",
                 "reason" => "x"
               }
             }) =~ "read-only"

      assert TalesForge.Repo.aggregate(TalesForge.WorkLog.Entry, :count) == 0

      assert conn |> recycle() |> get("/team/work-log.csv") |> redirected_to() =~
               ~r{^/admin/login}
    end

    test "opens no other page" do
      conn = qa_conn()

      for path <- ["/", "/admin", "/admin/operate/costs", "/new/tin_valley", "/admin/code-docs"] do
        assert conn |> recycle() |> get(path) |> redirected_to() =~ ~r{^/admin/login},
               "#{path} is open to the QA session"
      end

      for path <- ["/", "/admin", "/admin/operate/costs"] do
        assert {:error, {:redirect, %{to: "/admin/login" <> _}}} = live(conn, path)
      end
    end

    test "every write on the board is refused on the server" do
      {:ok, idea} = Board.create_idea("fredrik@whyse.se", %{"title" => "Fishing"})
      {:ok, _} = Board.add_tag(idea, "fredrik@whyse.se", "ux")
      goal = Repo.get_by!(TalesForge.Board.Goal, key: "G3")
      {:ok, idea} = Board.Goals.set_card_goal(idea, "fredrik@whyse.se", goal.id)
      {:ok, view, _} = live(qa_conn(), "/team")
      board = with_target(view, "#idea-board-live")
      before = snapshot()
      id = idea.id

      writes = [
        {"add", %{"idea" => %{"title" => "From QA", "body" => "x"}}},
        {"vote", %{"card_id" => id, "vote" => "1"}},
        {"vote", %{"card_id" => id, "vote" => "-1"}},
        {"downvote", %{"card_id" => id, "reason" => "no"}},
        {"move", %{"card_id" => id, "to" => "parked"}},
        {"step", %{"card_id" => id, "to" => "parked"}},
        {"comment", %{"card_id" => id, "body" => "@hakan hello"}},
        {"answer_pr", %{"card_id" => id, "answer" => "approve"}},
        {"refine", %{"card_id" => id, "refinement" => "x"}},
        {"draft_answers", %{"card_id" => id, "questions" => %{"0" => "x"}}},
        {"toggle_defer", %{"card_id" => id, "question" => "0", "deferred" => "true"}},
        {"save_answers", %{"card_id" => id}},
        {"add_images", %{"card_id" => id}},
        {"add_tag", %{"card_id" => id, "tag" => "qa"}},
        {"remove_tag", %{"card_id" => id, "tag" => "ux"}},
        {"typing", %{"card_id" => id, "body" => "x"}},
        {"archive_start", %{"card_id" => id}},
        {"archive", %{"card_id" => id, "reason" => "spam"}},
        {"restore_card", %{"card_id" => id}},
        {"ask_delete", %{"card_id" => id}},
        {"delete_card", %{"card_id" => id, "title" => "Fishing"}},
        {"goal_vote", %{"goal_id" => goal.id, "vote" => "1"}},
        {"goal_vote", %{"goal_id" => goal.id, "vote" => "-1"}},
        {"goal_downvote", %{"goal_id" => goal.id, "reason" => "no"}},
        {"set_goal", %{"card_id" => id, "goal_id" => goal.id}},
        {"set_goal", %{"card_id" => id, "goal_id" => ""}},
        {"goal_add_card", %{"goal_id" => goal.id, "card_id" => id}},
        {"goal_remove_card", %{"card_id" => id}},
        {"goal_new_card", %{"goal_id" => goal.id, "title" => "From QA"}},
        {"some_new_write", %{"card_id" => id}}
      ]

      for {event, params} <- writes do
        assert render_click(board, event, params) =~ "This QA session is read-only",
               "#{event} is not refused"

        assert snapshot() == before, "#{event} changed the database"
      end

      assert Board.Typing.who() == %{}
    end

    test "the QA session opens a goal and sees its cards, without the goal controls" do
      goal = TalesForge.Repo.get_by!(TalesForge.Board.Goal, key: "G2")
      {:ok, idea} = Board.create_idea("fredrik@whyse.se", %{"title" => "Goal card"})
      {:ok, _} = TalesForge.Board.Goals.set_card_goal(idea, "fredrik@whyse.se", goal.id)
      {:ok, view, _} = live(qa_conn(), "/team")

      view |> element("#goal-#{goal.id}-toggle") |> render_click()
      assert has_element?(view, "#goal-#{goal.id}-card-#{idea.id}", "Goal card")
      refute has_element?(view, "#goal-#{goal.id}-remove-#{idea.id}")
      refute has_element?(view, "#goal-#{goal.id}-add")
      refute has_element?(view, "#goal-#{goal.id}-new")
    end

    test "chat send is refused on the server" do
      {:ok, view, _} = live(qa_conn(), "/team")
      header = find_live_child(view, "team-online")
      chat = find_live_child(header, "team-online-chat")
      before = snapshot()

      render_click(chat, "open", %{})
      render_click(chat, "send", %{"chat" => %{"body" => "hello from QA"}})

      assert snapshot() == before
      assert Chat.recent() == []
    end

    test "viewing a card never clears anyone's inbox items" do
      {:ok, idea} = Board.create_idea("fredrik@whyse.se", %{"title" => "Fishing"})

      {:ok, _} =
        Board.add_comment(idea, "fredrik@whyse.se", "@hakan can you check this?",
          login: "fpahlen"
        )

      [_] = Workflow.Inbox.Store.open("hakan")
      {:ok, view, _} = live(qa_conn(), "/team")
      before = snapshot()

      view |> with_target("#idea-board-live") |> render_click("open", %{"card_id" => idea.id})
      assert has_element?(view, "#board-modal")

      assert [_] = Workflow.Inbox.Store.open("hakan")
      assert snapshot() == before
    end

    test "is not in Online now" do
      {:ok, _view, _} = live(qa_conn(), "/team")
      refute Enum.any?(TalesForge.Online.local(), &(&1["email"] == QaLogin.email()))
    end
  end

  describe "QA_ALLOW_WRITES (off by default)" do
    test "the session is read-only on production and locally, also with the flag on" do
      assert QaLogin.read_only?()
      Application.put_env(:ex_tales_forge, :qa_login, token: @token, allow_writes: true)
      assert QaLogin.read_only?()
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge")
      assert QaLogin.read_only?()
    end

    test "only playtest with the flag on allows writes" do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
      assert QaLogin.read_only?()
      Application.put_env(:ex_tales_forge, :qa_login, token: @token, allow_writes: true)
      refute QaLogin.read_only?()
    end

    test "the sign-in works on playtest too" do
      Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")

      conn =
        build_conn() |> init_test_session(%{}) |> post("/team/qa-login", %{"token" => @token})

      assert redirected_to(conn) == "/team"
      assert QaLogin.valid_session?(conn)
    end
  end
end
