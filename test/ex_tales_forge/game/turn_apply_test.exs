defmodule TalesForge.Game.TurnApplyTest do
  @moduledoc """
  TURN_APPLY_OUTCOMES: stage 3 applies sleep, pay and move to the state.
  The cases come from Gentry's v179 playtest session 75bc6057.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Context
  alias TalesForge.Game.Intent

  alias TalesForge.Game.Schemas.{
    GMStructuredResponse,
    IntentExtraction,
    PlayerAction,
    SingleAction
  }

  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.{Adapters, Store}
  alias TalesForge.GameSessions

  alias TalesForge.Game.WorldClock

  doctest TalesForge.Game.TurnApply
  doctest TalesForge.Game.WorldClock, only: [ticks_to_morning: 1]

  @room_copper 30

  defp play(session, text, action, flags) do
    me = self()

    adapters = %Adapters{
      npc: fn _moment -> [] end,
      gm: fn %TalesForge.LLM.GmTurn{messages: messages} ->
        send(me, {:gm_prompt, messages |> Enum.map_join("\n", &to_string(&1.content))})

        {:ok, %GMStructuredResponse{narrative: "The night passes."}}
      end,
      stream: fn _id, _chunk -> :ok end,
      store: fn %Store{world: world, ctx: ctx} ->
        send(me, {:stored, world, ctx.handler})
        {:ok, %{}}
      end
    }

    player_action = %PlayerAction{overall_intent: text, action: intent(session, text, action)}

    {session, 1}
    |> Turn.new({text, player_action}, adapters: adapters, flags: flags, role: :playtest)
    |> Turn.Premise.check()
    |> Turn.Mechanics.apply()
    |> Turn.Reactions.react()
    |> Turn.Place.settle()
    |> Turn.Notice.select()
    |> Turn.Prompt.build()
    |> Turn.Gm.narrate()
    |> Turn.Outcome.persist()

    assert_received {:stored, world, handler}
    {world, handler}
  end

  defp copper(coins),
    do:
      Map.get(coins, "gold", 0) * 500 + Map.get(coins, "silver", 0) * 10 +
        Map.get(coins, "copper", 0)

  # A move is validated by the intent step, as Jev's reading is
  # (`TalesForge.Game.Intent`): the words settle where it goes.
  defp intent(session, text, %SingleAction{action_type: :move} = move) do
    extraction = %IntentExtraction{overall_intent: text, actions: [move]}
    Intent.validate_player_action(extraction, Context.build_intent_context(session)).action
  end

  defp intent(_session, _text, action), do: action

  defp session(adventure, location, present) do
    {:ok, session} = GameSessions.create_session(%{name: "Apply", adventure_id: adventure})

    world =
      session.world_state
      |> Map.put("location_id", location)
      |> put_in(["character", "location_id"], location)
      |> Map.put("present_npcs", present)

    %{session | world_state: world}
  end

  @on %{turn_apply_outcomes: true}
  @spend %SingleAction{action_type: :spend, target: nil, parameters: %{"amount_copper" => 0}}
  @pay_sleep "I pay for a room and go to sleep"

  describe "pay for a room and go to sleep" do
    test "at the inn: the room costs coins and the clock moves 8 hours" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      tick = s.world_state["world_tick"]

      {world, _handler} = play(s, @pay_sleep, @spend, @on)

      assert copper(world["character"]["coins"]) ==
               copper(s.world_state["character"]["coins"]) - @room_copper

      assert world["world_tick"] == tick + WorldClock.ticks_to_morning(tick)
    end

    test "in the square: the payment is rejected and the clock moves 1 hour" do
      s = session("crossroads_ledger", "crossroads_square", [])
      tick = s.world_state["world_tick"]

      {world, handler} = play(s, @pay_sleep, @spend, @on)

      assert handler.state_hints["lodging_rejected"]
      assert world["character"]["coins"] == s.world_state["character"]["coins"]
      assert world["world_tick"] == tick + 4
    end

    test "with no coins: the clock moves 1 hour" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])

      s =
        put_in(s.world_state["character"]["coins"], %{"gold" => 0, "silver" => 0, "copper" => 0})

      tick = s.world_state["world_tick"]

      {world, handler} = play(s, @pay_sleep, @spend, @on)

      assert handler.notes =~ "no paid bed"
      assert world["world_tick"] == tick + 4
    end

    test "flag off: the turn plays as before (no coins, one tick)" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      tick = s.world_state["world_tick"]

      {world, _handler} = play(s, @pay_sleep, @spend, %{})

      assert world["character"]["coins"] == s.world_state["character"]["coins"]
      assert world["world_tick"] == tick + 1
    end
  end

  test "sleep in the field: no bed, and the clock moves 1 hour" do
    s = session("crossroads_ledger", "crossroads_square", [])
    tick = s.world_state["world_tick"]
    rest = %SingleAction{action_type: :rest, target: nil, parameters: %{}}

    {world, handler} = play(s, "I lie down in the field and go to sleep", rest, @on)

    assert handler.notes =~ "no bed"
    assert world["world_tick"] == tick + 4
  end

  test "a payment in silver words costs that amount" do
    s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])

    {world, _handler} = play(s, "I pay Marta two silver for the ale", @spend, @on)

    assert copper(world["character"]["coins"]) == copper(s.world_state["character"]["coins"]) - 20
  end

  # #470 retest (session 8a9dbde9): an ale is bought from the stock, so
  # the seller is paid; a payment with no amount and no seller moves nothing.
  test "an ale paid with no amount is no payment: nothing moves" do
    s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])

    {world, _handler} = play(s, "I pay for an ale", @spend, @on)

    assert world["character"]["coins"] == s.world_state["character"]["coins"]
  end

  describe "move" do
    test "to an unknown place: no move, and the GM is told there is no such place" do
      s = session("crossroads_ledger", "crossroads_square", [])
      move = %SingleAction{action_type: :move, target: "fields", parameters: %{}}

      {world, _handler} = play(s, "I walk into the fields", move, @on)

      assert world["location_id"] == "crossroads_square"
      assert gm_prompt() =~ "There's no fields you know of."
      assert world["world_tick"] == s.world_state["world_tick"]
    end

    test "to a known place: the location changes" do
      s = session("crossroads_ledger", "crossroads_square", [])
      move = %SingleAction{action_type: :move, target: "weary_pilgrim", parameters: %{}}

      {world, _handler} = play(s, "I walk to the inn", move, @on)

      assert world["location_id"] == "weary_pilgrim"
    end
  end

  describe "Gentry's live session f3a7bac0 (2026-10-13), Jev readings as recorded" do
    test "turn 3: 'old mill' read as a move to the Weary Pilgrim is rejected" do
      s = session("crossroads_ledger", "crossroads_square", ["worried_merchant"])
      move = %SingleAction{action_type: :move, target: "weary_pilgrim", parameters: %{}}

      {world, _handler} = play(s, "I walk to the old mill by the creek.", move, @on)

      assert world["location_id"] == "crossroads_square"
      assert gm_prompt() =~ "There's no old mill you know of."
    end

    test "turn 4: 'the Weary Pilgrim inn' read as the cellar goes to the Weary Pilgrim" do
      s = session("crossroads_ledger", "crossroads_square", ["worried_merchant"])
      move = %SingleAction{action_type: :move, target: "pilgrim_cellar", parameters: %{}}

      {world, _handler} = play(s, "I go into the Weary Pilgrim inn.", move, @on)

      assert world["location_id"] == "weary_pilgrim"
      assert "marta_kellen" in world["present_npcs"]
    end

    test "turn 5: 'I buy an ale' read as a purchase costs 2c" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      buy = %SingleAction{action_type: :buy, target: nil, parameters: %{}}

      {world, _handler} = play(s, "I buy an ale.", buy, @on)

      assert copper(world["character"]["coins"]) ==
               copper(s.world_state["character"]["coins"]) - 2
    end

    # #470 retest (session 8a9dbde9): Marta has no meal in stock, so
    # nothing moves and the GM is told.
    test "turn 6: 'I order a meal' from Marta, who sells none: nothing moves" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      buy = %SingleAction{action_type: :buy, target: "marta_kellen", parameters: %{}}

      {world, _handler} = play(s, "I order a meal.", buy, @on)

      assert world["character"]["coins"] == s.world_state["character"]["coins"]
      assert gm_prompt() =~ "The server refused this trade"
    end

    test "turn 8: a room payment to Marta at the inn costs the room and 8 hours" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      tick = s.world_state["world_tick"]
      pay = %SingleAction{action_type: :spend, target: "marta_kellen", parameters: %{}}

      {world, _handler} = play(s, "I pay for a room and go to sleep.", pay, @on)

      assert copper(world["character"]["coins"]) ==
               copper(s.world_state["character"]["coins"]) - @room_copper

      assert world["world_tick"] == tick + WorldClock.ticks_to_morning(tick)
    end
  end

  defp gm_prompt do
    assert_received {:gm_prompt, text}
    text
  end

  describe "Gentry's v195 retest sessions 141e1b85 and 1c82f268 (2026-10-13), Jev readings as recorded" do
    test "141e1b85 turn 1: 'old mill' from the inn (Jev: square) is rejected, and the GM gets the exits" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      move = %SingleAction{action_type: :move, target: "crossroads_square", parameters: %{}}

      {world, _handler} = play(s, "I walk to the old mill by the creek", move, @on)
      prompt = gm_prompt()

      assert world["location_id"] == "weary_pilgrim"
      assert prompt =~ "There's no old mill you know of."
    end

    test "1c82f268 turn 2: 'old mill' from the square (Jev: kings_road) is rejected" do
      s = session("crossroads_ledger", "crossroads_square", ["worried_merchant"])
      move = %SingleAction{action_type: :move, target: "kings_road", parameters: %{}}

      {world, _handler} = play(s, "I walk to the old mill by the creek", move, @on)
      prompt = gm_prompt()

      assert world["location_id"] == "crossroads_square"
      assert prompt =~ "There's no old mill you know of."
    end

    test "141e1b85 turn 2: 'into the Weary Pilgrim inn' in the inn (Jev: square) stays, with no walk" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      move = %SingleAction{action_type: :move, target: "crossroads_square", parameters: %{}}

      {world, handler} = play(s, "I go into the Weary Pilgrim inn", move, @on)
      prompt = gm_prompt()

      assert world["location_id"] == "weary_pilgrim"
      assert handler.state_hints["same_place"] == true
      assert prompt =~ "Narrate no walk."
      assert prompt =~ "Location: weary_pilgrim (no move)."
    end

    test "1c82f268 turn 1: 'I walk out to Crossroads Square' from the inn moves" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      move = %SingleAction{action_type: :move, target: "crossroads_square", parameters: %{}}

      {world, _handler} = play(s, "I walk out to Crossroads Square", move, @on)

      assert world["location_id"] == "crossroads_square"
    end

    test "turn 3 / turn 4: 'I buy an ale' (Jev: target ale_mug) costs the stock price 2c, and the GM gets it" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      buy = %SingleAction{action_type: :buy, target: "ale_mug", parameters: %{}}

      {world, _handler} = play(s, "I buy an ale", buy, @on)

      assert copper(world["character"]["coins"]) ==
               copper(s.world_state["character"]["coins"]) - 2

      assert gm_prompt() =~ "Coins: -2 copper"
    end

    test "141e1b85 turn 4: 'I buy a meal' (Jev: no target) with no meal for sale moves nothing" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      buy = %SingleAction{action_type: :buy, target: nil, parameters: %{}}

      {world, _handler} = play(s, "I buy a meal", buy, @on)

      assert world["character"]["coins"] == s.world_state["character"]["coins"]
      assert gm_prompt() =~ "The server refused this trade"
    end

    test "141e1b85 turn 5: room and sleep give the GM the clock after the sleep" do
      s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])
      pay = %SingleAction{action_type: :spend, target: "marta_kellen", parameters: %{}}

      {world, _handler} = play(s, "I pay for a room and go to sleep", pay, @on)

      assert gm_prompt() =~ "Time: #{world["world_clock"]}."
    end
  end

  test "session 11f60fb5 turn 7: room and sleep at dusk (tick 41) wake in the morning, and the GM gets that time" do
    s = session("crossroads_ledger", "weary_pilgrim", ["marta_kellen"])

    s = %{
      s
      | world_state:
          s.world_state
          |> Map.put("world_tick", 41)
          |> Map.put("world_clock", WorldClock.format(41))
    }

    pay = %SingleAction{action_type: :spend, target: "marta_kellen", parameters: %{}}

    {world, _handler} = play(s, "I pay for a room and go to sleep", pay, @on)
    prompt = gm_prompt()

    assert world["world_clock"] == "Day 2 · morning"
    assert prompt =~ "The character wakes at Day 2 · morning."
    assert prompt =~ "Time: Day 2 · morning."
  end
end
