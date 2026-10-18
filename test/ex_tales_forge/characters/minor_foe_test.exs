defmodule TalesForge.Characters.MinorFoeTest do
  @moduledoc """
  Minor foes live on `characters` rows (10f step 4): a row with controller
  `gm` and `lifetime: :scene`, removed when its scene ends. Rows that live
  on (`:persistent`, the default) stay.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Characters
  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.{Combat, Context}
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameSessions
  alias TalesForge.Schemas.{Character, GameSession}

  setup do
    previous = System.get_env("COMBAT_OPPOSED")
    System.put_env("COMBAT_OPPOSED", "on")

    on_exit(fn ->
      if previous,
        do: System.put_env("COMBAT_OPPOSED", previous),
        else: System.delete_env("COMBAT_OPPOSED")
    end)

    {:ok, session} = GameSessions.create_session(%{name: "Foes", adventure_id: "tin_valley"})
    %{session: session}
  end

  defp action(text, type, target, params) do
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

  defp attack(session) do
    text = "I attack the miner"
    a = action(text, :combat, nil, %{"skill" => "melee_combat"})
    {:ok, _} = TurnProcessor.run(session.id, {text, a}, combat_rolls: %{attack: 1})
  end

  defp rows(session_id) do
    Repo.all(from c in Character, where: c.game_session_id == ^session_id, order_by: c.slug)
  end

  defp world(session_id), do: Repo.get!(GameSession, session_id).world_state

  test "an attack on a stranger makes a minor foe row for the scene", %{session: session} do
    attack(session)
    here = world(session.id)["location_id"]

    assert %Character{controller: "gm", lifetime: :scene, location_id: ^here} =
             foe = Characters.get_by_slug(session.id, "foe_miner")

    assert foe.definition["minor"] == true
    assert foe.vitality == "down"
    refute Map.has_key?(world(session.id), "npc_state")

    # The next turn finds the same foe in the session's cast.
    assert %TalesForge.GameCharacter{minor: true, lifetime: :scene, vitality: "down"} =
             Characters.cast(session.id)["foe_miner"]

    # Every other row lives on.
    assert session.id
           |> rows()
           |> Enum.reject(&(&1.slug == "foe_miner"))
           |> Enum.all?(&(&1.lifetime == :persistent))
  end

  test "leaving the place ends the scene and removes its minor foes", %{session: session} do
    attack(session)
    here = world(session.id)["location_id"]
    before = session.id |> rows() |> Enum.map(& &1.slug)
    assert "foe_miner" in before

    [exit | _] = Context.build_intent_context(GameSessions.get_session!(session.id))["exits"]
    text = "I walk to #{exit}"
    {:ok, _} = TurnProcessor.run(session.id, {text, action(text, :move, exit, %{})})

    refute world(session.id)["location_id"] == here
    assert session.id |> rows() |> Enum.map(& &1.slug) == before -- ["foe_miner"]
    refute Map.has_key?(Characters.cast(session.id), "foe_miner")
  end

  test "an old world with npc_state and npc_moods: read as if absent, gone after the next turn",
       %{session: session} do
    old = %{"npc_state" => %{"foe_x" => %{"minor" => true}}, "npc_moods" => %{"innkeep" => %{}}}
    {:ok, id} = Ecto.UUID.dump(session.id)

    Repo.query!(
      "UPDATE game_sessions SET world_state = world_state || $1::jsonb WHERE id = $2",
      [old, id]
    )

    raw = fn ->
      Repo.query!("SELECT world_state FROM game_sessions WHERE id = $1", [id]).rows
      |> then(fn [[world]] -> world end)
    end

    assert Map.take(raw.(), ["npc_state", "npc_moods"]) == old
    refute Map.has_key?(world(session.id), "npc_state")
    refute Map.has_key?(world(session.id), "npc_moods")
    refute Map.has_key?(Characters.cast(session.id), "foe_x")

    attack(session)
    assert Map.take(raw.(), ["npc_state", "npc_moods"]) == %{}
  end

  describe "end_scene_multi/2" do
    setup %{session: session} do
      foe =
        {"foe_guard", "a guard"}
        |> Combat.minor_foe(Defaults.rules("tin_valley"), 7)
        |> Map.put(:location_id, "valley_inn")

      far = %{foe | slug: "foe_far", location_id: "inn_yard"}
      cast = session.id |> Characters.cast() |> Map.merge(%{"foe_guard" => foe, "foe_far" => far})

      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.put(:session, session)
        |> Characters.write_multi(cast)
        |> Repo.transaction()

      :ok
    end

    defp end_scene(session, events) do
      {:ok, _} =
        Ecto.Multi.new()
        |> Ecto.Multi.put(:session, session)
        |> Characters.end_scene_multi(Characters.Memory.scene_end(events))
        |> Repo.transaction()

      session.id |> rows() |> Enum.map(& &1.slug)
    end

    test "a long rest ends the scene at its place: only the scene rows there go",
         %{session: session} do
      persistent = session.id |> rows() |> Enum.filter(&(&1.lifetime == :persistent))

      rest = %{
        "kind" => "time.passed",
        "location_id" => "valley_inn",
        "payload" => %{"delta_ticks" => 32}
      }

      slugs = end_scene(session, [rest])

      refute "foe_guard" in slugs
      assert "foe_far" in slugs
      assert Enum.all?(persistent, &(&1.slug in slugs))
    end

    test "no scene end removes nothing", %{session: session} do
      before = session.id |> rows() |> Enum.map(& &1.slug)
      assert end_scene(session, [%{"kind" => "player.spoke", "payload" => %{}}]) == before
      assert end_scene(session, []) == before
    end
  end
end
