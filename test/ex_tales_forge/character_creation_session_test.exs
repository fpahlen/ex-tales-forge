defmodule TalesForge.CharacterCreationSessionTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.GameCharacter.Store
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, GameSession}

  defp created(adventure) do
    {:ok, d} = CC.new(adventure, seed_key: "s1") |> CC.choose_class("thief")
    {:ok, d} = CC.choose_race(d, "halfling")
    {:ok, d} = CC.set_name(d, "Pip Thistledown")
    {:ok, character} = CC.finalize(d)
    character
  end

  defp pc_row(session),
    do: Repo.get_by!(Character, game_session_id: session.id, slug: "pc_pip_thistledown")

  for adventure <- ["tin_valley", "crossroads_ledger"] do
    test "a created character replaces Elara in #{adventure}" do
      character = created(unquote(adventure))

      assert {:ok, session} =
               GameSessions.create_session(%{
                 adventure_id: unquote(adventure),
                 character: character
               })

      pc = session.world_state["character"]
      assert pc["id"] == "pc_pip_thistledown"
      assert pc["name"] == "Pip Thistledown"
      assert pc["class"] == "thief"
      assert pc["stats"] == character["stats"]
      assert pc["location_id"] == session.world_state["location_id"]
      refute Enum.any?(~w(ocean maslow concerns creation), &Map.has_key?(pc, &1))

      row = pc_row(session)
      assert row.controller == "player"
      assert row.origin == %{"source" => "created", "adventure_id" => unquote(adventure)}
      assert row.race == "halfling"
      assert row.skills == character["skills"]
      assert row.skills["stealth"] == 35

      assert Map.from_struct(row.ocean) |> Map.take([:openness]) == %{
               openness: character["ocean"]["openness"]
             }

      # a former thief: the levers follow the occupation
      assert Enum.map(row.concerns, & &1.focus) == ["freedom"]
      assert row.maslow_level == "safety"
      refute Repo.get_by(Character, game_session_id: session.id, slug: "elara_voss")
    end
  end

  test "the per-turn characters write keeps the created character's levers and origin" do
    character = created("tin_valley")

    {:ok, session} =
      GameSessions.create_session(%{adventure_id: "tin_valley", character: character})

    before = pc_row(session)

    session = GameSessions.get_session!(session.id)
    ws = put_in(session.world_state, ["character", "skills", "stealth"], 4)

    session |> GameSession.changeset(%{world_state: ws}) |> save_session!()

    assert Store.backfill().failed == []

    after_ = pc_row(session)
    assert after_.skills["stealth"] == 4
    assert after_.ocean == before.ocean
    assert after_.concerns == before.concerns
    assert after_.origin == before.origin
  end

  test "a bot can play a created character" do
    {:ok, session} =
      GameSessions.create_session(%{
        adventure_id: "tin_valley",
        character: created("tin_valley"),
        controller: "bot",
        controller_ref: "paul"
      })

    assert %{controller: "bot", controller_ref: "paul"} = pc_row(session)
  end

  test "an invalid character creates nothing" do
    count = Repo.aggregate(GameSession, :count)
    bad = Map.delete(created("tin_valley"), "stats")

    assert {:error, {:invalid_character, msg}} =
             GameSessions.create_session(%{adventure_id: "tin_valley", character: bad})

    assert msg =~ "needs \"stats\""

    assert {:error, {:invalid_character, _}} =
             GameSessions.create_session(%{adventure_id: "tin_valley", character: "Pip"})

    assert {:error, {:invalid_character, _}} =
             GameSessions.create_session(%{
               adventure_id: "tin_valley",
               character: Map.put(created("tin_valley"), "maslow", "greed")
             })

    assert Repo.aggregate(GameSession, :count) == count
  end
end
