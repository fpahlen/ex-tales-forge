defmodule TalesForge.Game.TradeRetest470Test do
  @moduledoc """
  Gentry's QA retest of #470 (playtest session
  8a9dbde9-5971-47eb-b4a6-d0d852869014, 2026-10-18, NO-GO), replayed turn
  by turn through `GameSessions.submit_message/3`, the play page's entry
  point, with INTENT_JEV on. Jev and the GM reply what that session got
  (its `ai_calls` `turn.intent` meta and its `gm_reasoning` events).

  Fredrik's rules: coins and items only change place; a trade happens only
  when both accept, else nothing moves.
  """
  use TalesForge.DataCase, async: false

  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.{Inventory, JevIntent}
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas
  # {player text, Jev action, Jev target id, GM narrative (shortened)}, and
  # T4, the accept of T3's quote (PR B, docs/design-trade-offers.md), which
  # the playtest did not have: Jev also answers the open offer. T3 and T4
  # are read as live Jev read the same turns in Gentry's v353 playtest
  # (`TalesForge.JevLive`: Tin Valley T1, the price question, and T5, the
  # "Yes." that bought), since session 8a9dbde9 predates `ask_price`.
  @script [
    {"I look around the common room.", :observe, nil, "Brenna smiles."},
    {"Brenna Holt, what work is there around here?", :speak, "innkeep", "Plenty of work."},
    {"How much for a mug of ale, Brenna?", {:live, {"tin_valley", 1}},
     "You slide two copper across the counter."},
    {"Yes, one please.", {:live, {"tin_valley", 5}}, "She draws a mug."},
    {"I buy a loaf of bread and pay her.", :buy, "innkeep", "The loaves are all gone."},
    {"I sell my travel cloak to Brenna Holt.", :sell, "innkeep", "I don't trade in gear."},
    {"Brenna, how much did you give me for the cloak?", :speak, "innkeep", "Not a copper."},
    {"I buy a mug of ale from Brenna and pay her.", :buy, "innkeep", "She draws a mug."},
    {"I sell the mug of ale back to Brenna Holt.", :sell, "innkeep", "Can't take it back."},
    {"I buy the mug itself from Brenna.", :buy, "innkeep", "That's for the ale, love."},
    {"I walk to the smithy to see Hilde Brask.", :move, "smithy", "You reach the forge."},
    {"I sell my hunting knife to Hilde Brask.", :sell, "smith", "Hilde weighs the knife."}
  ]

  setup do
    # Playtest's flags (fly.playtest.toml and its secrets): INN_WORLD,
    # INTENT_JEV and TURN_APPLY_OUTCOMES on.
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
        name: "QaRetest470",
        adventure_id: "tin_valley",
        intent_jev: "on"
      })

    {:ok, session: session}
  end

  test "Gentry's 11 turns and an accept: coins and items conserve, asking and refusals move nothing, the knife sells",
       %{session: session} do
    start = snapshot(session.id)
    assert copper(start, "innkeep") == 1000
    assert qty(start, "innkeep", "ale_mug") == 72

    log =
      @script
      |> Enum.with_index(1)
      |> Map.new(fn {turn, n} ->
        before = snapshot(session.id)
        play(session.id, turn)
        {n, {before, snapshot(session.id)}}
      end)

    moved = fn n -> diff(elem(log[n], 0), elem(log[n], 1)) end
    {b4, a4} = log[4]
    {b8, a8} = log[8]
    {b12, a12} = log[12]

    failures =
      Enum.reject(
        [
          for(
            n <- 1..12,
            totals(elem(log[n], 0)) != totals(elem(log[n], 1)),
            do: "T#{n} coins/items not conserved: #{inspect(moved.(n))}"
          ),
          moved.(3) != [] && "T3 a price question moved: #{inspect(moved.(3))}",
          {copper(a4, "innkeep"), qty(a4, "innkeep", "ale_mug")} !=
            {copper(b4, "innkeep") + 2, qty(b4, "innkeep", "ale_mug") - 1} &&
            "T4 the accepted quote: Brenna not paid or cask not served: #{inspect(moved.(4))}",
          moved.(10) != [] &&
            "T10 the mug is refused, yet the turn moved: #{inspect(moved.(10))}",
          {copper(a8, "innkeep"), qty(a8, "innkeep", "ale_mug")} !=
            {copper(b8, "innkeep") + 2, qty(b8, "innkeep", "ale_mug") - 1} &&
            "T8 Brenna not paid or cask not served: #{inspect(moved.(8))}",
          {qty(a12, "player", "hunting_knife"), qty(a12, "smith", "hunting_knife"),
           copper(a12, "player")} !=
            {0, qty(b12, "smith", "hunting_knife") + 1, copper(b12, "player") + 15} &&
            "T12 the knife sale to Hilde did not happen: #{inspect(moved.(12))}"
        ]
        |> List.flatten(),
        &(&1 == false)
      )

    assert failures == []
  end

  defp play(session_id, {text, {:live, turn}, narrative}) do
    {action, read} = Keyword.pop!(TalesForge.JevLive.read(turn), :action)
    {target_id, answers} = Keyword.pop!(read, :target)
    play(session_id, {text, action, target_id, narrative, answers})
  end

  defp play(session_id, {text, action, target_id, narrative}),
    do: play(session_id, {text, action, target_id, narrative, []})

  defp play(session_id, {text, action, target_id, narrative, answers}) do
    context = TalesForge.Game.Context.build_intent_context(GameSessions.get_session!(session_id))
    candidates = JevIntent.candidates(context)
    target = Enum.find_value(candidates, :none, &(&1.id == target_id && &1.label))

    Req.Test.stub(Jev.HTTP, fn conn ->
      {_request, conn} = Jev.Test.request(conn)

      Jev.Test.respond(
        conn,
        Map.merge(
          %{
            action: action,
            target: target,
            skill: :none,
            later: :none,
            safety: :benign,
            confidence: %{action: 0.95, target: 0.95, safety: 0.99}
          },
          Map.new(answers)
        )
      )
    end)

    stub_llm(fn
      :gm, _user, _system ->
        %{"narrative" => narrative, "context_summary" => "", "npc_memory_updates" => []}

      _kind, _user, _system ->
        :default
    end)

    assert {:ok, %{status: :processing}} = GameSessions.submit_message(session_id, text)
    # The play page asks for the scene after a walk.
    {:ok, _} = GameSessions.ensure_scene(session_id)
  end

  # The player's and every NPC's coins (copper) and items, as their rows hold them.
  defp snapshot(session_id) do
    Schemas.GameCharacter
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

  # Coins and items over everyone. A serving (Brenna's ale) is drunk where
  # it is bought, so it leaves her cask and nobody carries it: it is
  # counted by the cask checks of T4 and T8, not here.
  defp totals(snap) do
    snap
    |> Map.values()
    |> Enum.reduce({0, %{}}, fn {c, items}, {sum, all} ->
      {sum + c, Map.merge(all, Map.delete(items, "ale_mug"), fn _k, a, b -> a + b end)}
    end)
  end

  defp diff(a, b), do: for({k, v} <- b, a[k] != v, do: {k, a[k], v})
  defp copper(snap, who), do: elem(snap[who], 0)
  defp qty(snap, who, id), do: Map.get(elem(snap[who], 1), id, 0)
end
