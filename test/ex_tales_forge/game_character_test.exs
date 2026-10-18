defmodule TalesForge.GameCharacterTest do
  @moduledoc """
  Refactor step 10b-2: the player character's `characters` row is its only
  stored copy. `game_sessions.world_state` is saved without `"character"`,
  and a loaded session gets the sheet back from the row. The proof that
  nothing changes:

    * the row is lossless: `to_sheet/1` of the row is the sheet the turn
      played, after every turn (`===`, so `5` is not `5.0`);
    * a session stored before 10b-2 plays on its stored sheet, and its next
      save moves it to the row.
  """
  use TalesForge.DataCase, async: false

  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Characters
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameCharacter
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  doctest TalesForge.GameCharacter

  # A script that changes every part of the sheet: skills and learning
  # points (checks), coins and inventory (buy), equipped (equip), location
  # (move), rest growth (sleep) and wounds (a fight).
  @script [
    {"I study the regulars", :observe, nil, %{"skill" => "insight"}},
    {"I buy a mug of ale", :buy, "innkeep", %{"item_id" => "ale_mug"}},
    {"I ask the innkeep about the orcs", :speak, "innkeep", %{}},
    {"I ready my hunting knife", :equip, "hunting_knife", %{}},
    {"I head out to the market square", :move, "market_square", %{}},
    {"I try to climb the market cross", :other, nil, %{"skill" => "climbing"}},
    {"I punch the steward", :combat, "guild_steward", %{}},
    {"I go back to the inn", :move, "valley_inn", %{}},
    {"I sleep until morning", :rest, nil, %{"sleep_ticks" => 32}}
  ]

  setup do
    on_exit(fn ->
      System.delete_env("XAI_API_KEY")
      System.put_env("LLM_PROVIDER", "mock")
    end)

    test_pid = self()

    stub_llm(fn
      :gm, user, system ->
        send(test_pid, {:gm_prompt, system, user})
        %{"narrative" => "The valley goes on.", "gm_notes" => "n"}

      _kind, _user, _system ->
        :default
    end)

    :ok
  end

  defp action({text, type, target, params}) do
    %{
      "overall_intent" => text,
      "action" => %{
        "action_type" => Atom.to_string(type),
        "target" => target,
        "parameters" => params
      },
      "deferred_actions" => [],
      "confidence" => 0.9
    }
  end

  defp row_sheet(session_id), do: Characters.player_sheets([session_id])[session_id]

  defp stored_world(session_id), do: Repo.get!(GameSession, session_id).world_state

  # Saves the session with `sheet` as its player character, the way the turn
  # and the admin edit do: the session and the rows in one Multi.
  defp save_sheet(%GameSession{} = session, sheet) do
    session
    |> GameSession.changeset(%{world_state: Map.put(session.world_state, "character", sheet)})
    |> save_session!()
  end

  # Plays the script. Each turn gives the GM prompt, the world the turn
  # stored, the session as a page loads it, and the row's sheet, with the
  # session id taken out.
  defp play do
    :rand.seed(:exsss, {10, 20, 30})
    {:ok, session} = GameSessions.create_session(%{name: "Golden", adventure_id: "tin_valley"})

    Enum.map(@script, fn {text, _, _, _} = step ->
      {:ok, _} = TurnProcessor.run(session.id, {text, action(step)})
      assert_received {:gm_prompt, system, user}

      {system, user, stored_world(session.id), GameSessions.get_session!(session.id).world_state,
       row_sheet(session.id)}
      |> :erlang.term_to_binary()
      |> :binary.replace(session.id, "SESSION", [:global])
      |> :erlang.binary_to_term()
    end)
  end

  test "the row is the only stored sheet, and a loaded session plays on it" do
    turns = play()
    assert length(turns) == length(@script)

    for {_system, _user, stored, loaded, sheet} <- turns do
      refute Map.has_key?(stored, "character")
      assert loaded === Map.put(stored, "character", sheet)
    end

    # The script changed the sheet: coins (the ale), the equipped knife,
    # the fight and the rest are all in the last row.
    {_, _, _, _, first} = hd(turns)
    {_, _, _, _, last} = List.last(turns)
    assert first["coins"] != last["coins"]
    assert Enum.any?(last["inventory"], &(&1["equipped"] == true))
    assert first != last
  end

  test "a sheet with keys the columns lack round-trips through the row" do
    {:ok, session} = GameSessions.create_session(%{name: "Odd", adventure_id: "tin_valley"})
    session = GameSessions.get_session!(session.id)

    sheet =
      session.world_state["character"]
      |> Map.merge(%{
        "class" => "bard",
        "creation" => nil,
        "reflecting" => ["climbing"],
        "improved_since_rest" => ["insight"],
        "skills" => %{"insight" => 10.0, "climbing" => 3},
        "learning_points" => %{"climbing" => 2.5},
        "inventory" => [
          %{"id" => "rope", "name" => "rope", "quantity" => 1, "copper_value" => 4},
          %{"id" => "knife", "name" => "knife", "quantity" => 1, "equipped" => true},
          %{"name" => "Odd Stone", "quantity" => "2"}
        ]
      })
      |> Map.delete("learning_failures")

    save_sheet(session, sheet)
    assert row_sheet(session.id) === sheet
    assert GameSessions.get_session!(session.id).world_state["character"] === sheet
  end

  # 10b-1.5: the keys the row kept in runtime["sheet"] are columns now.
  test "the promoted sheet keys are columns and the row keeps no runtime sheet" do
    {:ok, session} = GameSessions.create_session(%{name: "Promoted", adventure_id: "tin_valley"})
    session = GameSessions.get_session!(session.id)
    [row] = Enum.filter(Characters.list_for_session(session.id), &(&1.controller == "player"))

    # A row written before the promotion, with "class" in the bridge.
    row
    |> Ecto.Changeset.change(
      runtime: %{"sheet" => %{"extra" => %{"class" => "old"}, "missing" => []}}
    )
    |> Repo.update!()

    sheet =
      Map.merge(session.world_state["character"], %{
        "class" => "warrior",
        "creation" => %{"seed_key" => "s1", "occupation" => "drover"},
        "reflecting" => ["climbing"],
        "improved_since_rest" => ["insight"],
        "skills" => %{"insight" => 10.5, "climbing" => 3},
        "learning_points" => %{"melee_combat" => 1.0}
      })

    save_sheet(session, sheet)
    [row] = Enum.filter(Characters.list_for_session(session.id), &(&1.controller == "player"))

    assert {row.class, row.creation["occupation"], row.reflecting, row.improved_since_rest} ==
             {"warrior", "drover", ["climbing"], ["insight"]}

    assert row.skills["insight"] === 10.5
    assert row.runtime == %{}
    assert GameCharacter.to_sheet(GameCharacter.from_schema(row)) === sheet

    # A sheet without the optional keys gets none of them back.
    plain = Map.drop(sheet, ~w(class creation reflecting improved_since_rest))
    gc = GameCharacter.from_sheet(plain)
    assert {gc.class, gc.reflecting, gc.extra, gc.missing} == {nil, nil, %{}, []}
    assert GameCharacter.to_sheet(gc) === plain
  end

  test "from_sheet/1 is lossless for sheets, NPC profiles and npc_state entries" do
    {:ok, session} = GameSessions.create_session(%{name: "Sheets", adventure_id: "tin_valley"})
    pc = GameSessions.get_session!(session.id).world_state["character"]

    sheets = [
      pc,
      %{},
      Map.merge(pc, %{"wounds" => "1", "vitality" => nil, "class" => nil, "name" => nil}),
      Map.drop(pc, ["id", "vitality", "stats"]),
      %{
        "id" => "gate_guard",
        "name" => "Gate Guard",
        "stats" => %{"CON" => 10.0},
        "skills" => %{"melee_combat" => 40},
        "ocean" => nil,
        "maslow" => "safety",
        "concerns" => [%{"focus" => "duty"}],
        "current_concern" => %{"focus" => "fame"},
        "wounds" => 2
      },
      %{
        "id" => "foe_x",
        "name" => "x",
        "minor" => true,
        "role" => "minor foe",
        "location_id" => "inn"
      }
    ]

    for sheet <- sheets do
      assert GameCharacter.to_sheet(GameCharacter.from_sheet(sheet)) === sheet
    end

    guard = GameCharacter.from_sheet(Enum.at(sheets, 4))
    assert {guard.slug, guard.maslow_level, guard.wounds} == {"gate_guard", "safety", 2}
    assert guard.runtime == %{"current_concern" => %{"focus" => "fame"}}
    assert GameCharacter.from_sheet(List.last(sheets)).minor
    assert GameCharacter.sheet_value(GameCharacter.from_sheet(%{}), "vitality") == nil
  end

  test "a session stored before 10b-2 plays on its stored sheet, and the turn moves it to the row" do
    {:ok, session} = GameSessions.create_session(%{name: "Legacy", adventure_id: "tin_valley"})
    row = row_sheet(session.id)
    legacy = Map.put(row, "coins", %{"silver" => 7})

    # As a session saved before 10b-2: the sheet is in the column, and the
    # row is behind it.
    put_stored_world!(session.id, "character", legacy)

    assert GameSessions.get_session!(session.id).world_state["character"] === legacy
    assert row_sheet(session.id) === row

    step = {"I study the regulars", :observe, nil, %{"skill" => "insight"}}
    {:ok, _} = TurnProcessor.run(session.id, {"I study the regulars", action(step)})

    refute Map.has_key?(stored_world(session.id), "character")
    assert row_sheet(session.id)["coins"] == %{"silver" => 7}
  end

  test "a session with no row is loaded as it is stored" do
    {:ok, session} = GameSessions.create_session(%{name: "None", adventure_id: "tin_valley"})
    Repo.delete_all(Ecto.assoc(session, :characters))
    stored = Repo.get!(GameSession, session.id)

    assert Characters.put_sheet(stored) == stored
    refute Map.has_key?(stored.world_state, "character")
  end

  test "an admin edit of the sheet is written to the row in the same transaction" do
    {:ok, session} = GameSessions.create_session(%{name: "Admin", adventure_id: "tin_valley"})
    world = GameSessions.get_session!(session.id).world_state
    edited = put_in(world, ["character", "coins"], %{"silver" => 9})

    assert {:ok, updated} =
             TalesForge.Admin.update_session_world_state(session, Jason.encode!(edited))

    assert updated.world_state["character"]["coins"] == %{"silver" => 9}
    assert row_sheet(session.id)["coins"] == %{"silver" => 9}
    refute Map.has_key?(stored_world(session.id), "character")

    assert GameSessions.get_session!(session.id).world_state["character"]["coins"] == %{
             "silver" => 9
           }
  end
end
