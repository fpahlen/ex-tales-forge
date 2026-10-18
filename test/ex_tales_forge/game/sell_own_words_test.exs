defmodule TalesForge.Game.SellOwnWordsTest do
  @moduledoc """
  Selling in the player's own words, through real turns with Jev and the LLM
  stubbed. Jev reads a sale with one target: the buyer ("to Brenna") or the
  item ("sell a mug of ale"). The item comes from the player's inventory, as
  a purchase's comes from the stock.

  Playtest v319 on 2026-10-18 (drift session 464229eb, turns 3 and 4):
  "I sell my mug of ale to Brenna for 2 copper" was a sale with no item,
  rejected with "Sell requires parameters.item_id.", and the mug stayed.
  """
  use TalesForge.DataCase, async: false

  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.{Context, JevIntent}
  alias TalesForge.GameSessions
  alias TalesForge.Jido

  doctest TalesForge.Game.Inventory, only: [sale: 3]

  setup do
    endpoints = Application.get_env(:jev, :endpoints)

    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
      Application.put_env(:jev, :endpoints, endpoints)
      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("TURN_APPLY_OUTCOMES")
    end)

    # As on playtest: a purchase of the item Jev targets (TurnApply.item_buy/3).
    System.put_env("TURN_APPLY_OUTCOMES", "on")

    Application.put_env(:jev, :endpoints,
      intent: [base_url: "https://api.typesafe.ai", api_key: "test-key", model: "jev-1.13.0"]
    )

    stub_llm(fn _kind, _user, _system -> :default end)

    {:ok, session} =
      GameSessions.create_session(%{name: "Sell", adventure_id: "tin_valley", intent_jev: "on"})

    start = coins(session)
    play(session, "I buy a mug of ale from Brenna.", :buy, %{"ale_mug" => 0.9})
    assert {ale(session), coins(session)} == {1, start - 2}

    %{session: session}
  end

  test "a sale to the person: the item is the one the words name", %{session: session} do
    before = coins(session)
    play(session, "I sell my mug of ale to Brenna.", :sell, %{"innkeep" => 0.9})

    assert ale(session) == 0
    assert coins(session) == before + 2
  end

  test "a sale of the item: the buyer is the person Jev ranks next", %{session: session} do
    before = coins(session)
    play(session, "I sell a mug of ale.", :sell, %{"ale_mug" => 0.8, "innkeep" => 0.15})

    assert ale(session) == 0
    assert coins(session) == before + 2
  end

  test "a sale of the item with nobody to buy it keeps the item", %{session: session} do
    before = coins(session)
    play(session, "I sell a mug of ale.", :sell, %{"ale_mug" => 0.9})

    assert ale(session) == 1
    assert coins(session) == before
  end

  test "without Jev, the sale pays the item's value too", %{session: session} do
    row = TalesForge.Repo.get!(TalesForge.Schemas.GameSession, session.id)

    row
    |> Ecto.Changeset.change(world_state: Map.delete(row.world_state, "intent_jev"))
    |> TalesForge.Repo.update!()

    before = coins(session)
    Req.Test.stub(Jev.HTTP, fn _conn -> flunk("Jev called") end)

    assert {:ok, %{status: :processing}} =
             GameSessions.submit_message(session.id, "I sell my mug of ale to Brenna.")

    assert ale(session) == 0
    assert coins(session) == before + 2
  end

  # One turn: Jev reads `action` with the `ranking` of target ids.
  defp play(session, text, action, ranking) do
    context = Context.build_intent_context(GameSessions.get_session!(session.id))
    labels = Map.new(JevIntent.candidates(context), &{&1.id, &1.label})
    probs = Map.new(ranking, fn {id, p} -> {Map.fetch!(labels, id), p} end)
    {top, _p} = Enum.max_by(probs, &elem(&1, 1))

    reply = %{
      action: action,
      target: top,
      skill: :none,
      later: :none,
      safety: :benign,
      confidence: %{action: 0.95, target: 0.95, safety: 0.99},
      probabilities: %{action: %{action => 1.0}, target: probs}
    }

    Req.Test.stub(Jev.HTTP, &Jev.Test.respond(&1, reply))
    assert {:ok, %{status: :processing}} = GameSessions.submit_message(session.id, text)
  end

  defp sheet(session), do: GameSessions.get_session!(session.id).world_state["character"]

  defp coins(session), do: TalesForge.Game.Inventory.coin_total_copper(sheet(session)["coins"])

  defp ale(session) do
    Enum.find_value(sheet(session)["inventory"], 0, &(&1["id"] == "ale_mug" && &1["quantity"]))
  end
end
