defmodule TalesForgeWeb.CreateCharacterLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias TalesForge.Repo
  alias TalesForge.Schemas
  alias TalesForge.Schemas.{AICall, GameSession}

  setup %{conn: conn} do
    {:ok, conn: log_in_admin(conn)}
  end

  test "the screen needs a signed-in team member" do
    for conn <- [build_conn(), log_in_non_member(build_conn())] do
      assert redirected_to(get(conn, ~p"/new/tin_valley")) =~ "/admin/login"
    end
  end

  defp points(view), do: view |> element("#points-left") |> render() |> text_int()

  defp text_int(html),
    do: ~r/<[^>]+>/ |> Regex.replace(html, "") |> String.trim() |> String.to_integer()

  defp total(view, stat) do
    view
    |> element("#total-#{stat}")
    |> render()
    |> text_int()
  end

  defp to_stats(view) do
    view |> element("#next-stats") |> render_click()
    view
  end

  defp to_name(view) do
    view |> element("#next-skills") |> render_click()
    view |> element("#next-name") |> render_click()
    view
  end

  defp skill_points(view), do: view |> element("#skill-points-left") |> render() |> text_int()
  defp level(view, skill), do: view |> element("#skill-level-#{skill}") |> render() |> text_int()

  describe "the happy path" do
    test "race, class, stats, race bonus, name, then a game with that character", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/new/tin_valley")

      assert html =~ "Create your character"
      assert html =~ "Your first character is free"
      assert html =~ "Coming later: Background · Standing · Origin · Personality"
      refute html =~ "Coming later: Background · Standing · Origin · Occupation"

      view |> element("#race-elf") |> render_click()
      view |> element("#class-ranger") |> render_click()
      assert view |> element("#race-elf[aria-checked=true]") |> has_element?()
      assert view |> element("#class-ranger[aria-checked=true]") |> has_element?()
      # the ranger suggests the hunter occupation
      assert view |> element("#occupation-hunter[aria-checked=true]") |> has_element?()

      to_stats(view)
      # ranger: DEX 14, WIS 13; the elf bonus defaults to WIS (the higher one)
      assert points(view) == 0
      assert total(view, "DEX") == 16
      assert total(view, "WIS") == 14
      assert total(view, "CON") == 11

      view |> element("#pick-INT") |> render_click()
      assert total(view, "INT") == 13
      assert total(view, "WIS") == 13

      view |> element("#dec-CHA") |> render_click()
      assert points(view) == 1
      view |> element("#inc-CON") |> render_click()
      assert points(view) == 0
      assert total(view, "CON") == 12

      view |> element("#next-skills") |> render_click()
      assert has_element?(view, "#skills-step")
      assert level(view, "ranged_combat") == 35
      assert view |> element("#skill-ranged_combat") |> render() =~ "Signature"

      view |> element("#next-name") |> render_click()
      assert has_element?(view, "#name-step")
      assert view |> element("#summary") |> render() =~ "Elf · Ranger · former hunter"
      assert view |> element("#summary-skills") |> render() =~ "Ranged combat 35"
      view |> element("#name-form") |> render_change(%{"name" => "Sela Vorn"})
      assert view |> element("#summary") |> render() =~ "Sela Vorn"

      view |> element("#name-form") |> render_submit(%{"name" => "Sela Vorn"})
      {path, _flash} = assert_redirect(view)
      "/play/" <> session_id = path

      session = TalesForge.GameSessions.get_session!(session_id)
      pc = session.world_state["character"]
      assert session.name == "Tin Valley · Sela Vorn"
      assert pc["id"] == "pc_sela_vorn"
      assert pc["name"] == "Sela Vorn"
      assert pc["race"] == "elf"
      assert pc["class"] == "ranger"

      assert pc["stats"] == %{
               "STR" => 12,
               "DEX" => 16,
               "CON" => 12,
               "INT" => 13,
               "WIS" => 13,
               "CHA" => 11
             }

      row = Repo.get_by!(Schemas.GameCharacter, game_session_id: session.id, controller: "player")
      assert row.slug == "pc_sela_vorn"
      assert row.name == "Sela Vorn"
      assert row.race == "elf"
      assert row.stats.dex == 16
      # ranger package 3/2/1 + elf Ranged Combat +3, Survival +2 + hunter, then the spread
      assert %{"ranged_combat" => 35, "tracking" => 25, "survival" => 25} = row.skills
      assert map_size(row.skills) >= 5
      assert row.origin["source"] == "created"
      refute Repo.get_by(Schemas.GameCharacter, game_session_id: session.id, slug: "elara_voss")

      # creation made no AI calls (none without a session): the first character is free
      assert Repo.aggregate(from(c in AICall, where: is_nil(c.game_session_id)), :count) == 0
    end

    test "Crossroads Hamlet works the same way", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/crossroads_ledger")
      view |> element("#class-warrior") |> render_click()
      view |> to_stats() |> to_name()
      view |> element("#name-form") |> render_submit(%{"name" => "Brann"})
      {"/play/" <> id, _} = assert_redirect(view)

      assert %{"name" => "Brann", "location_id" => "weary_pilgrim"} =
               TalesForge.GameSessions.get_session!(id).world_state["character"]
    end
  end

  describe "the point buy" do
    test "points left update live and the buttons stop at the limits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      to_stats(view)

      # no class: 12s across, 72 of 75
      assert points(view) == 3
      for _ <- 1..3, do: view |> element("#inc-STR") |> render_click()
      assert points(view) == 0
      assert view |> element("#inc-DEX[disabled]") |> has_element?()

      for _ <- 1..9, do: view |> element("#dec-CHA") |> render_click()
      assert view |> element("#dec-CHA[disabled]") |> has_element?()
      assert points(view) == 9

      for _ <- 1..3, do: view |> element("#inc-STR") |> render_click()
      assert view |> element("#inc-STR[disabled]") |> has_element?()
      assert total(view, "STR") == 19
    end

    test "a race bonus past 18 is shown inline and blocks the next step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> element("#race-elf") |> render_click()
      to_stats(view)

      for _ <- 1..3, do: view |> element("#dec-CHA") |> render_click()
      for _ <- 1..5, do: view |> element("#inc-DEX") |> render_click()

      assert view |> element("#stats-errors") |> render() =~
               "DEX would be 19 after the elf modifier (+2); it must be 3–18"

      assert view |> element("#next-skills[disabled]") |> has_element?()
      assert view |> element("#step-skills[disabled]") |> has_element?()
      assert view |> element("#step-name[disabled]") |> has_element?()

      view |> element("#dec-DEX") |> render_click()
      refute has_element?(view, "#stats-errors")
      to_name(view)
      assert has_element?(view, "#name-step")
    end

    test "a stat can't go below 3 even if the event is forced", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      to_stats(view)
      html = render_click(view, "stat", %{"stat" => "STR", "delta" => "-10"})
      assert html =~ "STR must be a whole number from 3 to 18"
      assert total(view, "STR") == 13
    end
  end

  describe "racial bonuses" do
    test "Human picks any two stats; a new pick replaces the oldest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      to_stats(view)

      assert view |> element("#race-bonus") |> render() =~ "+1 to any 2 stats"
      assert view |> element("#pick-STR[aria-pressed=true]") |> has_element?()
      assert view |> element("#pick-DEX[aria-pressed=true]") |> has_element?()

      view |> element("#pick-CHA") |> render_click()
      assert view |> element("#pick-STR[aria-pressed=false]") |> has_element?()
      assert total(view, "STR") == 12
      assert total(view, "CHA") == 13
      assert total(view, "DEX") == 13
    end

    test "a race without a choice shows its fixed modifiers and no picker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> element("#race-dwarf") |> render_click()
      to_stats(view)

      refute has_element?(view, "#race-bonus")
      assert view |> element("#stat-CON") |> render() =~ "+2"
      assert total(view, "CON") == 14
      assert total(view, "CHA") == 11
    end
  end

  describe "past occupation and skills" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> element("#class-warrior") |> render_click()
      %{view: view}
    end

    test "an occupation gives free levels and re-suggests the build", %{view: view} do
      assert view |> element("#occupation-soldier[aria-checked=true]") |> has_element?()
      assert view |> element("#occupation-soldier") |> render() =~ "Melee combat +10"

      view |> element("#occupation-merchant") |> render_click()
      view |> to_stats() |> element("#next-skills") |> render_click()

      # Persuasion 10 from the merchant, Melee Combat 15 from the class package
      assert view |> element("#skill-persuasion") |> render() =~ ~r/>\s*10\s*</
      assert view |> element("#skill-dec-melee_combat") |> has_element?()
      assert skill_points(view) in 0..5
    end

    test "levels cost points, stop at the budget and come back", %{view: view} do
      view |> to_stats() |> element("#next-skills") |> render_click()
      view |> element("#suggest-skills") |> render_click()
      left = skill_points(view)

      # Melee Combat is free at 25 (15 class + 10 soldier); one more step (to 30)
      # makes it a signature skill for 15 points
      assert level(view, "melee_combat") == 25
      assert view |> element("#skill-dec-melee_combat[disabled]") |> has_element?()

      view |> element("#skill-dec-climbing") |> render_click()
      view |> element("#skill-dec-climbing") |> render_click()
      assert skill_points(view) == left + 20

      view |> element("#skill-inc-melee_combat") |> render_click()
      assert level(view, "melee_combat") == 30
      assert skill_points(view) == left + 5
      assert view |> element("#signature-count") |> render() =~ "1"
      assert view |> element("#skill-melee_combat") |> render() =~ "Signature"
    end

    test "too few skills are shown inline and block the name step", %{conn: conn} do
      # no class, laborer: Climbing 2, Unarmed Combat 2, Survival 1 are free
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> to_stats() |> element("#next-skills") |> render_click()

      for %{id: skill} <- TalesForge.CharacterCreation.options("tin_valley").skill_list,
          _ <- 1..7,
          has_element?(view, "#skill-dec-#{skill}:not([disabled])") do
        view |> element("#skill-dec-#{skill}") |> render_click()
      end

      assert view |> element("#skill-count") |> render() =~ "3"
      assert view |> element("#skills-errors") |> render() =~ "Choose at least 5 skills; 3 so far"
      assert view |> element("#next-name[disabled]") |> has_element?()
      assert view |> element("#step-name[disabled]") |> has_element?()

      view |> element("#skill-inc-dodge") |> render_click()
      view |> element("#skill-inc-stealth") |> render_click()
      refute has_element?(view, "#skills-errors")
      view |> element("#next-name") |> render_click()
      assert has_element?(view, "#name-step")
    end

    test "a forced level below the free one is refused", %{view: view} do
      view |> to_stats() |> element("#next-skills") |> render_click()
      html = render_click(view, "skill", %{"skill" => "melee_combat", "delta" => "-3"})
      assert html =~ "Melee combat starts at 25 for free"
    end
  end

  describe "the name" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> to_stats() |> to_name()
      %{view: view}
    end

    test "an empty name is refused inline and starts nothing", %{view: view} do
      count = Repo.aggregate(GameSession, :count)
      html = view |> element("#name-form") |> render_submit(%{"name" => "   "})
      assert html =~ "Type a name"
      assert has_element?(view, "#character-name[aria-invalid=true]")
      assert Repo.aggregate(GameSession, :count) == count
    end

    test "a name over 40 characters is refused inline", %{view: view} do
      html =
        view |> element("#name-form") |> render_change(%{"name" => String.duplicate("a", 41)})

      assert html =~ "A name has at most 40 characters"

      html = view |> element("#name-form") |> render_change(%{"name" => "Wren"})
      refute html =~ "at most 40 characters"
    end
  end

  test "an unknown adventure goes back home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Unknown adventure."}}}} =
             live(conn, ~p"/new/atlantis")
  end

  test "the home page offers creation and the Elara quick start", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Create a character"
    assert html =~ "Quick start as Elara"

    view |> element("#create-tin_valley") |> render_click()
    assert_redirect(view, ~p"/new/tin_valley")

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#quick-tin_valley") |> render_click()
    {"/play/" <> id, _} = assert_redirect(view)
    assert TalesForge.GameSessions.get_session!(id).world_state["character"]["id"] == "elara_voss"
  end

  describe "the dice model" do
    @stats ~w(STR DEX CON INT WIS CHA)

    defp base(view, stat), do: view |> element("#base-#{stat}") |> render() |> text_int()
    defp bases(view), do: Map.new(@stats, &{&1, base(view, &1)})

    defp roll(conn) do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> element("#model-stat_roll") |> render_click()
      to_stats(view)
    end

    test "point buy is the default and the click-through is unchanged", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/new/tin_valley")

      assert html =~ "How you make your stats"
      assert has_element?(view, ~s(#model-point_buy[aria-checked="true"]))
      to_stats(view)
      assert points(view) == 3
      refute has_element?(view, "#stat-roll")

      view |> element("#inc-STR") |> render_click()
      assert points(view) == 2
    end

    test "the roll shows each stat from 3 to 18 and the player cannot set them", %{conn: conn} do
      view = roll(conn)

      assert has_element?(view, "#stat-roll")
      refute has_element?(view, "#points-left")
      refute has_element?(view, "#inc-STR")
      assert Enum.all?(Map.values(bases(view)), &(&1 in 3..18))
    end

    test "exactly one re-roll", %{conn: conn} do
      view = roll(conn)

      view |> element("#reroll") |> render_click()
      refute has_element?(view, "#reroll")
      assert has_element?(view, "#reroll-used")

      assert render_click(view, "reroll", %{}) =~ "You used your re-roll"
      assert Enum.all?(Map.values(bases(view)), &(&1 in 3..18))
    end

    test "a reload keeps the roll and the used re-roll", %{conn: conn} do
      view = roll(conn)
      view |> element("#reroll") |> render_click()
      rolled = bases(view)

      {:ok, reloaded, _html} = live(conn, ~p"/new/tin_valley")
      assert has_element?(reloaded, ~s(#model-stat_roll[aria-checked="true"]))
      to_stats(reloaded)

      assert bases(reloaded) == rolled
      assert has_element?(reloaded, "#reroll-used")
    end

    test "a change to point buy and back gives the same roll", %{conn: conn} do
      view = roll(conn)
      rolled = bases(view)

      view |> element("#step-origin") |> render_click()
      view |> element("#model-point_buy") |> render_click()
      view |> element("#model-stat_roll") |> render_click()
      to_stats(view)

      assert bases(view) == rolled
    end

    test "a point-buy draft without a roll stays out of the store", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> element("#class-warrior") |> render_click()

      assert TalesForge.CharacterDrafts.get("tf-tester", "tin_valley") == nil
      {:ok, _view, html} = live(conn, ~p"/new/tin_valley")
      assert html =~ ~s(id="class-none")
      assert TalesForge.CharacterDrafts.get("tf-tester", "tin_valley") == nil
    end

    test "a rolled character ends with validate and finalize", %{conn: conn} do
      view = roll(conn)
      rolled = bases(view)
      to_name(view)

      view |> form("#name-form", %{"name" => "Dice Wren"}) |> render_submit()
      {"/play/" <> id, _} = assert_redirect(view)

      pc = TalesForge.GameSessions.get_session!(id).world_state["character"]
      assert pc["name"] == "Dice Wren"
      assert Enum.all?(Map.values(pc["stats"]), &(&1 in 3..18))

      row = Repo.get_by!(Schemas.GameCharacter, game_session_id: id, slug: "pc_dice_wren")
      assert row.controller == "player"

      assert TalesForge.CharacterDrafts.get("tf-tester", "tin_valley") == nil
      assert map_size(rolled) == 6
    end
  end

  describe "the description model" do
    alias TalesForge.CharacterTextStub, as: Stub

    defp describe(conn, text \\ "Mira is an elf ranger who hunted deer.") do
      {:ok, view, _html} = live(conn, ~p"/new/tin_valley")
      view |> element("#model-from_text") |> render_click()
      view |> form("#describe-form", %{"description" => text}) |> render_submit()
      render_async(view)
      view
    end

    test "it is a third model next to point buy and the dice", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/new/tin_valley")

      assert html =~ "Describe your character"
      assert has_element?(view, "#model-point_buy")
      assert has_element?(view, "#model-stat_roll")
      view |> element("#model-from_text") |> render_click()
      assert has_element?(view, "#describe-form")
      refute has_element?(view, "#step-stats")
    end

    test "the AI draft shows labels with confidence, and approval leads to play", %{conn: conn} do
      Stub.put(Stub.reply())
      view = describe(conn)

      assert has_element?(view, "#ai-draft")
      assert view |> element("#label-race") |> render() =~ "Elf"
      assert view |> element("#label-race") |> render() =~ "confidence 90%"
      refute render(view) =~ ~r/unsure|uncertain/i

      view |> element("#approve") |> render_click()
      assert has_element?(view, "#name-step")
      assert has_element?(view, ~s(#character-name[value="Mira Vale"]))

      view |> form("#name-form", %{"name" => "Mira Vale"}) |> render_submit()
      {"/play/" <> id, _} = assert_redirect(view)
      pc = TalesForge.GameSessions.get_session!(id).world_state["character"]
      assert {pc["race"], pc["class"]} == {"elf", "ranger"}
      assert TalesForge.CharacterDrafts.get("tf-tester", "tin_valley") == nil
    end

    test "play needs approval: the name step stays closed", %{conn: conn} do
      Stub.put(Stub.reply())
      view = describe(conn)

      render_click(view, "go", %{"step" => "name"})
      refute has_element?(view, "#name-step")
      assert has_element?(view, "#ai-draft")
    end

    test "at most 2 questions, then the draft", %{conn: conn} do
      Stub.put(fn _s, user ->
        if user =~ "Answers",
          do: {:ok, Stub.reply()},
          else: {:ok, Stub.reply(%{"questions" => ["Q one?", "Q two?", "Q three?"]}, 0.3)}
      end)

      view = describe(conn)
      assert has_element?(view, "#answer_0")
      assert has_element?(view, "#answer_1")
      refute has_element?(view, "#answer_2")

      view
      |> form("#questions-form", %{"answer_0" => "Elf", "answer_1" => "Hunter"})
      |> render_submit()

      render_async(view)
      assert has_element?(view, "#ai-draft")
      assert_received {:character_text_call, _}
      assert_received {:character_text_call, _}
    end

    test "a reload keeps the AI draft and makes no new AI call", %{conn: conn} do
      Stub.put(Stub.reply())
      describe(conn)
      assert_received {:character_text_call, _}

      {:ok, reloaded, _html} = live(conn, ~p"/new/tin_valley")
      assert has_element?(reloaded, "#ai-draft")
      refute_received {:character_text_call, _}
    end

    test "an AI error shows a message and keeps the form", %{conn: conn} do
      Stub.put(fn _s, _u -> {:error, :timeout} end)
      view = describe(conn)

      assert has_element?(view, "#text-error")
      assert has_element?(view, "#describe-form")
    end
  end
end
