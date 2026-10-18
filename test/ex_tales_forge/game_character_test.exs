defmodule TalesForge.GameCharacterTest do
  @moduledoc """
  Refactor step 10a: the turn reads its acting character from the
  `characters` row with `CHARACTERS=on`. The proof that nothing changes:

    * the mirror is lossless: `to_sheet/1` of the mirrored row is
      `world_state["character"]` after every turn (`===`, so `5` is not `5.0`);
    * the same script of turns, played with the flag off and on, gives
      byte-identical GM prompts (system and user) and world states.
  """
  use TalesForge.DataCase, async: false

  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Characters
  alias TalesForge.Characters.Present
  alias TalesForge.Game.{Turn, TurnProcessor}
  alias TalesForge.GameCharacter
  alias TalesForge.GameSessions
  alias TalesForge.Jido
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
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
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

  defp row_sheet(session_id) do
    %Present{actor: actor} = Characters.load_present(Repo.get!(GameSession, session_id))
    GameCharacter.to_sheet(actor)
  end

  # Plays the script with CHARACTERS off or on. Each turn gives the GM
  # prompt, the world after it, and the row's sheet after it, with the
  # session id taken out.
  defp play(characters?) do
    :rand.seed(:exsss, {10, 20, 30})
    {:ok, session} = GameSessions.create_session(%{name: "Golden", adventure_id: "tin_valley"})
    flags = Map.put(Turn.read_flags(), :characters, characters?)

    Enum.map(@script, fn {text, _, _, _} = step ->
      {:ok, _} = TurnProcessor.run(session.id, {text, action(step)}, flags: flags)
      assert_received {:gm_prompt, system, user}
      world = Repo.get!(GameSession, session.id).world_state

      {system, user, world, row_sheet(session.id)}
      |> :erlang.term_to_binary()
      |> :binary.replace(session.id, "SESSION", [:global])
      |> :erlang.binary_to_term()
    end)
  end

  test "the mirrored row gives back the sheet after every turn" do
    for {_system, _user, world, sheet} <- play(false) do
      assert sheet === world["character"]
    end
  end

  test "the turns play the same with CHARACTERS off and on" do
    off = play(false)
    {on, log} = ExUnit.CaptureLog.with_log(fn -> play(true) end)

    assert length(on) == length(@script)
    # Every flag-on turn read a row, and no row differed from the sheet.
    refute log =~ "characters read"

    # The script changed the sheet: coins (the ale), the equipped knife,
    # the fight and the rest are all in the last world state.
    {_, _, first, _} = hd(off)
    {_, _, last, _} = List.last(off)
    assert first["character"]["coins"] != last["character"]["coins"]
    assert Enum.any?(last["character"]["inventory"], &(&1["equipped"] == true))
    assert first["character"] != last["character"]

    for {{a, b}, n} <- off |> Enum.zip(on) |> Enum.with_index(1) do
      assert elem(a, 0) === elem(b, 0), "turn #{n}: GM system prompt"
      assert elem(a, 1) === elem(b, 1), "turn #{n}: GM user prompt"
      assert elem(a, 2) === elem(b, 2), "turn #{n}: world state"
    end
  end

  test "a sheet with keys the columns lack round-trips through the row" do
    {:ok, session} = GameSessions.create_session(%{name: "Odd", adventure_id: "tin_valley"})
    session = Repo.get!(GameSession, session.id)

    sheet =
      session.world_state["character"]
      |> Map.merge(%{
        "class" => "bard",
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

    session =
      session
      |> GameSession.changeset(%{world_state: Map.put(session.world_state, "character", sheet)})
      |> Repo.update!()

    assert :ok = Characters.mirror(session)
    assert row_sheet(session.id) === Repo.get!(GameSession, session.id).world_state["character"]
  end

  test "load_present gives the human-controlled character and the others at its place" do
    {:ok, session} = GameSessions.create_session(%{name: "Here", adventure_id: "tin_valley"})

    %Present{actor: actor, others: others} = Characters.load_present(session)
    assert actor.slug == "elara_voss"
    assert Enum.all?(others, &(&1.location_id == actor.location_id))
    assert "innkeep" in Enum.map(others, & &1.slug)
  end

  test "with CHARACTERS on and no row, the turn plays on world_state" do
    {:ok, session} = GameSessions.create_session(%{name: "None", adventure_id: "tin_valley"})
    session = Repo.get!(GameSession, session.id)
    Repo.delete_all(Ecto.assoc(session, :characters))

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert Characters.turn_session(session, true) == session
      end)

    assert log =~ "characters read: no row"
    assert Characters.turn_session(session, false) == session
  end

  test "an admin edit of the sheet reaches the row, so CHARACTERS on reads it" do
    {:ok, session} = GameSessions.create_session(%{name: "Admin", adventure_id: "tin_valley"})
    world = Repo.get!(GameSession, session.id).world_state
    edited = put_in(world, ["character", "coins"], %{"silver" => 9})

    assert {:ok, updated} =
             TalesForge.Admin.update_session_world_state(session, Jason.encode!(edited))

    assert row_sheet(session.id)["coins"] == %{"silver" => 9}

    assert Characters.turn_session(updated, true).world_state["character"]["coins"] == %{
             "silver" => 9
           }
  end
end
