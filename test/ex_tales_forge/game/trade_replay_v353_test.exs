defmodule TalesForge.Game.TradeReplayV353Test do
  @moduledoc """
  Replays Gentry's v353 playtest (Tin Valley 169f4dcb, Crossroads f9467718,
  2026-10-19) through `GameSessions.submit_message/3`: her words, the Jev
  intent read stored for each turn (`test/fixtures/replay/gentry_v353.json`)
  and the GM reply stored for each turn. After every turn, the coins and the
  goods of the player and the NPCs are conserved (Fredrik's trade rules).
  """
  use TalesForge.DataCase, async: false

  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Admin
  alias TalesForge.Game.{Inventory, JevIntent}
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.Character

  @servings ~w(ale_mug stew_bowl bread_cheese)
  @prices %{"ale_mug" => 2, "stew_bowl" => 5, "bread_cheese" => 2}
  @fixture "test/fixtures/replay/gentry_v353.json" |> File.read!() |> Jason.decode!()

  setup do
    flags = ~w(INN_WORLD WORLD_ANTAGONIST COMBAT_OPPOSED NPC_REACTIONS TURN_APPLY_OUTCOMES)
    previous = Map.new(flags, &{&1, System.get_env(&1)})
    Enum.each(flags, &System.put_env(&1, "on"))
    endpoints = Application.get_env(:jev, :endpoints)
    key = Application.get_env(:jev, :api_key)
    Application.put_env(:jev, :api_key, "test-key")

    Application.put_env(:jev, :endpoints,
      intent: [base_url: "https://api.typesafe.ai", api_key: "test-key", model: "jev-1.13.0"]
    )

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)

      Application.put_env(:jev, :endpoints, endpoints)
      Application.put_env(:jev, :api_key, key)
      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("XAI_API_KEY")
    end)

    :ok
  end

  for %{"adventure_id" => adventure} = recorded <- @fixture["sessions"] do
    @recorded recorded
    test "#{adventure}: every turn conserves coins and goods" do
      {:ok, session} =
        GameSessions.create_session(%{
          name: "Replay v353",
          adventure_id: @recorded["adventure_id"],
          intent_jev: "on"
        })

      {:ok, _} = GameSessions.ensure_scene(session.id)
      start = snapshot(session.id)

      Enum.reduce(@recorded["turns"], start, fn turn, before ->
        maybe_admin_edit(session.id, @recorded["adventure_id"], turn["turn"])
        before = if turn["turn"] == 24, do: snapshot(session.id), else: before
        now = play(session.id, turn)

        assert_conserved(
          before,
          now,
          "turn #{turn["turn"]} #{inspect(turn["text"])} (#{ledger(now)})"
        )

        now
      end)
    end
  end

  # Gentry's admin edit before Tin Valley turn 24: the player's coins to 1c.
  defp maybe_admin_edit(session_id, "tin_valley", 24) do
    session = GameSessions.get_session!(session_id)
    world = put_in(session.world_state, ["character", "coins"], %{"copper" => 1})
    {:ok, _} = Admin.update_session_world_state(session, Jason.encode!(world))
  end

  defp maybe_admin_edit(_session_id, _adventure, _turn), do: :ok

  defp play(session_id, %{"text" => text, "jev" => jev, "gm" => gm}) do
    context = TalesForge.Game.Context.build_intent_context(GameSessions.get_session!(session_id))
    labels = Map.new(JevIntent.candidates(context), &{&1.id, &1.label})
    target = Map.get(labels, jev["target"], :none)
    action = String.to_existing_atom(jev["action"])
    raw = jev["raw_confidence"]
    probs = Map.new(jev["probabilities"], fn {k, v} -> {String.to_existing_atom(k), v} end)

    Req.Test.stub(Jev.HTTP, fn conn ->
      {request, conn} = Jev.Test.request(conn)
      questions = request["questions"] || %{}

      reply =
        if Map.has_key?(questions, "action"),
          do:
            intent_reply(questions, jev, %{action: action, target: target, raw: raw, probs: probs}),
          else: %{emotion: :calm, intensity: 0.33, stance: 0.75}

      Jev.Test.respond(conn, reply)
    end)

    stub_llm(fn
      :gm, _user, _system -> gm
      _kind, _user, _system -> :default
    end)

    {:ok, _} = GameSessions.submit_message(session_id, text)
    {:ok, _} = GameSessions.ensure_scene(session_id)
    snapshot(session_id)
  end

  defp intent_reply(questions, jev, %{action: action, target: target, raw: raw, probs: probs}) do
    base = %{
      action: action,
      target: target,
      skill: :none,
      later: :none,
      safety: :benign,
      confidence: %{action: raw, target: raw, safety: 0.99},
      probabilities: %{action: probs}
    }

    if Map.has_key?(questions, "offer_answer"),
      do: offer_reply(base, questions, jev),
      else: base
  end

  # Jev's answer to the open offer, as the turn stored it.
  defp offer_reply(base, questions, jev) do
    base
    |> Map.put(:offer_answer, String.to_existing_atom(jev["offer_answer"] || "other"))
    |> put_offer_probabilities(jev["offer_probabilities"])
    |> put_pick(Map.has_key?(questions, "offer_pick"))
  end

  defp put_offer_probabilities(reply, nil), do: reply

  defp put_offer_probabilities(reply, probs),
    do:
      put_in(
        reply,
        [:probabilities, :offer_answer],
        Map.new(probs, fn {k, v} -> {String.to_existing_atom(k), v} end)
      )

  defp put_pick(reply, true), do: Map.put(reply, :offer_pick, :none)
  defp put_pick(reply, false), do: reply

  # Every character's copper and goods (by item id).
  defp snapshot(session_id) do
    Character
    |> where([c], c.game_session_id == ^session_id)
    |> Repo.all()
    |> Map.new(fn c ->
      slug = if c.controller in ~w(player bot), do: "player", else: c.slug

      items =
        Enum.reduce(c.inventory || [], %{}, fn i, acc ->
          Map.update(acc, i.id, i.quantity || 1, &(&1 + (i.quantity || 1)))
        end)

      {slug, {Inventory.coin_total_copper(c.coins || %{}), items}}
    end)
  end

  # Coins never appear or vanish, and goods only change hands. The one
  # exception is a serving (ale, stew): it is eaten or drunk where it is
  # bought, so it leaves the seller's stock, and its price is exactly the
  # copper the seller got for it this turn.
  defp assert_conserved(before, now, label) do
    assert copper(before) == copper(now),
           "#{label}: coins created or destroyed #{inspect(diff(before, now))}"

    gone =
      for {id, n} <- items(before),
          n - Map.get(items(now), id, 0) != 0,
          into: %{},
          do: {id, n - Map.get(items(now), id, 0)}

    servings = Map.filter(gone, fn {id, n} -> n > 0 and id in @servings end)

    assert gone == servings,
           "#{label}: goods created or destroyed #{inspect(gone)} #{inspect(diff(before, now))}"

    paid = Enum.sum(for {id, n} <- servings, do: n * Map.fetch!(@prices, id))

    assert paid == seller_gain(before, now),
           "#{label}: servings #{inspect(servings)} worth #{paid}c, sellers got #{seller_gain(before, now)}c #{inspect(diff(before, now))}"
  end

  defp copper(snap), do: snap |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.sum()

  defp items(snap),
    do:
      snap
      |> Map.values()
      |> Enum.map(&elem(&1, 1))
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _k, a, b -> a + b end))

  defp seller_gain(before, now),
    do:
      Enum.sum(
        for {who, {c, _}} <- now,
            who != "player",
            do: max(c - elem(Map.get(before, who, {c, %{}}), 0), 0)
      )

  defp ledger(snap) do
    snap
    |> Enum.filter(fn {who, _} -> who in ~w(player innkeep marta_kellen) end)
    |> Enum.map_join(" ", fn {who, {c, items}} -> "#{who}=#{c}c #{inspect(items)}" end)
  end

  defp diff(a, b), do: for({k, v} <- b, a[k] != v, do: {k, a[k], v})
end
