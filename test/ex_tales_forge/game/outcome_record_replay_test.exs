defmodule TalesForge.Game.OutcomeRecordReplayTest do
  @moduledoc """
  Replay fixtures for the outcome record (turn pipeline PR 1, ex-tales-forge
  `docs/design-turn-pipeline.md` §8 and §9). Each fixture plays stored turns
  with `TURN_OUTCOME_RECORD=on` and asserts the outcome record and the books,
  not the prose words:

    * `test/fixtures/turn_replay/gentry_0caf.json`: Gentry's session 0caf18f5,
      11 turns in one session.
    * `test/fixtures/turn_replay/issue_180.json`: the #180 cases h-fp12,
      h-fp13, h-fp14 and h-fa06, plus h-fp14 played as a sell.

  A test also checks that the flag off keeps the GM prompt as before.
  """
  use TalesForge.DataCase, async: false

  import Ecto.Query
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, SessionEvent}

  @fixtures Path.expand("../../fixtures/turn_replay", __DIR__)
  @heading "## Outcome record (booked by the server)"
  @env ~w(TURN_OUTCOME_RECORD INN_WORLD WORLD_ANTAGONIST)

  setup do
    saved = Map.new(@env, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("XAI_API_KEY")
    end)

    test_pid = self()

    stub_llm(fn
      :gm, user, _system ->
        send(test_pid, {:gm_prompt, user})
        %{"narrative" => "The table waits.", "gm_notes" => "n"}

      _kind, _user, _system ->
        :default
    end)

    System.put_env("TURN_OUTCOME_RECORD", "on")
    :ok
  end

  defp fixture(name), do: @fixtures |> Path.join(name) |> File.read!() |> Jason.decode!()

  defp session(adventure_id, start, location_id \\ nil) do
    {:ok, session} = GameSessions.create_session(%{name: "Replay", adventure_id: adventure_id})
    session = GameSessions.get_session!(session.id)

    character =
      session.world_state["character"]
      |> Map.put("coins", start["coins"])
      |> Map.put("inventory", start["inventory"])
      |> then(&if(location_id, do: Map.put(&1, "location_id", location_id), else: &1))

    world =
      session.world_state
      |> Map.put("character", character)
      |> then(&if(location_id, do: Map.put(&1, "location_id", location_id), else: &1))

    session |> GameSession.changeset(%{world_state: world}) |> save_session!()
  end

  defp play(session_id, step) do
    before = outcome_events(session_id)
    assert {:ok, _payload} = TurnProcessor.run(session_id, {step["text"], step["player_action"]})
    assert_received {:gm_prompt, prompt}

    [record] = outcome_events(session_id) -- before
    {record, prompt}
  end

  defp outcome_events(session_id) do
    SessionEvent
    |> where([e], e.game_session_id == ^session_id and e.kind == "turn.outcome")
    |> select([e], e.payload)
    |> Repo.all()
  end

  defp books(session_id) do
    character = GameSessions.get_session!(session_id).world_state["character"]

    {TalesForge.Game.Inventory.coin_total_copper(character["coins"]),
     character["inventory"] |> Enum.map(&{&1["id"], &1["quantity"]}) |> Enum.sort()}
  end

  defp assert_record(label, record, prompt, expect) do
    [action] = record["actions"]
    [want] = expect["actions"]

    assert action["type"] == want["type"], label
    assert action["status"] == want["status"], label
    if want["reason"], do: assert(action["reason"] == want["reason"], label)
    assert record["coins"]["delta_copper"] == expect["delta_copper"], label
    assert record["items"]["gained"] == expect["gained"], label
    assert record["items"]["lost"] == expect["lost"], label
    assert record["location"]["from"] == record["location"]["to"], label
    assert prompt =~ @heading, label

    if want["status"] == "rejected",
      do: assert(prompt =~ "Rejected: #{want["type"]}", label),
      else: assert(prompt =~ "Accepted: #{want["type"]}", label)
  end

  describe "Gentry's session 0caf (11 turns)" do
    test "each turn books what the record says, and the books stay in step" do
      fixture = fixture("gentry_0caf.json")
      session = session(fixture["adventure_id"], fixture["start"])
      start_books = books(session.id)

      for step <- fixture["turns"] do
        {copper_before, _items} = books(session.id)
        {record, prompt} = play(session.id, step)
        label = "0caf turn #{step["turn"]}: #{step["text"]}"

        assert_record(label, record, prompt, step["expect"])
        assert record["coins"]["before_copper"] == copper_before, label
        {copper_after, _items} = books(session.id)
        assert record["coins"]["after_copper"] == copper_after, label
      end

      # No turn of the session books coins or items: the claims, the fake GM
      # notes and the rejected purchase and payment change nothing.
      assert books(session.id) == start_books
    end
  end

  describe "the #180 cases" do
    for case_id <- ~w(h-fp12 h-fp13 h-fp14 h-fp14-sell h-fa06) do
      test "#{case_id} books nothing and the record says so" do
        fixture = fixture("issue_180.json")
        step = Enum.find(fixture["cases"], &(&1["id"] == unquote(case_id)))
        System.put_env("INN_WORLD", "on")
        System.put_env("WORLD_ANTAGONIST", "on")
        session = session(fixture["adventure_id"], fixture["start"], step["location_id"])
        start_books = books(session.id)

        {record, prompt} = play(session.id, step)

        assert_record(unquote(case_id), record, prompt, step["expect"])
        assert books(session.id) == start_books
      end
    end

    test "h-fp14-sell: the rejected sale reaches the GM with its reason" do
      fixture = fixture("issue_180.json")
      step = Enum.find(fixture["cases"], &(&1["id"] == "h-fp14-sell"))
      System.put_env("INN_WORLD", "on")
      session = session(fixture["adventure_id"], fixture["start"], step["location_id"])

      {_record, prompt} = play(session.id, step)

      assert prompt =~
               "Rejected: sell (smith). Reason: Cannot sell 'enchanted_armor' — not in inventory."

      assert prompt =~ "Coins: no change (500 copper in total)."
    end
  end

  describe "TURN_OUTCOME_RECORD off" do
    test "the GM prompt has no outcome record and the turn has no turn.outcome event" do
      System.put_env("TURN_OUTCOME_RECORD", "off")
      fixture = fixture("issue_180.json")
      step = Enum.find(fixture["cases"], &(&1["id"] == "h-fp14-sell"))
      session = session(fixture["adventure_id"], fixture["start"])

      assert {:ok, _} = TurnProcessor.run(session.id, {step["text"], step["player_action"]})
      assert_received {:gm_prompt, prompt}
      refute prompt =~ @heading

      refute Repo.exists?(
               from(e in SessionEvent,
                 where: e.game_session_id == ^session.id and e.kind == "turn.outcome"
               )
             )
    end
  end
end
