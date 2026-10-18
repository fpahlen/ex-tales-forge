defmodule TalesForge.CharactersSyncTest do
  use TalesForge.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias TalesForge.Characters
  alias TalesForge.Game.Turn.Board
  alias TalesForge.Game.{ActionHandler, Intent, TurnProcessor}
  alias TalesForge.Game.Schemas.MechanicalResolution
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, GameSession, NpcInstance, PlaytestRun}

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Sync", adventure_id: "tin_valley"})
    %{session: session}
  end

  defp reload(id), do: GameSessions.get_session!(id)

  defp wait_turn(session, rolls) do
    {bundle, _} =
      Intent.resolve_bundle("I sleep", %{"exits" => [], "present_npcs" => []})

    action = Intent.validate_player_action(bundle, %{})

    {:ok, _} =
      TurnProcessor.simulate!(
        %Board{
          session: session,
          player_action: action,
          handler: ActionHandler.resolve(action),
          mechanical: %MechanicalResolution{outcome: "none"},
          opts: [improvement_rolls: rolls]
        },
        "I sleep"
      )

    reload(session.id)
  end

  defp put_character(session, fun) do
    world = Map.update!(session.world_state, "character", fun)
    session |> GameSession.changeset(%{world_state: world}) |> save_session!()
  end

  describe "double-write after a turn" do
    test "the player character and NPC state reach the characters rows", %{session: session} do
      session =
        put_character(session, fn c ->
          c
          |> Map.update!("skills", &Map.put(&1, "climbing", 15))
          |> Map.put("learning_points", %{"climbing" => 1.0})
          |> Map.put("learning_failures", %{"climbing" => 3})
        end)

      NPC.record_memory(%NPC.Note{
        session_id: session.id,
        npc_id: "innkeep",
        summary: "The stranger paid in silver",
        tick: 30
      })

      NPC.bump_relationship(session.id, "innkeep", 0.4)

      session = wait_turn(session, %{"climbing" => {51, 5}})
      assert get_in(session.world_state, ["character", "skills", "climbing"]) == 20

      elara = Characters.get_by_slug(session.id, "elara_voss")
      assert elara.skills["climbing"] == 20
      assert elara.learning_points == %{"climbing" => 0.0}
      # Levers set at seeding are not overwritten by the mirror.
      assert elara.maslow_level == "esteem"
      assert elara.controller == "player"

      innkeep = Characters.get_by_slug(session.id, "innkeep")
      assert_in_delta innkeep.relationships["elara_voss"], 0.4, 0.001

      assert [%{text: "The stranger paid in silver", tick: 30, kind: "memory"}] =
               Characters.list_memories(innkeep)

      # A second turn adds nothing twice.
      wait_turn(reload(session.id), %{})
      assert length(Characters.list_memories(innkeep)) == 1
    end
  end

  describe "write_multi/2" do
    defp coins_session(session, coins) do
      %{session | world_state: put_in(session.world_state, ["character", "coins"], coins)}
    end

    test "the rows are written in the turn's transaction", %{session: session} do
      saved = coins_session(session, %{"silver" => 7})

      assert {:error, :boom, :failed, _} =
               Ecto.Multi.new()
               |> Ecto.Multi.put(:session, saved)
               |> Characters.write_multi(Characters.cast(session.id))
               |> Ecto.Multi.run(:boom, fn _repo, _ -> {:error, :failed} end)
               |> Repo.transaction()

      # The turn failed, so the row kept its coins.
      refute Characters.get_by_slug(session.id, "elara_voss").coins == %{"silver" => 7}

      assert {:ok, %{characters: :ok}} =
               Ecto.Multi.new()
               |> Ecto.Multi.put(:session, saved)
               |> Characters.write_multi(Characters.cast(session.id))
               |> Repo.transaction()

      assert Characters.get_by_slug(session.id, "elara_voss").coins == %{"silver" => 7}
    end

    test "a sheet that doesn't validate skips the write and never fails the turn",
         %{session: session} do
      broken = %{
        session
        | world_state:
            Map.put(session.world_state, "character", %{"id" => "elara_voss", "name" => nil})
      }

      log =
        capture_log(fn ->
          assert {:ok, %{characters: :skipped}} =
                   Ecto.Multi.new()
                   |> Ecto.Multi.put(:session, broken)
                   |> Characters.write_multi(Characters.cast(session.id))
                   |> Repo.transaction()
        end)

      assert log =~ "characters write skipped session=#{session.id} slugs=elara_voss"
      assert Characters.get_by_slug(session.id, "elara_voss").name == "Elara Voss"
    end
  end

  describe "NPC rows (10f PR 5)" do
    test "an NPC's state is its row: a memory gets its memory row at once", %{session: session} do
      :ok =
        NPC.record_memory(%NPC.Note{
          session_id: session.id,
          npc_id: "innkeep",
          summary: "  The stranger paid in silver ",
          tick: 30
        })

      innkeep = Characters.get_by_slug(session.id, "innkeep")

      assert [%{"summary" => "The stranger paid in silver", "tick" => 30}] =
               innkeep.runtime["memories"]

      assert [%{text: "The stranger paid in silver", tick: 30, kind: "memory", about: []}] =
               Characters.list_memories(innkeep)

      {:ok, score} = NPC.bump_relationship(session.id, "innkeep", 0.25)
      assert score == 0.25

      assert Characters.get_by_slug(session.id, "innkeep").relationships == %{
               "elara_voss" => 0.25
             }

      refute Repo.exists?(from n in NpcInstance, where: n.game_session_id == ^session.id)
    end

    test "a row from before PR 5 reads its memories from its memory rows", %{session: session} do
      innkeep = Characters.get_by_slug(session.id, "innkeep")

      innkeep
      |> Character.changeset(%{runtime: Map.delete(innkeep.runtime, "memories")})
      |> Repo.update!()

      for {text, tick} <- [{"Second", 12}, {"First", 11}] do
        {:ok, _} = Characters.add_memory(innkeep, %{kind: "memory", text: text, tick: tick})
      end

      {:ok, _} = Characters.add_memory(innkeep, %{kind: "memory", text: "Long", about: ["x"]})

      assert [%{"summary" => "First", "tick" => 11}, %{"summary" => "Second", "tick" => 12}] =
               NPC.get_person(session.id, "innkeep").runtime_state["memories"]

      :ok =
        NPC.record_memory(%NPC.Note{
          session_id: session.id,
          npc_id: "innkeep",
          summary: "Third",
          tick: 13
        })

      assert ~w(First Second Third) ==
               Enum.map(
                 Characters.get_by_slug(session.id, "innkeep").runtime["memories"],
                 & &1["summary"]
               )
    end

    test "NPC updates commit or roll back with the turn", %{session: session} do
      assert {:error, :boom, :failed, _} =
               Ecto.Multi.new()
               |> Ecto.Multi.run(:npc, fn _repo, _ ->
                 NPC.bump_relationship(session.id, "innkeep", 1.0)
               end)
               |> Ecto.Multi.run(:boom, fn _repo, _ -> {:error, :failed} end)
               |> Repo.transaction()

      assert Characters.get_by_slug(session.id, "innkeep").relationships == %{"elara_voss" => 0.0}
    end

    test "the characters step keeps the NPC updates before it and adds the reaction",
         %{session: session} do
      reaction = %{"emotion" => "wary", "intensity" => 0.4}
      cast = Characters.cast(session.id)

      cast =
        put_in(cast["innkeep"].runtime, Map.put(cast["innkeep"].runtime, "reaction", reaction))

      assert {:ok, _} =
               Ecto.Multi.new()
               |> Ecto.Multi.put(:session, session)
               |> Ecto.Multi.run(:gm, fn _repo, _ ->
                 inst = NPC.get_person(session.id, "innkeep")
                 {:ok, NPC.put_state!(inst, Map.put(inst.runtime_state, "mood", "tired"))}
               end)
               |> Characters.write_multi(cast)
               |> Repo.transaction()

      innkeep = Characters.get_by_slug(session.id, "innkeep")
      assert {innkeep.mood, innkeep.runtime["reaction"]} == {"tired", reaction}
      assert Characters.cast(session.id)["innkeep"].mood == "tired"
    end

    test "the combat profile reads the skills column, not the definition", %{session: session} do
      innkeep = Characters.get_by_slug(session.id, "innkeep")

      innkeep
      |> Character.changeset(%{
        skills: %{"brawling" => 77},
        definition: Map.put(innkeep.definition, "skills", %{"brawling" => 3})
      })
      |> Repo.update!()

      assert NPC.combat_profile(session.id, "innkeep")["skills"] == %{"brawling" => 77}
    end
  end

  describe "backfill/0" do
    test "writes the player character's row from a stored sheet, idempotently",
         %{session: session} do
      # A session as it looked before 10b-2: no player character row, the sheet in world_state.
      Repo.delete_all(
        from c in Character, where: c.game_session_id == ^session.id and c.controller == "player"
      )

      from(c in Character, where: c.game_session_id == ^session.id and c.controller == "gm")
      |> Repo.update_all(set: [relationships: %{}])

      put_stored_world!(
        session.id,
        "character",
        Map.put(session.world_state["character"], "inventory", [
          %{"name" => "Rope Coil", "quantity" => "2"},
          %{"id" => "nameless"}
        ])
      )

      Repo.insert!(
        PlaytestRun.changeset(%PlaytestRun{}, %{
          game_session_id: session.id,
          persona: "ronny",
          module: "tin_valley",
          turn_limit: 5,
          status: "finished",
          started_at: DateTime.utc_now(:second)
        })
      )

      first = Characters.backfill()
      assert first.failed == []
      assert first.inserted == 1

      elara = Characters.get_by_slug(session.id, "elara_voss")
      assert {elara.controller, elara.controller_ref} == {"bot", "ronny"}
      assert [%{id: "rope_coil", name: "Rope Coil", quantity: 2}] = elara.inventory

      assert Characters.get_by_slug(session.id, "prospector").relationships == %{
               "elara_voss" => 0.0
             }

      second = Characters.backfill()
      assert second.failed == []
      assert second.inserted == 0
      assert second.characters == first.characters
      assert second.memories == first.memories
    end

    test "seeding and backfill agree on a fresh session", %{session: session} do
      before =
        Characters.list_for_session(session.id)
        |> Enum.map(&Map.take(&1, [:slug, :controller, :skills, :maslow_level]))

      assert Characters.backfill().failed == []

      after_ =
        Characters.list_for_session(session.id)
        |> Enum.map(&Map.take(&1, [:slug, :controller, :skills, :maslow_level]))

      assert before == after_
    end

    test "mix characters.backfill prints the counts", %{session: session} do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      Mix.Tasks.Characters.Backfill.run([])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "inserted: 0"
      assert output =~ "failed: []"
      assert Repo.aggregate(where(Character, game_session_id: ^session.id), :count) == 4
    end
  end
end
