defmodule TalesForgeWeb.PlayLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, Turn}

  setup %{conn: conn} do
    {:ok, conn: log_in_admin(conn)}
  end

  test "play surface hides skill, roll, outcome, and LP", %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Living Tin Valley", adventure_id: "tin_valley"})

    {:ok, _view, html} = live(conn, ~p"/play/#{session.id}")

    assert html =~ "Time"
    assert html =~ "Location"
    assert html =~ "wounds"
    assert html =~ "Coins"
    assert html =~ "Inventory"
    assert html =~ "Brenna"
    refute html =~ "fee_copper"

    refute_sheet(html)

    assert {:ok, %{status: :processing}} =
             GameSessions.submit_message(session.id, "search the inn")

    turn =
      Turn
      |> Repo.all()
      |> Enum.find(&(&1.game_session_id == session.id))

    assert is_integer(turn.mechanical_resolution["roll"])

    assert turn.mechanical_resolution["outcome"] in [
             "critical_success",
             "success",
             "partial_success",
             "failure",
             "critical_failure"
           ]

    {:ok, _view, html} = live(conn, ~p"/play/#{session.id}")
    refute_sheet(html)
  end

  describe "d100 rolls and skills (QA 2026-10-14 21:15)" do
    test "the GM text shows the roll line, the panel shows the skills and the coins converted up",
         %{conn: conn} do
      {:ok, session} =
        GameSessions.create_session(%{name: "Rolla", adventure_id: "tin_valley"})

      world =
        session.world_state
        |> put_in(["character", "coins"], %{"gold" => 0, "silver" => 20, "copper" => 300})
        |> put_in(["character", "skills"], %{"climbing" => 25, "stealth" => 5})

      session |> GameSession.changeset(%{world_state: world}) |> save_session!()

      Repo.insert!(%Turn{
        game_session_id: session.id,
        turn_number: 1,
        player_action: "I try to climb down the timber frame into the shaft.",
        narrative: "Your boot slips on the wet timber.",
        mechanical_resolution: %{
          "skill" => "climbing",
          "roll" => 85,
          "effective_skill" => 25,
          "outcome" => "failure",
          "improvements" => [
            %{
              "skill" => "climbing",
              "roll" => 70,
              "raw_skill" => 20,
              "improved" => true,
              "gain" => 5
            }
          ]
        }
      })

      {:ok, view, html} = live(conn, ~p"/play/#{session.id}")

      assert has_element?(view, "[data-roll-line]", "Climbing: d100 85 vs 25: failure.")
      assert has_element?(view, "[data-roll-line]", "Skill improved: climbing +5 (20 to 25)")
      assert has_element?(view, "#character-skills [data-skill=climbing]")
      assert has_element?(view, "#character-skills [data-skill=stealth]")
      assert html =~ "1g 0s 0c"
      refute html =~ "300c"
    end
  end

  test "dead session disables play input", %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Dead Elara", adventure_id: "tin_valley"})

    world = put_in(session.world_state, ["character", "vitality"], "dead")

    session
    |> GameSession.changeset(%{status: "dead", world_state: world})
    |> save_session!()

    {:ok, view, html} = live(conn, ~p"/play/#{session.id}")

    assert html =~ "You are dead."
    assert html =~ "dead"
    assert has_element?(view, "input[name=message][disabled]")
    assert has_element?(view, "button[type=submit][disabled]")
  end

  test "re-rendering mid-turn keeps the GM placeholder out of the stream", %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Thinking Tin Valley", adventure_id: "tin_valley"})

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

    send(view.pid, {:turn_processing, %{}})
    assert has_element?(view, "#gm-streaming [data-gm-dots]")

    # A stream insert while the placeholder is showing used to raise
    # "setting phx-update to \"stream\" requires setting an ID on each child".
    send(
      view.pid,
      {:npc_initiative,
       %{npc_id: "brenna", npc_name: "Brenna", world_tick: 1, text: "Brenna waves."}}
    )

    html = render(view)
    assert html =~ "Brenna waves."
    assert has_element?(view, "#gm-streaming [data-gm-dots]")
    refute has_element?(view, "#narrative-log > p")

    send(view.pid, {:turn_failed, "boom"})
    refute has_element?(view, "#gm-streaming")
  end

  describe "the streamed GM reply (docs/design-gm-streaming.md, PR 2)" do
    setup do
      on_exit(fn ->
        System.delete_env("GM_MIN_DELAY_MS")
        System.delete_env("GM_REVEAL_MIN_MS_PER_CHAR")
      end)
    end

    test "the typing dots show after a submit, in place of a thinking line", %{conn: conn} do
      {:ok, session} =
        GameSessions.create_session(%{name: "Dots Tin Valley", adventure_id: "tin_valley"})

      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")
      refute has_element?(view, "#gm-streaming")

      send(view.pid, {:turn_processing, %{}})
      assert has_element?(view, ~s(#gm-streaming[phx-hook$="GmReveal"][phx-update="ignore"]))
      assert has_element?(view, ~s(#gm-streaming .gm-typing[aria-hidden="true"]))
      assert has_element?(view, ~s(#gm-streaming [role="status"]), "The story continues…")
      refute render(view) =~ "The GM is thinking…"
    end

    test "the reveal hook gets the pacing config as data attributes", %{conn: conn} do
      {:ok, session} =
        GameSessions.create_session(%{name: "Pace Tin Valley", adventure_id: "tin_valley"})

      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")
      send(view.pid, {:turn_processing, %{}})

      assert has_element?(
               view,
               ~s(#gm-streaming[data-min-delay-ms="1500"][data-min-ms-per-char="8"])
             )

      # Playtest sets them in fly.playtest.toml; the page reads them at mount.
      System.put_env("GM_MIN_DELAY_MS", "2000")
      System.put_env("GM_REVEAL_MIN_MS_PER_CHAR", "5")
      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")
      send(view.pid, {:turn_processing, %{}})

      assert has_element?(
               view,
               ~s(#gm-streaming[data-min-delay-ms="2000"][data-min-ms-per-char="5"])
             )
    end

    test "each streamed chunk is pushed to the hook, and a retry pushes empty text",
         %{conn: conn} do
      {:ok, session} =
        GameSessions.create_session(%{name: "Streaming Tin Valley", adventure_id: "tin_valley"})

      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

      send(view.pid, {:turn_processing, %{}})
      send(view.pid, {:turn_stream, {:text, "The lamp"}})
      assert_push_event(view, "gm_text", %{text: "The lamp"})
      send(view.pid, {:turn_stream, {:text, "The lamp gutters."}})
      assert_push_event(view, "gm_text", %{text: "The lamp gutters."})

      # The hook owns the text: the server renders no copy of it.
      assert has_element?(view, "#gm-streaming")
      refute render(view) =~ "The lamp gutters."

      # A JSON retry: the hook clears the old text and shows the dots again.
      send(view.pid, {:turn_stream, :reset})
      assert_push_event(view, "gm_text", %{text: ""})
      send(view.pid, {:turn_stream, {:text, "Rain falls."}})
      assert_push_event(view, "gm_text", %{text: "Rain falls."})

      send(view.pid, {:turn_failed, "boom"})
      refute has_element?(view, "#gm-streaming")
    end

    test "input stays locked until the commit, and the committed entry replaces the streamed one",
         %{conn: conn} do
      {:ok, session} =
        GameSessions.create_session(%{name: "Commit Tin Valley", adventure_id: "tin_valley"})

      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

      send(view.pid, {:turn_processing, %{}})
      send(view.pid, {:turn_stream, {:text, "The lamp gutters."}})
      assert_push_event(view, "gm_text", %{text: "The lamp gutters."})
      assert has_element?(view, "input[name=message][disabled]")
      assert has_element?(view, "#act-button[disabled]", "GM is writing…")

      # The commit: the GM entry has the full text and replaces the streamed one.
      send(
        view.pid,
        {:turn_completed,
         %{
           world_state: session.world_state,
           llm_source: "mock",
           entries: [%{id: "t1-gm", role: "gm", text: "The lamp gutters. Rain falls."}]
         }}
      )

      refute has_element?(view, "#gm-streaming")
      assert has_element?(view, "#entries-t1-gm", "The lamp gutters. Rain falls.")
      refute has_element?(view, "input[name=message][disabled]")
      assert has_element?(view, "#act-button:not([disabled])", "Act")
    end
  end

  # Gentry QA 2026-10-21 (playtest 9b08e77): the empty-submit toast never
  # cleared. It was an error flash, and only info flashes close themselves.
  test "an empty submit says so in a toast that closes itself", %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Empty Tin Valley", adventure_id: "tin_valley"})

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")
    view |> form("#action-form", %{message: "   "}) |> render_submit()

    assert has_element?(view, "#flash-info[data-autohide-ms]", "Say something first.")
    refute has_element?(view, "#flash-error")
  end

  test "the player's action shows as soon as it is sent, above the GM text",
       %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Asking Tin Valley", adventure_id: "tin_valley"})

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

    # The reply to the submit is the page before any turn message: the action
    # shows in the story, and the input stays disabled while the turn runs.
    html =
      view
      |> form("#action-form", %{message: "I ask Mags about the missing cart."})
      |> render_submit()

    pending = html |> LazyHTML.from_fragment() |> LazyHTML.query("#entries-pending-player")
    assert LazyHTML.text(pending) =~ "You"
    assert LazyHTML.text(pending) =~ "I ask Mags about the missing cart."
    assert html =~ ~r/<input[^>]*name="message"[^>]*disabled/

    # The turn completes (the mock GM runs inline): the turn's own player entry
    # replaces the pending one, so the action shows one time.
    done_html = render(view)
    refute has_element?(view, "#entries-pending-player")
    assert has_element?(view, "[id$='-player']", "I ask Mags about the missing cart.")
    assert length(String.split(done_html, ">I ask Mags about the missing cart.<")) == 2
  end

  test "the streamed GM text comes after the player's action, with its heading",
       %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Order Tin Valley", adventure_id: "tin_valley"})

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

    send(
      view.pid,
      {:npc_initiative, %{npc_id: "mags", npc_name: "Mags", world_tick: 1, text: "Mags waits."}}
    )

    send(view.pid, {:turn_processing, %{}})
    send(view.pid, {:turn_stream, {:text, "Mags turns."}})
    html = render(view)

    assert has_element?(view, "#gm-streaming [data-gm-heading]", "Game Master")
    assert_push_event(view, "gm_text", %{text: "Mags turns."})
    {log_at, _} = :binary.match(html, "Mags waits.")
    {gm_at, _} = :binary.match(html, ~s(id="gm-streaming"))
    assert log_at < gm_at
  end

  test "the action form is disabled until the page connects", %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Loading Tin Valley", adventure_id: "tin_valley"})

    # The first HTML comes before the socket joins. A submit at that time goes
    # nowhere, so the input and Act are disabled until the join.
    html = conn |> get(~p"/play/#{session.id}") |> html_response(200)
    assert html =~ ~r/<input[^>]*name="message"[^>]*disabled/

    assert html =~
             ~r/<button[^>]*id="act-button"[^>]*disabled|<button[^>]*disabled[^>]*id="act-button"/

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")
    refute has_element?(view, "input[name=message][disabled]")
    refute has_element?(view, "#act-button[disabled]")
  end

  test "a spend cap shows a calm message, not a failure", %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Capped Tin Valley", adventure_id: "tin_valley"})

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

    send(view.pid, {:turn_processing, %{}})
    send(view.pid, {:turn_failed, {:spend_cap, :day}})

    html = render(view)
    assert html =~ "resting until tomorrow"
    refute html =~ "Turn failed"
    refute has_element?(view, "#gm-streaming")
  end

  describe "clarification questions" do
    import TalesForge.PlaytestHelpers

    setup do
      on_exit(fn ->
        System.put_env("LLM_PROVIDER", "mock")
        System.delete_env("XAI_API_KEY")
      end)

      {:ok, session} =
        GameSessions.create_session(%{name: "Which way", adventure_id: "tin_valley"})

      # The intent step asked back; the player's words are kept with the
      # pending question on the session.
      put_pending_clarification(session.id, clarifying_intent(), "I go over there.")

      {:ok, session: session}
    end

    test "the question survives a reload, and an option plays the words it asked about",
         %{conn: conn, session: session} do
      # A fresh mount is a reload: the question comes back from the session.
      {:ok, view, html} = live(conn, ~p"/play/#{session.id}")
      assert html =~ "Which way?"
      assert has_element?(view, ~s(button[phx-value-option_id="inn"]), "Ask the innkeeper")

      view |> element(~s(button[phx-value-option_id="inn"])) |> render_click()

      html = render(view)
      refute html =~ "Say something first."
      refute html =~ "Which way?"

      assert [%Turn{player_action: "I go over there."}] =
               Turn |> Repo.all() |> Enum.filter(&(&1.game_session_id == session.id))

      refute Map.has_key?(
               GameSessions.get_session!(session.id).world_state,
               "pending_clarification"
             )
    end

    test "the question also appears live, without a reload", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

      question =
        GameSessions.pending_clarification(GameSessions.get_session!(session.id).world_state)

      send(view.pid, {:clarification_needed, Map.put(question, "question", "Left or right?")})
      assert render(view) =~ "Left or right?"
    end

    test "an option of a question that has passed asks for a new action",
         %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

      session = GameSessions.get_session!(session.id)
      world = Map.delete(session.world_state, "pending_clarification")
      session |> GameSession.changeset(%{world_state: world}) |> save_session!()

      view |> element(~s(button[phx-value-option_id="inn"])) |> render_click()

      html = render(view)
      assert html =~ "That question has passed."
      refute html =~ "Which way?"
      refute html =~ "Say something first."
    end
  end

  test "Act reads GM is writing… with the dots and is disabled while a turn is in flight",
       %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Busy Tin Valley", adventure_id: "tin_valley"})

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")
    assert has_element?(view, "#act-button:not([disabled])", "Act")

    send(view.pid, {:turn_processing, %{}})
    assert has_element?(view, ~s(#act-button[disabled][aria-busy="true"]), "GM is writing…")
    assert has_element?(view, ~s(#act-button[phx-disable-with="GM is writing…"]))
    assert has_element?(view, ~s(#act-button .gm-typing[aria-hidden="true"]))
    assert has_element?(view, "input[name=message][disabled]")

    send(view.pid, {:turn_failed, "boom"})
    assert has_element?(view, "#act-button:not([disabled])", "Act")
  end

  test "the story fills the phone screen and has a New text below button", %{conn: conn} do
    {:ok, session} =
      GameSessions.create_session(%{name: "Scroll Tin Valley", adventure_id: "tin_valley"})

    {:ok, view, _html} = live(conn, ~p"/play/#{session.id}")

    assert has_element?(view, "#story-column[class*='100dvh']")
    assert has_element?(view, "#story-scroll[phx-hook=StoryScroll]")

    assert has_element?(
             view,
             ~s(#story-new-text-region[phx-update="ignore"][aria-live="polite"] #story-new-text[hidden][aria-controls="story-scroll"]),
             "New text below"
           )
  end

  defp clarifying_intent do
    %{
      "overall_intent" => "go somewhere",
      "actions" => [
        %{"action_type" => "speak", "target" => "innkeep", "parameters" => %{}},
        %{"action_type" => "move", "target" => "market_square", "parameters" => %{}}
      ],
      "primary_index" => 0,
      "confidence" => 0.4,
      "needs_clarification" => true,
      "clarification_question" => "Which way?",
      "clarification_options" => [
        %{"id" => "inn", "label" => "Ask the innkeeper", "action_index" => 0},
        %{"id" => "square", "label" => "Walk to the square", "action_index" => 1}
      ]
    }
  end

  # Checks rendered text only. Matching raw HTML also hits attributes, and the
  # random data-phx-session / csrf tokens occasionally contain e.g. "XP".
  defp refute_sheet(html) do
    text = visible_text(html)
    # Guard against an empty extraction making every refute pass.
    assert text =~ "Location"

    refute text =~ "Skill:"
    refute text =~ "Outcome:"
    refute text =~ "Roll:"
    refute text =~ "+LP"
    refute text =~ "Learning points"
    refute text =~ "insight +2"
    refute text =~ "you learned"
    refute text =~ ~r/\bXP\b/
    refute text =~ "learning_failures"
  end

  defp visible_text(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("body")
    |> LazyHTML.to_tree()
    |> LazyHTML.Tree.postwalk(fn
      {tag, _attrs, _children} when tag in ["script", "style", "template"] -> []
      node -> node
    end)
    |> LazyHTML.from_tree()
    |> LazyHTML.text(separator: " ")
  end
end
