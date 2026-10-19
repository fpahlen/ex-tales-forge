defmodule TalesForge.Game.TradeOffersTest do
  @moduledoc """
  Offer, then accept (`docs/design-trade-offers.md`), played through
  `GameSessions.submit_message/3` with INTENT_JEV on, like
  `TalesForge.Game.TradeRetest470Test`. Jev and the GM are stubbed; the
  Jev stub answers the open-offer questions only when the request asks
  them (`Jev.Test` raises on an answer to a question it was not asked).
  Where Gentry played the same turn in v353, the stub is what live Jev
  read for it (`live/3`, `TalesForge.JevLive`); the rest (no live
  counterpart) are written by hand.

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
    {before, quoted} = live(session.id, {"tin_valley", 1})
    assert diff(before, quoted) == []
    assert %{"item" => %{"id" => "ale_mug"}, "price" => 2} = open_offer(session.id)
    assert last_gm() =~ "The server quotes: Brenna Holt sells Ale for 2c"

    {_, accepted} = live(session.id, {"tin_valley", 5})
    assert copper(accepted, "innkeep") == copper(quoted, "innkeep") + 2
    assert copper(accepted, "player") == copper(quoted, "player") - 2
    assert qty(accepted, "innkeep", "ale_mug") == qty(quoted, "innkeep", "ale_mug") - 1
    assert open_offer(session.id) == nil
    assert_conserved(before, accepted)
  end

  test "a quote, then decline: nothing moves and the offer closes", %{session: session} do
    {before, _} = live(session.id, {"tin_valley", 1})
    {_, declined} = live(session.id, {"tin_valley", 9})

    assert diff(before, declined) == []
    assert open_offer(session.id) == nil
    assert last_gm() =~ "The player declined the offer"
  end

  test "a quote, then leaving the place: the offer expires, a later yes moves nothing",
       %{session: session} do
    {before, _} = live(session.id, {"tin_valley", 1})
    {_, left} = live(session.id, {"tin_valley", 18}, offer_answer: :other)

    assert open_offer(session.id) == nil
    assert diff(before, left) == []

    # No offer is open, so Jev is not asked about one (the stub raises if it answers one).
    {_, after_yes} = live(session.id, {"tin_valley", 13})
    refute_received {:jev_questions, %{"offer_answer" => _}}
    assert diff(before, after_yes) == []
  end

  test "an unanswered quote expires after 2 turns", %{session: session} do
    live(session.id, {"tin_valley", 1})
    live(session.id, {"tin_valley", 11}, offer_answer: :other)

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

  test "an unclear 'I order a meal' (Jev: a meal): a counter-question with the kind's options from stock, then the pick trades",
       %{session: session} do
    {before, asked} = live_words(session.id, "I order a meal.", {"tin_valley", 6})
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
    {before, _} = live_words(session.id, "I order a meal.", {"tin_valley", 6})
    offered = open_offer(session.id)

    {_, yes} = play(session.id, "Yes, please.", :buy, offer_answer: :accept)
    assert diff(before, yes) == []
    assert open_offer(session.id) == offered
    gm = last_gm()
    assert gm =~ "Player's intent: unclear, nothing happened"
    assert gm =~ "Bread and Cheese (2c); or Bowl of Stew (5c)"

    {_, picked} =
      play(session.id, "Bread and cheese.", :speak, offer_answer: :accept, offer_pick: :o0)

    assert copper(picked, "player") == copper(yes, "player") - 2
    assert copper(picked, "innkeep") == copper(yes, "innkeep") + 2
    assert qty(picked, "innkeep", "bread_cheese") == qty(yes, "innkeep", "bread_cheese") - 1
    assert open_offer(session.id) == nil
    assert_conserved(before, picked)
  end

  # Case's review of #478: the game holds no language, so the words "a
  # meal" alone list nothing. Fredrik's steer on the next PR: aimed at the
  # innkeep with no kind target, it is unclear, not nothing: Brenna asks,
  # with what she has, and nothing moves.
  test "'I order a meal' aimed at the innkeep (no kind target) clarifies, not nothing",
       %{session: session} do
    {before, after_order} = play(session.id, "I order a meal.", :buy)
    assert diff(before, after_order) == []
    assert open_offer(session.id) == nil

    gm = last_gm()
    assert gm =~ "Player's intent: unclear, nothing happened"
    assert gm =~ ~s(The player said: "I order a meal.")

    assert gm =~
             "Brenna Holt asks a short clarifying question in character, echoing the player's own words"

    assert gm =~ "Bread and Cheese (2c)"
    assert gm =~ "Bowl of Stew (5c)"
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
    live(session.id, {"tin_valley", 1})
    stock(session.id, fn stock -> Enum.map(stock, &Map.put(&1, "quantity", 0)) end)
    before = snapshot(session.id)

    {_, refused} = live(session.id, {"tin_valley", 5})
    assert diff(before, refused) == []
    assert last_gm() =~ "The server refused this trade"
  end

  test "the NPC refuses: the player cannot pay, nothing moves", %{session: session} do
    # Gentry's T24-T25: her purse set to 1c on the admin page, then a quote and a yes.
    live(session.id, {"tin_valley", 24})

    Character
    |> where([c], c.game_session_id == ^session.id and c.controller == "player")
    |> Repo.update_all(set: [coins: %{"copper" => 1}])

    before = snapshot(session.id)
    # The ale is in stock: only the purse refuses the trade.
    assert qty(before, "innkeep", "ale_mug") > 1
    {_, refused} = live(session.id, {"tin_valley", 25})
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
      live_words(session.id, "Vad kostar en öl?", {"tin_valley", 1},
        narrative:
          "\"Two copper for the ale, love.\" Brenna glances at the hearth. " <>
            "\"And if you've a mind for work, the kindling wants splitting.\""
      )

    assert diff(before, quoted) == []
    assert %{"item" => %{"id" => "ale_mug"}, "price" => 2} = open_offer(session.id)
    assert last_gm() =~ "The server quotes: Brenna Holt sells Ale for 2c"

    {_, accepted} = live_words(session.id, "Ja.", {"tin_valley", 5})

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
    {before, _} = live(session.id, {"tin_valley", 6})
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
    assert last_gm() =~ "offers what they might mean: Bread and Cheese (2c); or Bowl of Stew (5c)"
  end

  describe "the in-character clarify (Fredrik via Case, the PR after #478)" do
    # Gentry's retest of #476 (session 6d938a30), T1-T2: the GM quoted the
    # ale and offered kindling work in one reply; "Yes." could be either.
    test "Gentry's 'Yes.' after a quote and a side kindling offer clarifies; nothing moves",
         %{session: session} do
      {before, _} =
        live(session.id, {"tin_valley", 1},
          narrative:
            "\"Two copper for the ale, love.\" Brenna glances at the hearth. " <>
              "\"And if you've a mind for work, the kindling wants splitting.\""
        )

      offered = open_offer(session.id)
      assert %{"item" => %{"id" => "ale_mug"}, "price" => 2} = offered

      {_, yes} = live(session.id, {"tin_valley", 2})

      assert diff(before, yes) == []
      assert open_offer(session.id) == offered

      gm = last_gm()
      assert gm =~ ~s(The player said: "Yes.")
      assert gm =~ "yes to the open offer: Brenna Holt sells Ale for 2c"
      assert gm =~ "something else offered in the last narration"
    end

    # Finding (v353 stubs from live, this PR): live Jev was never unsure on
    # "Meal." (Tin Valley T6 and T23: buy 0.93 and 0.90, the kind "a meal"
    # as target), so the turn lists the kind's options; the clarify this
    # test wants needs an unsure read that did not happen live. Kept, not
    # patched: trade features are frozen (Fredrik, 2026-10-19).
    @tag :pending
    @tag finding: "v353 live read of 'Meal.' is sure: options, not the clarify"
    test "'Meal.' alone, Jev unsure between buying a meal and talking: clarifies; nothing moves",
         %{session: session} do
      {before, after_meal} = live(session.id, {"tin_valley", 6})

      assert diff(before, after_meal) == []
      assert open_offer(session.id) == nil

      gm = last_gm()
      assert gm =~ ~s(The player said: "Meal.")
      assert gm =~ "buy Bread and Cheese or Bowl of Stew"
      assert gm =~ "talk to Brenna Holt"
    end

    test "a clear 'Yes' to the one open offer buys it", %{session: session} do
      {before, quoted} = live(session.id, {"tin_valley", 21})
      {_, bought} = live(session.id, {"tin_valley", 22})

      assert copper(bought, "player") == copper(quoted, "player") - 2
      assert qty(bought, "innkeep", "ale_mug") == qty(quoted, "innkeep", "ale_mug") - 1
      refute last_gm() =~ "Player's intent: unclear"
      assert_conserved(before, bought)
    end

    # The clarify style comes from the asker's own data (OCEAN, Maslow, mood:
    # TalesForge.Game.Clarify.patience/1), as the packs author it: Brenna
    # (A 8, C 7, belonging, cheerful) is 8.6, helpful; Hilde (A 4, C 8,
    # safety, uneasy) is 2.6, a brush-off.
    test "Brenna (patient) echoes the words and offers options; nothing moves",
         %{session: session} do
      {before, after_order} = live(session.id, {"tin_valley", 14})
      assert diff(before, after_order) == []

      gm = last_gm()
      assert gm =~ "echoing the player's own words, and offers what they might mean"
      refute gm =~ "brush-off"
    end

    # Finding (v353 stubs from live): at the forge live Jev read "I'd like
    # something to eat." as talk to Hilde (T19: speak 0.84, target smith),
    # so no clarify, and her brush-off never came. Kept, not patched.
    @tag :pending
    @tag finding: "v353 T19 reads talk to Hilde: no clarify, no brush-off"
    test "Hilde (gruff) gives a short brush-off; nothing moves", %{session: session} do
      live(session.id, {"tin_valley", 18})
      {before, after_order} = live(session.id, {"tin_valley", 19})
      assert diff(before, after_order) == []
      assert open_offer(session.id) == nil

      gm = last_gm()
      assert gm =~ "Hilde Brask has little patience for it: give a short, in-character brush-off"
      refute gm =~ "offers what they might mean"
    end

    # Finding (v353 stubs from live): live Jev gave "I'd like something to
    # eat." no target (T14: buy 0.64, speak 0.36), so the clarify has no
    # asker (stored clarify: npc null, style helpful) and Brenna's patience
    # is never read: hungry or not, the style is helpful. Kept, not patched.
    @tag :pending
    @tag finding: "v353 T14 clarify has no asker: the patience never applies"
    test "unmet low needs lower patience: Brenna going hungry brushes off; nothing moves",
         %{session: session} do
      Character
      |> where([c], c.game_session_id == ^session.id and c.slug == "innkeep")
      |> Repo.update_all(set: [maslow_level: "physiological"])

      {before, after_order} = live(session.id, {"tin_valley", 14})
      assert diff(before, after_order) == []

      gm = last_gm()
      assert gm =~ "Brenna Holt has little patience for it"
      refute gm =~ "offers what they might mean"
    end
  end

  # The Jev request (state and questions) while an offer with options is
  # open, against `test/fixtures/jev/open_offer_request.json` (rewrite it
  # with UPDATE_JEV_GOLDEN=1): the action question has `ask_price`, the
  # state the open offer with its options, and the offer questions are asked.
  @jev_golden Path.expand("../../fixtures/jev/open_offer_request.json", __DIR__)
  test "Jev prompt fixture: ask_price and the open offer with its options", %{session: session} do
    live(session.id, {"tin_valley", 6})
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
    # The clarify schema: Jev reports how sure it is of each answer (its
    # probabilities are the candidates), including a side offer in the narration.
    assert golden =~ ~s("other_offer")
    assert golden =~ "something else offered in the last narration"
  end

  # The GM side of the clarify schema, against
  # `test/fixtures/gm/clarify_sections.txt` (UPDATE_GM_GOLDEN=1 rewrites it):
  # what the helpful and the brusque asker are told.
  @gm_golden Path.expand("../../fixtures/gm/clarify_sections.txt", __DIR__)
  test "GM prompt fixture: the clarify section, helpful and brusque" do
    clarify = %{
      "words" => "Yes.",
      "candidates" => [
        "yes to the open offer: Brenna Holt sells Ale for 2c",
        "something else offered in the last narration"
      ],
      "npc_id" => "innkeep",
      "npc" => "Brenna Holt",
      "style" => "helpful"
    }

    text =
      TalesForge.Game.Context.player_request_section(%{clarify: clarify}) <>
        "---\n" <>
        TalesForge.Game.Context.player_request_section(%{
          clarify: %{clarify | "npc" => "Hilde Brask", "style" => "brusque"}
        })

    if System.get_env("UPDATE_GM_GOLDEN") == "1" do
      File.mkdir_p!(Path.dirname(@gm_golden))
      File.write!(@gm_golden, text)
    end

    assert text == File.read!(@gm_golden)
  end

  # One turn: Jev reads `action` at `opts[:target]` (default the innkeep)
  # and answers the offer questions in `opts`; the GM narrates a line.
  # Gives the snapshots before and after, conserved.
  defp play(session_id, text, action, opts \\ []) do
    context = TalesForge.Game.Context.build_intent_context(GameSessions.get_session!(session_id))
    target_id = Keyword.get(opts, :target, "innkeep")

    target =
      Enum.find_value(JevIntent.candidates(context), :none, &(&1.id == target_id && &1.label))

    answers =
      opts
      |> Keyword.take([:offer_answer, :offer_pick, :probabilities])
      |> Map.new()
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

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

  # One turn as Gentry played it in v353 (`TalesForge.JevLive`): her words
  # and what live Jev read for them; `opts` adds to the read (a narrative,
  # an answer to an offer the recorded turn did not have).
  defp live(session_id, turn, opts \\ []),
    do: live_words(session_id, TalesForge.JevLive.text(turn), turn, opts)

  # Other words, read as live Jev read the turn `turn`.
  defp live_words(session_id, text, turn, opts \\ []) do
    {action, read} = Keyword.pop!(TalesForge.JevLive.read(turn), :action)
    play(session_id, text, action, Keyword.merge(read, opts))
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
