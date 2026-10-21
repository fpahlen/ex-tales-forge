defmodule TalesForge.Game.TurnTest do
  @moduledoc """
  The turn pipe (`TalesForge.Game.Turn`). The adapters are plain functions,
  so the tests need no mocks.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Schemas.{
    GMStructuredResponse,
    MechanicalResolution,
    PlayerAction,
    SingleAction
  }

  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.Adapters
  alias TalesForge.GameSessions

  @off %{
    turn_outcome_record: false,
    npc_dialogue_memory: false,
    npc_reactions: false,
    world_agents: false,
    turn_premise_first: false,
    turn_state_from_mechanics: false,
    history_strip_injection: false,
    skill_detail_level: false
  }

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Pipe", adventure_id: "tin_valley"})
    %{session: session}
  end

  defp turn(session, text, opts) do
    action = %PlayerAction{
      overall_intent: text,
      action: %SingleAction{action_type: :observe, target: nil}
    }

    flags = Map.merge(@off, Keyword.get(opts, :flags, %{}))
    Turn.new({session, 1}, {text, action}, Keyword.merge(opts, flags: flags, role: :playtest))
  end

  test "new/5 reads the flags and the role one time", %{session: session} do
    t = turn(session, "look around", flags: %{history_strip_injection: true})
    assert t.flags.history_strip_injection
    assert t.role == :playtest
    refute t.injected
    assert t.history_action == "look around"
  end

  test "a premise finding blocks the action; the rejection is data", %{session: session} do
    finding = %{kind: :item, claim: "my sword", correction: "There is no sword."}

    t =
      session
      |> turn("I draw my sword", [])
      |> Map.update!(:premise, &%{&1 | first: [finding]})
      |> Turn.Mechanics.apply()

    assert t.outcome.handler.handler == "narrate"
    assert t.outcome.handler.state_hints["rejected"]
    assert t.outcome.handler.state_hints["reason"] == "There is no sword."
  end

  # Gentry QA 2026-10-21 (playtest 9b08e77, session b01271a7, turn 10): with no
  # key on the sheet, "I take out the silver key Brenna gave me earlier ..."
  # was narrated as drawing the key. The premise check found the claim, but
  # without TURN_PREMISE_FIRST the action is not blocked: the board plays it as
  # an everyday action (outcome none, "simply happens"), so the GM got both.
  test "TURN_PREMISE_FIRST: an invented key blocks the action and the GM is told",
       %{session: session} do
    me = self()

    adapters = %Adapters{
      gm: fn %TalesForge.LLM.GmTurn{messages: messages} ->
        send(me, {:gm, Enum.map_join(messages, "\n", & &1.content)})
        {:ok, %GMStructuredResponse{narrative: "Elara pats her cloak and finds no key."}}
      end,
      stream: fn _id, _chunk -> :ok end
    }

    text = "I take out the silver key Brenna gave me earlier and unlock the guild vault."

    t =
      session
      |> turn(text, flags: %{turn_premise_first: true}, adapters: adapters)
      |> Turn.Premise.check()
      |> Turn.Mechanics.apply()
      |> Turn.Npcs.react()
      |> Turn.Prompt.build()
      |> Turn.Gm.narrate()

    assert [%{kind: :item, claim: "silver key"}] = t.premise.first
    assert t.outcome.handler.handler == "narrate"
    assert t.outcome.handler.state_hints["premise_rejected"]

    assert t.outcome.handler.state_hints["reason"] =~
             "Player claims to own silver key; they don't"

    assert_received {:gm, prompt}
    assert prompt =~ "Premise check: the action is blocked."
    assert prompt =~ "Player claims to own silver key; they don't"
  end

  test "the npc adapter gives the reactions; the gm adapter streams after them",
       %{session: session} do
    previous = Application.get_env(:jev, :api_key)
    Application.put_env(:jev, :api_key, "test-key-not-a-secret")
    on_exit(fn -> Application.put_env(:jev, :api_key, previous) end)

    me = self()
    reaction = %{"name" => "Brenna Holt", "emotion" => "wary"}

    adapters = %Adapters{
      npc: fn _moment ->
        send(me, :npc)
        [reaction]
      end,
      gm: fn %TalesForge.LLM.GmTurn{messages: messages, opts: opts} ->
        send(me, {:gm, List.last(messages).content})
        opts[:on_text].("Brenna ")
        {:ok, %GMStructuredResponse{narrative: "Brenna looks up."}}
      end,
      stream: fn _id, chunk -> send(me, {:chunk, chunk}) end
    }

    t =
      session
      |> turn("look around", flags: %{npc_reactions: true}, adapters: adapters)
      |> Turn.Premise.check()
      |> Turn.Mechanics.apply()
      |> Turn.Npcs.react()
      |> Turn.Prompt.build()
      |> Turn.Gm.narrate()

    assert t.npcs.reactions == [reaction]
    assert_received :npc
    assert_received {:gm, per_turn}
    assert per_turn =~ "## NPC reactions (this moment)"
    assert_received {:chunk, "Brenna "}
    assert {:ok, %GMStructuredResponse{}} = t.narration
  end

  test "a failed GM call is data; persist passes the turn through", %{session: session} do
    adapters = %Adapters{
      gm: fn %TalesForge.LLM.GmTurn{} -> {:error, :timeout} end,
      store: fn _store -> flunk("the store must not run") end
    }

    result =
      session
      |> turn("look around", adapters: adapters)
      |> Turn.Premise.check()
      |> Turn.Mechanics.apply()
      |> Turn.Npcs.react()
      |> Turn.Prompt.build()
      |> Turn.Gm.narrate()
      |> Turn.Outcome.persist()
      |> Turn.result()

    assert result == {:error, :timeout}
  end

  describe "the notice stage (SKILL_DETAIL_LEVEL)" do
    @wary "Under the surface, Brenna Holt is wary."

    defp noticed(session, mechanical, flags) do
      adapters = %Adapters{
        profiles: fn _id, ids ->
          for id <- ids, do: %{"id" => id, "name" => "Brenna Holt"}
        end
      }

      cast =
        session.id
        |> TalesForge.Characters.cast()
        |> update_in(["innkeep"], &%{&1 | runtime: %{"reaction" => %{"emotion" => "wary"}}})

      t =
        session
        |> turn("I study Brenna's face", flags: flags, adapters: adapters, cast: cast)
        |> Turn.Mechanics.apply()

      t
      |> Map.update!(:outcome, &%{&1 | mechanical: mechanical})
      |> Turn.Npcs.react()
      |> Turn.Notice.select()
      |> Turn.Prompt.build()
    end

    test "a hidden detail appears only at the right level", %{session: session} do
      high = %MechanicalResolution{
        skill: "insight",
        roll: 3,
        effective_skill: 70,
        outcome: "success"
      }

      low = %MechanicalResolution{
        skill: "insight",
        roll: 3,
        effective_skill: 20,
        outcome: "success"
      }

      t = noticed(session, high, %{skill_detail_level: true})
      assert t.notice == %{level: :high, details: [@wary]}
      assert List.last(t.prompt.messages).content =~ @wary
      assert List.last(t.prompt.messages).content =~ "## Noticing (high)"

      t = noticed(session, low, %{skill_detail_level: true})
      assert t.notice == %{level: :low, details: []}
      refute List.last(t.prompt.messages).content =~ @wary
      assert List.last(t.prompt.messages).content =~ "Tunnel vision"
    end

    test "the details go into the outcome record", %{session: session} do
      high = %MechanicalResolution{
        skill: "insight",
        roll: 3,
        effective_skill: 70,
        outcome: "success"
      }

      t = noticed(session, high, %{skill_detail_level: true, turn_outcome_record: true})
      assert t.outcome.board.outcome["notice"] == %{"level" => "high", "details" => [@wary]}
    end

    test "with the flag off the stage passes the turn through", %{session: session} do
      high = %MechanicalResolution{
        skill: "insight",
        roll: 3,
        effective_skill: 70,
        outcome: "success"
      }

      t = noticed(session, high, %{})
      assert t.notice == nil
      refute List.last(t.prompt.messages).content =~ "## Noticing"
    end
  end
end
