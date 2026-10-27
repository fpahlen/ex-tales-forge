defmodule TalesForge.Game.TurnSelfCheckTest do
  @moduledoc """
  The self-check in a turn (`JEV_SELF_CHECK`, `TalesForge.Game.Turn.SelfCheck`):
  Jev's question next to the manner, its answer in the action's parameters,
  the narrow text fallback, a turn that only asks plays no action and costs
  no time, and the GM answers as the narrator from the sheet after the trade
  (h-qa13, h-qa16, h-qa21). With the flag off nothing changes.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{JevIntent, JevSelfCheck, SelfCheck, StateFacts, TurnProcessor}
  alias TalesForge.Game.Schemas.{GMStructuredResponse, PlayerAction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.Adapters
  alias TalesForge.Game.Turn.SelfCheck, as: TurnSelfCheck
  alias TalesForge.GameSessions
  alias TalesForge.IntentEval

  @h_qa13 "What did I order earlier and what does my pack contain?"
  @h_qa16 "I check: how many coins do I have exactly, and did I just sell anything?"
  @h_qa19 "How much money do I have left?"
  @h_qa21 "I buy an ale and count my coins"

  @context %{
    "present_npcs" => ["innkeep"],
    "npc_details" => %{"innkeep" => %{"name" => "Brenna"}}
  }

  describe "the Jev question" do
    test "flag on: asked right after the manner (v2) or the action (v1)" do
      for catalogue <- [:v1, :v2] do
        questions = JevIntent.questions(JevIntent.candidates(@context), catalogue)
        asked = JevSelfCheck.ask(questions, true)
        keys = Keyword.keys(asked)
        before = if catalogue == :v2, do: :manner, else: :action

        assert Enum.at(keys, Enum.find_index(keys, &(&1 == before)) + 1) == :self_check
        assert asked[:self_check] == SelfCheck.question()
        assert Keyword.delete(asked, :self_check) == questions
      end
    end

    test "flag off: the questions do not change" do
      questions = JevIntent.questions(JevIntent.candidates(@context), :v2)
      assert JevSelfCheck.ask(questions, false) == questions
    end
  end

  describe "decode" do
    test "reads the answer into the reading and the action's parameters" do
      for {label, asks, names} <- [
            {:both, [:coins, :pack], ["coins", "pack"]},
            {:coins, [:coins], ["coins"]},
            {:none, [], []}
          ] do
        reading = JevIntent.decode(%{action: :other, self_check: label}, [], text: @h_qa16)
        assert reading.self_check == asks
        assert hd(reading.extraction.actions).parameters["self_check"] == names
      end
    end

    test "no answer (flag off): no reading and no parameter" do
      reading = JevIntent.decode(%{action: :other}, [], text: @h_qa16)
      assert reading.self_check == nil
      refute Map.has_key?(hd(reading.extraction.actions).parameters, "self_check")
    end
  end

  describe "Turn.SelfCheck.asks/1" do
    test "Jev's answer wins over the text; the text fallback when Jev did not read it" do
      assert TurnSelfCheck.asks(turn(@h_qa13, other(%{}))) == [:pack]
      assert TurnSelfCheck.asks(turn(@h_qa13, other(%{"self_check" => ["coins"]}))) == [:coins]
      assert TurnSelfCheck.asks(turn(@h_qa13, other(%{"self_check" => []}))) == []
    end

    test "nothing with the flag off, on a clarify turn or an injection turn" do
      assert TurnSelfCheck.asks(%{turn(@h_qa13, other(%{})) | flags: %{}}) == []

      clarify = %{other(%{}) | clarify: %{"words" => "x"}}
      assert TurnSelfCheck.asks(turn(@h_qa13, clarify)) == []
      assert TurnSelfCheck.asks(%{turn(@h_qa13, other(%{})) | injected: true}) == []
    end
  end

  describe "the eval's Jev reader" do
    setup do
      previous = System.get_env("JEV_SELF_CHECK")
      System.put_env("JEV_SELF_CHECK", "on")

      on_exit(fn ->
        if previous,
          do: System.put_env("JEV_SELF_CHECK", previous),
          else: System.delete_env("JEV_SELF_CHECK")
      end)
    end

    test "JEV_SELF_CHECK=on: asks the question, and Jev's self-checks are scored" do
      Req.Test.stub(Jev.HTTP, fn conn ->
        Jev.Test.respond(conn,
          action: :other,
          skill: :none,
          later: :none,
          safety: :benign,
          self_check: :coins,
          confidence: %{action: 0.9}
        )
      end)

      {_report, results} =
        IntentEval.run(split: "tune", readers: [:jev], limit: 5, jev: [api_key: "test-key"])

      assert results.metrics[:jev].self_check.read == 5
    end
  end

  describe "a whole turn" do
    setup do
      previous = System.get_env("INN_WORLD")
      System.put_env("INN_WORLD", "on")

      on_exit(fn ->
        if previous,
          do: System.put_env("INN_WORLD", previous),
          else: System.delete_env("INN_WORLD")
      end)

      {:ok, session} = GameSessions.create_session(%{name: "Self", adventure_id: "tin_valley"})
      {:ok, session: GameSessions.get_session!(session.id)}
    end

    test "h-qa13 (text fallback): the narrator lists the pack, no action, no time",
         %{session: session} do
      {prompt, ticks, world} = play(session, @h_qa13, action("other"), on())

      assert prompt =~ "Narrator, not an NPC: the player asks about their own pack."
      assert prompt =~ "Pack: #{fact(world, :pack)}."
      refute prompt =~ "Coins: #{fact(world, :coins)}. State"
      assert_narrator(prompt)
      assert ticks == 0
    end

    test "h-qa16 (Jev's answer): the narrator states the coins, no action, no time",
         %{session: session} do
      read = action("other", %{"self_check" => ["coins"]})
      {prompt, ticks, world} = play(session, @h_qa16, read, on())

      assert prompt =~ "Narrator, not an NPC: the player asks about their own coins."
      assert prompt =~ "Coins: #{fact(world, :coins)}."
      assert_narrator(prompt)
      assert ticks == 0
    end

    test "h-qa19 (a speak with no target that asks): the narrator states the coins, no time",
         %{session: session} do
      read = action("speak", %{"self_check" => ["coins"]})
      {prompt, ticks, world} = play(session, @h_qa19, read, on())

      assert prompt =~ "Coins: #{fact(world, :coins)}."
      assert_narrator(prompt)
      assert ticks == 0
    end

    test "a bare speak with no target that asks nothing keeps its time (shouting)",
         %{session: session} do
      read = action("speak", %{"self_check" => []})
      {prompt, ticks, _world} = play(session, "I shout: the north road is closed!", read, on())

      refute prompt =~ "Narrator, not an NPC"
      refute prompt =~ ~s("handler": "narrate")
      assert ticks > 0
    end

    test "h-qa21: the purchase plays, and the coins are the ones after it",
         %{session: session} do
      before = fact(session.world_state, :coins)
      buy = action("buy", %{"item_id" => "ale_mug"}, "innkeep")
      {prompt, _ticks, world} = play(session, @h_qa21, buy, on())

      assert prompt =~ "The server made this trade: bought 1x ale_mug for 2c."
      assert fact(world, :coins) != before
      assert prompt =~ "Coins: #{fact(world, :coins)}. State these facts as the narrator"
      refute prompt =~ "Coins: #{before}. State"
    end

    test "flag off: no self-check line, and the turn plays as before", %{session: session} do
      {:ok, other} = GameSessions.create_session(%{name: "Off", adventure_id: "tin_valley"})
      {prompt, ticks, _world} = play(session, @h_qa13, action("other"), %{})

      {on_prompt, on_ticks, _} =
        play(GameSessions.get_session!(other.id), "I look around.", action("other"), on())

      refute prompt =~ "Narrator, not an NPC"
      refute prompt =~ ~s("self_check")
      # Off, the question plays as an everyday action and costs its time.
      assert ticks > 0
      # A turn that asks nothing plays the same with the flag on.
      refute on_prompt =~ "Narrator, not an NPC"
      assert on_ticks == ticks
    end
  end

  defp on, do: %{jev_self_check: true}

  defp assert_narrator(prompt) do
    assert prompt =~ "no character in the scene answers or comments on them."
    assert prompt =~ ~s("handler": "narrate")
    assert prompt =~ ~s("target": null)
  end

  defp fact(world, ask),
    do: Map.fetch!(SelfCheck.resolve(StateFacts.build(world["character"] || %{}), [ask]), ask)

  defp other(params),
    do: %PlayerAction{
      overall_intent: "x",
      action: %SingleAction{action_type: :other, target: nil, parameters: params}
    }

  defp turn(text, action),
    do: %Turn{raw_action: text, intent: action, flags: on()}

  defp action(type, params \\ %{}, target \\ nil),
    do: %{"action_type" => type, "target" => target, "parameters" => params}

  # Plays `text` as `action` and gives the GM prompt, the ticks the turn cost
  # and the world after it.
  defp play(session, text, action, flags) do
    me = self()

    adapters = %Adapters{
      npc: fn _moment -> [] end,
      stream: fn _id, _chunk -> :ok end,
      gm: fn %TalesForge.LLM.GmTurn{messages: messages} ->
        send(me, {:gm_prompt, List.last(messages).content})
        {:ok, %GMStructuredResponse{narrative: "You look."}}
      end
    }

    read = %{"overall_intent" => text, "action" => action}

    assert {:ok, _payload} =
             TurnProcessor.run(session.id, {text, read},
               adapters: adapters,
               flags: flags,
               role: :playtest
             )

    assert_received {:gm_prompt, prompt}
    world = GameSessions.get_session!(session.id).world_state
    {prompt, world["world_tick"] - session.world_state["world_tick"], world}
  end
end
