defmodule TalesForge.NPCInitiativeTest do
  # Refactor 10e: what a turn means for the present NPCs comes in as
  # Intentions (TalesForge.NPCSignals.intentions/1) that the turn applies
  # (TalesForge.Game.Turn.Intentions.apply_all/2). Before 10e these were
  # Jido signals to the NPC agents.
  use TalesForge.DataCase, async: false
  alias TalesForge.GameCharacter.Rows

  alias TalesForge.Game.Turn.Intentions
  alias TalesForge.GameCharacter.Agency
  alias TalesForge.GameSessions
  alias TalesForge.Intention
  alias TalesForge.NPCInitiative
  alias TalesForge.NPCSignals
  alias TalesForge.PubSub.GameSession, as: SessionPubSub

  # A finished turn of `session` in which `delta` ticks passed.
  defp turn(session, handler, raw_action, delta \\ 0) do
    world = session.world_state
    tick = Map.get(world, "world_tick")

    %NPCSignals.Turn{
      session_id: session.id,
      world_state: world,
      handler: handler,
      raw_action: raw_action,
      world_before: Map.put(world, "world_tick", tick - delta)
    }
  end

  defp play(session, %NPCSignals.Turn{} = turn),
    do: Intentions.apply_all(session.id, NPCSignals.intentions(turn))

  defp memories(session, npc_id),
    do: Rows.get(session.id, npc_id).runtime_state |> Map.get("memories", [])

  defp speak(target), do: %{handler: "speak", target: target, skill: "persuasion", notes: "test"}
  defp freeform, do: %{handler: "freeform", target: nil, skill: nil, notes: "test"}

  test "a turn gives each present NPC a wait and a speak-up, then what it heard, all by the system" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Intentions"})
    tick = Map.get(session.world_state, "world_tick")
    present = session.world_state["present_npcs"]
    assert "marta_kellen" in present

    intentions = NPCSignals.intentions(turn(session, speak("marta_kellen"), "hello marta", 2))

    assert Enum.all?(intentions, &match?(%Intention{by: :system, tick: ^tick}, &1))

    time = Enum.flat_map(present, &[{&1, {:wait, 2}}, {&1, :speak_up}])

    others =
      for npc <- present,
          npc != "marta_kellen",
          do: {npc, {:remember, "Overheard player: hello marta"}}

    assert Enum.map(intentions, &{&1.character_id, &1.action}) ==
             time ++
               [
                 {"marta_kellen", {:remember, "Player spoke to me: hello marta"}},
                 {"marta_kellen", {:warm, 0.05}}
               ] ++ others
  end

  test "speaking to an NPC is remembered and warms it, with no overheard copy" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Speak Only"})

    assert [] =
             play(
               session,
               turn(session, speak("marta_kellen"), "Marta, tell me about the ledger")
             )

    assert [memory] = memories(session, "marta_kellen")
    assert memory["summary"] == "Player spoke to me: Marta, tell me about the ledger"
    assert memory["tick"] == Map.get(session.world_state, "world_tick")

    assert Rows.get(session.id, "marta_kellen").runtime_state["relationship_score"] ==
             0.05
  end

  test "freeform words are overheard by the present NPCs; a quiet turn is not" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Overhear"})

    play(session, turn(session, %{freeform() | handler: "wait"}, "I wait by the fire"))
    assert memories(session, "marta_kellen") == []

    play(session, turn(session, freeform(), "I study the chalk marks on the slate"))

    assert [%{"summary" => "Overheard player: I study the chalk marks on the slate"}] =
             memories(session, "marta_kellen")
  end

  test "an NPC that is not present hears nothing" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Absent"})

    intentions = NPCSignals.intentions(turn(session, speak("ghost"), "hello?"))
    refute Enum.any?(intentions, &(&1.character_id == "ghost"))
  end

  test "a concern escalates after four ticks of waiting, and 288 ticks at once" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Time"})
    for _ <- 1..4, do: play(session, turn(session, freeform(), "", 1))

    concern = Rows.get(session.id, "marta_kellen").runtime_state["current_concern"]
    assert concern["priority"] >= 9

    {:ok, other} = GameSessions.create_session(%{name: "NPC Wait Concern"})
    play(other, turn(other, freeform(), "", 288))

    assert get_in(Rows.get(other.id, "marta_kellen").runtime_state, [
             "current_concern",
             "priority"
           ]) == 10
  end

  test "three-day wait escalates pack NPC concern" do
    {:ok, session} =
      GameSessions.create_session(%{name: "Tin Valley Wait", adventure_id: "tin_valley"})

    before = Rows.get(session.id, "innkeep")
    assert get_in(before.runtime_state, ["current_concern", "focus"]) =~ "hills are restless"

    play(session, turn(session, freeform(), "", 288))

    assert get_in(Rows.get(session.id, "innkeep").runtime_state, [
             "current_concern",
             "priority"
           ]) >
             get_in(before.runtime_state, ["current_concern", "priority"])
  end

  test "marta speaks up once after four ticks of worry, and the payload broadcasts" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Initiative"})
    SessionPubSub.subscribe(session.id)

    payloads = Enum.flat_map(1..5, fn _ -> play(session, turn(session, freeform(), "", 1)) end)

    assert [payload] = Enum.filter(payloads, &(&1.npc_id == "marta_kellen"))
    assert payload.npc_name == "Marta Kellen"
    assert payload.text =~ "ledger"
    assert Rows.get(session.id, "marta_kellen").runtime_state["initiative_emitted"]

    :ok = NPCInitiative.broadcast(session.id, payload)
    assert_receive {:npc_initiative, ^payload}
  end

  # Gentry QA 2026-10-21 (playtest 9b08e77, session b01271a7): Brenna, Cobb
  # and Rusk "speak up, as if a worry has been pressing on them for some
  # time." with nothing said. Only Henrik and Marta have lines written; the
  # fallback was a stage direction with no speech.
  test "a pack NPC with no line written speaks up with nothing, not an empty line" do
    {:ok, session} =
      GameSessions.create_session(%{name: "Tin Valley Speak Up", adventure_id: "tin_valley"})

    payloads =
      Enum.flat_map([288, 1, 1, 1, 1, 1], &play(session, turn(session, freeform(), "", &1)))

    assert Rows.get(session.id, "innkeep").runtime_state["initiative_emitted"]
    assert Agency.initiative_text(Rows.get(session.id, "innkeep")) == nil
    refute Enum.any?(payloads, &(&1.npc_id == "innkeep"))
    refute Enum.any?(payloads, &(&1.text =~ "as if a worry has been pressing"))
  end

  test "a turn applies its NPC Intentions in its own transaction" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Turn"})

    action = %{
      "overall_intent" => "greet Marta",
      "action" => %{"action_type" => "speak", "target" => "marta_kellen", "parameters" => %{}},
      "deferred_actions" => [],
      "confidence" => 0.9
    }

    assert {:ok, _} = TalesForge.Game.TurnProcessor.run(session.id, {"Hello, Marta.", action})

    assert [%{"summary" => "Player spoke to me: Hello, Marta."}] =
             memories(session, "marta_kellen")
  end

  # Before this fix the turn compared the saved session with itself, so no
  # time ever passed for the NPCs: concern_wait_ticks stayed 0 and no NPC
  # spoke up on its own (seen in the 10e golden of Gentry's 38-turn script).
  test "time passing in a real turn builds Marta's concern and she speaks up" do
    {:ok, session} = GameSessions.create_session(%{name: "NPC Turn Time"})
    SessionPubSub.subscribe(session.id)

    priority = fn ->
      get_in(Rows.get(session.id, "marta_kellen").runtime_state, [
        "current_concern",
        "priority"
      ])
    end

    before = priority.()

    wait = %{
      "overall_intent" => "I wait by the fire for an hour.",
      "action" => %{"action_type" => "wait", "target" => nil, "parameters" => %{"ticks" => 4}},
      "deferred_actions" => [],
      "confidence" => 0.9
    }

    # Through the turn job, as the play page submits it: the broadcast comes
    # from wherever the turn commits (World.Instance from refactor 10f PR 2).
    assert :ok =
             TalesForge.Workers.ProcessTurn.perform(%Oban.Job{
               args: %{
                 "session_id" => session.id,
                 "raw_action" => "I wait by the fire for an hour.",
                 "player_action" => wait
               }
             })

    assert GameSessions.get_session!(session.id).world_state["world_tick"] ==
             session.world_state["world_tick"] + 4

    # Four ticks of worry: the concern escalates and Marta speaks up.
    assert priority.() == before + 1
    assert_receive {:npc_initiative, %{npc_id: "marta_kellen", text: text}}
    assert text =~ "ledger"
  end

  test "concern priority surfaces in the session's cast" do
    assert {:ok, session} = GameSessions.create_session(%{name: "NPC Concern UI"})

    inst = Rows.get(session.id, "marta_kellen")

    Rows.update!(
      inst,
      inst.runtime_state
      |> Map.put("concern_wait_ticks", 4)
      |> put_in(["current_concern", "priority"], 9)
    )

    marta = TalesForge.Characters.cast(session.id)["marta_kellen"]

    assert TalesForge.Game.Cast.details(marta)["concern_priority"] == 9
  end
end
