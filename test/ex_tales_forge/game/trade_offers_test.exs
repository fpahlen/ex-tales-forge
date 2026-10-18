defmodule TalesForge.Game.TradeOffersTest do
  @moduledoc """
  Offer, then accept (`docs/design-trade-offers.md`), played through
  `GameSessions.submit_message/3` with INTENT_JEV on, like
  `TalesForge.Game.TradeRetest470Test`. Jev and the GM are stubbed; the
  Jev stub answers the open-offer questions only when the request asks
  them (`Jev.Test` raises on an answer to a question it was not asked).

  Fredrik's rules: coins and items only change place; a trade needs both
  sides to accept, else nothing moves.
  """
  use TalesForge.DataCase, async: false

  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.{Inventory, JevIntent}
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.Character

  setup do
    previous = Map.new(~w(INN_WORLD TURN_APPLY_OUTCOMES), &{&1, System.get_env(&1)})
    Enum.each(previous, fn {name, _} -> System.put_env(name, "on") end)
    endpoints = Application.get_env(:jev, :endpoints)

    Application.put_env(:jev, :endpoints,
      intent: [base_url: "https://api.typesafe.ai", api_key: "test-key", model: "jev-1.13.0"]
    )

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)

      Application.put_env(:jev, :endpoints, endpoints)
      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("XAI_API_KEY")
    end)

    {:ok, session} =
      GameSessions.create_session(%{
        name: "TradeOffers",
        adventure_id: "tin_valley",
        intent_jev: "on"
      })

    {:ok, session: session}
  end

  test "a quote, then accept: the ale is served and paid", %{session: session} do
    {before, quoted} = play(session.id, "How much for a mug of ale, Brenna?", :buy)
    assert diff(before, quoted) == []
    assert %{"item" => %{"id" => "ale_mug"}, "price" => 2} = open_offer(session.id)
    assert last_gm() =~ "The server quotes: Brenna Holt sells Ale for 2c"

    {_, accepted} = play(session.id, "Yes, one please.", :speak, offer_answer: :accept)
    assert copper(accepted, "innkeep") == copper(quoted, "innkeep") + 2
    assert copper(accepted, "player") == copper(quoted, "player") - 2
    assert qty(accepted, "innkeep", "ale_mug") == qty(quoted, "innkeep", "ale_mug") - 1
    assert open_offer(session.id) == nil
    assert_conserved(before, accepted)
  end

  test "a quote, then decline: nothing moves and the offer closes", %{session: session} do
    {before, _} = play(session.id, "How much for a mug of ale, Brenna?", :buy)
    {_, declined} = play(session.id, "No thanks, too dear.", :speak, offer_answer: :decline)

    assert diff(before, declined) == []
    assert open_offer(session.id) == nil
    assert last_gm() =~ "The player declined the offer"
  end

  test "a quote, then leaving the place: the offer expires, a later yes moves nothing",
       %{session: session} do
    {before, _} = play(session.id, "How much for a mug of ale, Brenna?", :buy)

    {_, left} =
      play(session.id, "I walk to the smithy.", :move, target: "smithy", offer_answer: :other)

    assert open_offer(session.id) == nil
    assert diff(before, left) == []

    # No offer is open, so Jev is not asked about one (the stub raises if it answers one).
    {_, after_yes} = play(session.id, "Yes, one please.", :speak, target: nil)
    refute_received {:jev_questions, %{"offer_answer" => _}}
    assert diff(before, after_yes) == []
  end

  test "an unanswered quote expires after 2 turns", %{session: session} do
    play(session.id, "How much for a mug of ale, Brenna?", :buy)

    play(session.id, "I look around the common room.", :observe,
      target: nil,
      offer_answer: :other
    )

    assert %{"age" => 1} = open_offer(session.id)
    play(session.id, "Nice weather.", :speak, offer_answer: :other)
    assert open_offer(session.id) == nil
  end

  test "'I buy X' trades in one step", %{session: session} do
    {before, bought} = play(session.id, "I buy a mug of ale from Brenna.", :buy)
    assert copper(bought, "innkeep") == copper(before, "innkeep") + 2
    assert copper(bought, "player") == copper(before, "player") - 2
    assert qty(bought, "innkeep", "ale_mug") == qty(before, "innkeep", "ale_mug") - 1
    assert open_offer(session.id) == nil
  end

  test "an unclear 'I order a meal': a counter-question with options from the pack, then the pick trades",
       %{session: session} do
    {before, asked} = play(session.id, "I order a meal.", :buy)
    assert diff(before, asked) == []

    assert %{
             "item" => nil,
             "options" => [
               %{"item" => %{"id" => "bread_cheese"}, "price" => 2},
               %{"item" => %{"id" => "stew_bowl"}, "price" => 5}
             ]
           } =
             open_offer(session.id)

    assert last_gm() =~
             "The server listed these options from stock: Brenna Holt has Bread and Cheese for 2c, or Bowl of Stew for 5c"

    {_, picked} =
      play(session.id, "The stew, please.", :speak, offer_answer: :accept, offer_pick: :o1)

    assert_received {:jev_questions, %{"offer_pick" => _}}
    assert copper(picked, "innkeep") == copper(asked, "innkeep") + 5
    assert copper(picked, "player") == copper(asked, "player") - 5
    assert qty(picked, "innkeep", "stew_bowl") == qty(asked, "innkeep", "stew_bowl") - 1
    # A serving from the pot is eaten at the table: nobody carries it.
    assert qty(picked, "player", "stew_bowl") == 0
    assert qty(picked, "innkeep", "bread_cheese") == qty(asked, "innkeep", "bread_cheese")
    assert open_offer(session.id) == nil
    assert_conserved(before, picked)
  end

  test "a plain yes to an unclear buy picks nothing: the offer stays open, then a pick buys",
       %{session: session} do
    {before, _} = play(session.id, "I order a meal.", :buy)
    offered = open_offer(session.id)

    {_, yes} = play(session.id, "Yes, please.", :buy, offer_answer: :accept)
    assert diff(before, yes) == []
    assert open_offer(session.id) == offered
    assert last_gm() =~ "The player said yes but picked none of the options"

    {_, picked} =
      play(session.id, "Bread and cheese.", :speak, offer_answer: :accept, offer_pick: :o0)

    assert copper(picked, "player") == copper(yes, "player") - 2
    assert copper(picked, "innkeep") == copper(yes, "innkeep") + 2
    assert qty(picked, "innkeep", "bread_cheese") == qty(yes, "innkeep", "bread_cheese") - 1
    assert open_offer(session.id) == nil
    assert_conserved(before, picked)
  end

  test "an unclear buy with no matching stock: no offer, nothing moves", %{session: session} do
    stock(session.id, fn stock ->
      Enum.reject(stock, &(&1["id"] in ~w(stew_bowl bread_cheese)))
    end)

    {before, after_order} = play(session.id, "I order a meal.", :buy)
    assert diff(before, after_order) == []
    assert open_offer(session.id) == nil
  end

  test "the NPC refuses: out of stock after the quote, nothing moves", %{session: session} do
    play(session.id, "How much for a mug of ale, Brenna?", :buy)
    stock(session.id, fn stock -> Enum.map(stock, &Map.put(&1, "quantity", 0)) end)
    before = snapshot(session.id)

    {_, refused} = play(session.id, "Yes, one please.", :speak, offer_answer: :accept)
    assert diff(before, refused) == []
    assert last_gm() =~ "The server refused this trade"
  end

  test "the NPC refuses: the player cannot pay, nothing moves", %{session: session} do
    play(session.id, "How much for a mug of ale, Brenna?", :buy)

    Character
    |> where([c], c.game_session_id == ^session.id and c.controller == "player")
    |> Repo.update_all(set: [coins: %{"copper" => 1}])

    before = snapshot(session.id)
    # The ale is in stock: only the purse refuses the trade.
    assert qty(before, "innkeep", "ale_mug") > 1
    {_, refused} = play(session.id, "Yes, one please.", :speak, offer_answer: :accept)
    assert diff(before, refused) == []
    assert last_gm() =~ "cannot pay 2c"
  end

  # Gentry's retest of #476 (session 6d938a30), T1-T2. Jev read the price
  # question as talk, so no offer opened; the GM quoted 2c and offered
  # kindling work in the same reply, and the "Yes." took the work: 0c moved.
  # Jev now reads a price question as `ask_price` (any language: the game
  # never reads the words), and the yes against the open offer in its state.
  test "ask_price quotes the item; Jev's accept of the open offer buys it, not the GM's side offer",
       %{session: session} do
    {before, quoted} =
      play(session.id, "Vad kostar en öl?", :ask_price,
        target: "ale_mug",
        narrative:
          "\"Two copper for the ale, love.\" Brenna glances at the hearth. " <>
            "\"And if you've a mind for work, the kindling wants splitting.\""
      )

    assert diff(before, quoted) == []
    assert %{"item" => %{"id" => "ale_mug"}, "price" => 2} = open_offer(session.id)
    assert last_gm() =~ "The server quotes: Brenna Holt sells Ale for 2c"

    {_, accepted} = play(session.id, "Ja.", :speak, offer_answer: :accept)

    assert_received {:jev_request,
                     %{"state" => %{"open_offer" => "Brenna Holt sells Ale for 2c"}}}

    assert copper(accepted, "player") == copper(quoted, "player") - 2
    assert copper(accepted, "innkeep") == copper(quoted, "innkeep") + 2
    assert qty(accepted, "innkeep", "ale_mug") == qty(quoted, "innkeep", "ale_mug") - 1
    assert open_offer(session.id) == nil
    assert_conserved(before, accepted)
  end

  test "ask_price on a kind of goods lists the options from stock, and nothing moves",
       %{session: session} do
    {before, asked} =
      play(session.id, "What's on for supper?", :ask_price, target: "goods:a meal")

    assert diff(before, asked) == []

    assert %{
             "item" => nil,
             "options" => [
               %{"item" => %{"id" => "bread_cheese"}, "price" => 2},
               %{"item" => %{"id" => "stew_bowl"}, "price" => 5}
             ]
           } = open_offer(session.id)

    assert last_gm() =~ "The server listed these options from stock"
  end

  # Same session, T5-T6: a plain "Yes." to Brenna's meal options got the
  # generic question "Do you want to buy Brenna Holt, or talk to Brenna
  # Holt?" instead of her "which one?".
  test "a yes to the options is not a generic clarification: the seller asks which one",
       %{session: session} do
    {before, _} = play(session.id, "I'd like a meal.", :buy)
    offered = open_offer(session.id)
    assert %{"item" => nil, "options" => [_, _]} = offered

    # Jev accepts the open offer but is unsure between buying and talking:
    # without the open offer this asks the player which one they meant.
    {_, yes} =
      play(session.id, "Yes.", :buy,
        offer_answer: :accept,
        confidence: %{action: 0.3, target: 0.95, safety: 0.99},
        probabilities: %{action: %{buy: 0.5, speak: 0.45, observe: 0.05}}
      )

    assert diff(before, yes) == []
    assert open_offer(session.id) == offered
    assert last_gm() =~ "The player said yes but picked none of the options"
  end

  # The Jev request (state and questions) while an offer with options is
  # open, against `test/fixtures/jev/open_offer_request.json` (rewrite it
  # with UPDATE_JEV_GOLDEN=1): the action question has `ask_price`, the
  # state the open offer with its options, and the offer questions are asked.
  @jev_golden Path.expand("../../fixtures/jev/open_offer_request.json", __DIR__)
  test "Jev prompt fixture: ask_price and the open offer with its options", %{session: session} do
    play(session.id, "I'd like a meal.", :buy)
    play(session.id, "Hmm.", :speak, offer_answer: :other)
    assert_received {:jev_request, request}

    golden = Jason.encode!(Map.take(request, ["state", "questions"]), pretty: true) <> "\n"

    if System.get_env("UPDATE_JEV_GOLDEN") == "1" do
      File.mkdir_p!(Path.dirname(@jev_golden))
      File.write!(@jev_golden, golden)
    end

    assert golden == File.read!(@jev_golden)
    assert golden =~ ~s("ask_price")
    assert golden =~ "costs, without buying it yet"
    assert golden =~ "a meal: Bread and Cheese or Bowl of Stew (for sale)"

    assert request["state"]["open_offer"] ==
             "Brenna Holt has Bread and Cheese for 2c, or Bowl of Stew for 5c"

    assert golden =~ "Open offer: Brenna Holt has Bread and Cheese for 2c, or Bowl of Stew for 5c"
    assert golden =~ "Which of the offered options does the player pick?"
  end

  # One turn: Jev reads `action` at `opts[:target]` (default the innkeep)
  # and answers the offer questions in `opts`; the GM narrates a line.
  # Gives the snapshots before and after, conserved.
  defp play(session_id, text, action, opts \\ []) do
    context = TalesForge.Game.Context.build_intent_context(GameSessions.get_session!(session_id))
    target_id = Keyword.get(opts, :target, "innkeep")

    target =
      Enum.find_value(JevIntent.candidates(context), :none, &(&1.id == target_id && &1.label))

    answers = Map.new(Keyword.take(opts, [:offer_answer, :offer_pick, :probabilities]))
    confidence = Keyword.get(opts, :confidence, %{action: 0.95, target: 0.95, safety: 0.99})
    narrative = Keyword.get(opts, :narrative, "Brenna nods.")
    test = self()

    Req.Test.stub(Jev.HTTP, fn conn ->
      {request, conn} = Jev.Test.request(conn)
      send(test, {:jev_questions, request["questions"]})
      send(test, {:jev_request, request})

      Jev.Test.respond(
        conn,
        Map.merge(answers, %{
          action: action,
          target: target,
          skill: :none,
          later: :none,
          safety: :benign,
          confidence: confidence
        })
      )
    end)

    stub_llm(fn
      :gm, user, _system ->
        send(test, {:gm_prompt, user})
        %{"narrative" => narrative, "context_summary" => "", "npc_memory_updates" => []}

      _kind, _user, _system ->
        :default
    end)

    flush()
    before = snapshot(session_id)
    assert {:ok, %{status: :processing}} = GameSessions.submit_message(session_id, text)
    {:ok, _} = GameSessions.ensure_scene(session_id)
    now = snapshot(session_id)
    assert_conserved(before, now)
    {before, now}
  end

  defp flush do
    receive do
      {:jev_questions, _} -> flush()
      {:jev_request, _} -> flush()
    after
      0 -> :ok
    end
  end

  defp last_gm do
    receive_all(nil)
  end

  defp receive_all(last) do
    receive do
      {:gm_prompt, user} -> receive_all(user)
    after
      0 -> last || ""
    end
  end

  defp open_offer(session_id), do: GameSessions.get_session!(session_id).world_state["open_offer"]

  defp stock(session_id, fun) do
    [brenna] = session_id |> NPC.traders(["innkeep"]) |> Map.values()
    NPC.put_inventories(session_id, [%{brenna | inventory: fun.(brenna.inventory)}])
  end

  # Coins and items are conserved; a serving (Brenna's ale, stew, bread and
  # cheese) is eaten or drunk where it is bought, so it leaves her cask or
  # pot and nobody carries it.
  @servings ~w(ale_mug stew_bowl bread_cheese)
  defp assert_conserved(before, now) do
    {coins_before, items_before} = totals(before)
    {coins_now, items_now} = totals(now)
    assert coins_before == coins_now
    assert items_before == items_now
  end

  defp snapshot(session_id) do
    Character
    |> where([c], c.game_session_id == ^session_id)
    |> Repo.all()
    |> Map.new(fn c ->
      slug = if c.controller == "player", do: "player", else: c.slug

      items =
        Enum.reduce(
          c.inventory || [],
          %{},
          &Map.update(&2, &1.id, &1.quantity || 1, fn q -> q + (&1.quantity || 1) end)
        )

      {slug, {Inventory.coin_total_copper(c.coins || %{}), items}}
    end)
  end

  defp totals(snap) do
    snap
    |> Map.values()
    |> Enum.reduce({0, %{}}, fn {c, items}, {sum, all} ->
      {sum + c, Map.merge(all, Map.drop(items, @servings), fn _k, a, b -> a + b end)}
    end)
  end

  defp diff(a, b), do: for({k, v} <- b, a[k] != v, do: {k, a[k], v})
  defp copper(snap, who), do: elem(snap[who], 0)
  defp qty(snap, who, id), do: Map.get(elem(snap[who], 1), id, 0)
end
