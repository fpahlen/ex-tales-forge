defmodule TalesForge.Game.PremiseFirstReplayTest do
  @moduledoc """
  Replay fixtures for turn pipeline PR 2, premise first (ex-tales-forge
  `docs/design-turn-pipeline.md` §8 and §9). With `TURN_PREMISE_FIRST=on` and
  `TURN_OUTCOME_RECORD=on`, the premise check runs before the mechanics and the
  NPCs. A claim that the state contradicts blocks the action. The blocked
  action books nothing and costs no game time (§11, decision 1).

  The fixtures are the same files as for PR 1
  (`test/fixtures/turn_replay/gentry_0caf.json` and `issue_180.json`). A turn
  or case with `expect_premise_first` uses it instead of `expect`. The tests
  assert the outcome record, the clock and the books, not the prose words.
  """
  use TalesForge.DataCase, async: false

  import Ecto.Query
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.Inventory
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.Repo
  alias TalesForge.Schemas.{AICall, GameSession, SessionEvent}

  @fixtures Path.expand("../../fixtures/turn_replay", __DIR__)
  @env ~w(TURN_OUTCOME_RECORD TURN_PREMISE_FIRST INN_WORLD WORLD_ANTAGONIST)

  setup do
    saved = Map.new(@env, &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)

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
    System.put_env("TURN_PREMISE_FIRST", "on")
    System.put_env("INN_WORLD", "on")
    System.put_env("WORLD_ANTAGONIST", "on")
    :ok
  end

  defp fixture(name), do: @fixtures |> Path.join(name) |> File.read!() |> Jason.decode!()

  defp session(adventure_id, start, location_id \\ nil) do
    {:ok, session} = GameSessions.create_session(%{name: "Replay", adventure_id: adventure_id})
    session = Repo.get!(GameSession, session.id)
    put_location = &if(location_id, do: Map.put(&1, "location_id", location_id), else: &1)

    character =
      session.world_state["character"]
      |> Map.put("coins", start["coins"])
      |> Map.put("inventory", start["inventory"])
      |> put_location.()

    world = session.world_state |> Map.put("character", character) |> put_location.()
    session |> GameSession.changeset(%{world_state: world}) |> Repo.update!()
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
    character = Repo.get!(GameSession, session_id).world_state["character"]

    {Inventory.coin_total_copper(character["coins"]),
     character["inventory"] |> Enum.map(&{&1["id"], &1["quantity"]}) |> Enum.sort()}
  end

  defp expected(step), do: step["expect_premise_first"] || step["expect"]

  defp assert_record(label, record, prompt, expect) do
    [action] = record["actions"]
    [want] = expect["actions"]

    assert action["type"] == want["type"], label
    assert action["status"] == want["status"], label

    if prefix = want["reason_prefix"],
      do: assert(String.starts_with?(action["reason"], prefix), label)

    assert record["coins"]["delta_copper"] == expect["delta_copper"], label
    assert record["items"]["gained"] == expect["gained"], label
    assert record["items"]["lost"] == expect["lost"], label
    assert record["location"]["from"] == record["location"]["to"], label

    if expect["clock_advances"] == false,
      do: assert(record["clock"]["tick_after"] == record["clock"]["tick_before"], label)

    if want["status"] == "rejected" do
      assert prompt =~ "Rejected: #{want["type"]}", label

      if want["reason_prefix"],
        do: assert(prompt =~ "## Player claims the state doesn't back", label)
    else
      assert prompt =~ "Accepted: #{want["type"]}", label
    end
  end

  describe "Gentry's session 0caf (11 turns), premise first" do
    test "the false claims of turns 5 and 6 are blocked; the books stay at the start" do
      fixture = fixture("gentry_0caf.json")
      session = session(fixture["adventure_id"], fixture["start"])
      start_books = books(session.id)

      for step <- fixture["turns"] do
        {record, prompt} = play(session.id, step)

        assert_record(
          "0caf turn #{step["turn"]}: #{step["text"]}",
          record,
          prompt,
          expected(step)
        )
      end

      assert books(session.id) == start_books
    end
  end

  describe "the #180 cases, premise first" do
    for case_id <- ~w(h-fp12 h-fp13 h-fp14 h-fp14-sell h-fa06 true-claim) do
      test "#{case_id}" do
        fixture = fixture("issue_180.json")
        step = Enum.find(fixture["cases"], &(&1["id"] == unquote(case_id)))
        session = session(fixture["adventure_id"], fixture["start"], step["location_id"])
        start_books = books(session.id)

        {record, prompt} = play(session.id, step)

        assert_record(unquote(case_id), record, prompt, expected(step))
        assert books(session.id) == start_books
      end
    end

    test "stage 2 runs before stage 3: the premise check step starts before the rules step" do
      fixture = fixture("issue_180.json")
      step = Enum.find(fixture["cases"], &(&1["id"] == "h-fp13"))
      session = session(fixture["adventure_id"], fixture["start"], step["location_id"])

      play(session.id, step)

      purposes =
        AICall
        |> where(
          [c],
          c.game_session_id == ^session.id and c.purpose in ["turn.premise_check", "turn.rules"]
        )
        |> order_by([c], asc: c.started_at)
        |> select([c], c.purpose)
        |> Repo.all()

      assert purposes == ["turn.premise_check", "turn.rules"]
    end
  end

  describe "TURN_PREMISE_FIRST off" do
    test "h-fp13 plays as before: the action is accepted and the GM gets the correction" do
      System.put_env("TURN_PREMISE_FIRST", "off")
      fixture = fixture("issue_180.json")
      step = Enum.find(fixture["cases"], &(&1["id"] == "h-fp13"))
      session = session(fixture["adventure_id"], fixture["start"], step["location_id"])

      {record, prompt} = play(session.id, step)

      assert [%{"status" => "accepted"}] = record["actions"]
      assert record["clock"]["tick_after"] == record["clock"]["tick_before"] + 1
      assert prompt =~ "## Player claims the state doesn't back"
    end
  end
end
