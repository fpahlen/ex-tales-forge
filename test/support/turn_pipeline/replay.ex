defmodule TalesForge.TurnPipeline.Replay do
  @moduledoc """
  The replay harness for the turn pipeline fixtures
  (`test/fixtures/turn_pipeline/README.md`, "Harness spec").

  `run/1` builds a session from the fixture context, plays each turn through
  `TalesForge.Game.TurnProcessor` with the mock GM, and compares the outcome
  record, the books and the GM prompt with `expect`. Call it from a test
  process that owns a database sandbox.

  Limits of this version:

    * The intent step is not run. The harness plays the first action of
      `expect.intent.actions` (a stub that returns `expect.intent`, spec
      item 3). The `intent` keys are therefore not checked.
    * Dice are not scripted yet. A fixture with `dice` fails.
    * The post-check runs only when `TalesForge.Game.ProseCheck` exists
      (turn pipeline PR 3). Before that, `post_check` and `mismatch_kinds`
      are not checked.
    * `TURN_OUTCOME_RECORD` is always on, because the harness reads the
      outcome record. The other flags follow `pending_on` (spec item 9).
    * `coins_after` compares the coin total in copper, not the split into
      copper, silver and gold.
    * A key that the harness does not support fails the fixture, so that a
      fixture never passes without its checks.
  """

  import ExUnit.Assertions, only: [assert_received: 1]
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.Inventory
  alias TalesForge.Game.OutcomeRecord
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.Game.WorldClock
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, NpcInstance, SessionEvent}

  import Ecto.Query

  @worlds %{"1e9114ed" => "tin_valley", "8eab5ea0" => "crossroads_ledger"}

  @flags %{
    "outcome_record" => "TURN_OUTCOME_RECORD",
    "premise_first" => "TURN_PREMISE_FIRST",
    "state_from_mechanics" => "TURN_STATE_FROM_MECHANICS"
  }

  # TURN_OUTCOME_RECORD is always on: the record is what the harness reads.
  @base_env %{"INN_WORLD" => "on", "WORLD_ANTAGONIST" => "on", "TURN_OUTCOME_RECORD" => "on"}

  @default_prose "The table waits."

  @supported ~w(intent premise outcome post_check mismatch_kinds fixture_fails gm_prompt
                coins_after)

  @prose_check TalesForge.Game.ProseCheck

  @doc "Plays the fixture. Returns `:ok` or `{:error, failures}`."
  @spec run(map()) :: :ok | {:error, [String.t()]}
  def run(item) do
    env = env_for(item)
    saved = Map.new(env, fn {key, _} -> {key, System.get_env(key)} end)
    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)

    try do
      session = session(item["context"])

      failures =
        item["turns"]
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {turn, n} ->
          turn |> play(session.id, item["context"]) |> Enum.map(&"turn #{n}: #{&1}")
        end)

      if failures == [], do: :ok, else: {:error, failures}
    after
      Enum.each(saved, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp env_for(item) do
    item["pending_on"]
    |> Enum.flat_map(fn key -> List.wrap(@flags[key]) end)
    |> Map.new(&{&1, "on"})
    |> Map.merge(@base_env)
  end

  # --- the session -------------------------------------------------------------

  defp session(context) do
    adventure = Map.fetch!(@worlds, context["world"])
    {:ok, session} = GameSessions.create_session(%{name: "Replay", adventure_id: adventure})
    session = Repo.get!(GameSession, session.id)
    location = context["location_id"]

    character =
      session.world_state["character"]
      |> Map.put("coins", context["coins"])
      |> Map.put("inventory", context["inventory"])
      |> Map.put("location_id", location)
      |> put_skills(context["skills"])

    tick = div(context["clock_minute"] || 0, WorldClock.minutes_per_tick())

    world =
      session.world_state
      |> Map.put("character", character)
      |> Map.put("location_id", location)
      |> Map.put("world_tick", tick)
      |> Map.put("world_clock", WorldClock.format(tick))

    session = session |> GameSession.changeset(%{world_state: world}) |> Repo.update!()
    put_stock(session.id, context["stock"] || %{})
    session
  end

  defp put_skills(character, nil), do: character
  defp put_skills(character, skills), do: Map.put(character, "skills", skills)

  defp put_stock(session_id, stock) do
    Enum.each(stock, fn {npc_id, items} ->
      case NPC.get_instance(session_id, npc_id) do
        %NpcInstance{} = inst ->
          inst
          |> Ecto.Changeset.change(runtime_state: Map.put(inst.runtime_state, "stock", items))
          |> Repo.update!()

        nil ->
          :ok
      end
    end)
  end

  # --- one turn ----------------------------------------------------------------

  defp play(turn, session_id, context) do
    expect = turn["expect"]

    case unsupported(turn) do
      [] ->
        prose = turn["gm_mock_prose"] || @default_prose
        stub_gm(prose)
        before = Repo.get!(GameSession, session_id).world_state
        events_before = events(session_id)
        action = player_action(turn["text"], expect, context)
        {:ok, _payload} = TurnProcessor.run(session_id, turn["text"], action)
        assert_received {:replay_gm_prompt, prompt}
        after_turn = Repo.get!(GameSession, session_id).world_state
        new_events = events(session_id) -- events_before

        check(expect, %{
          before: before,
          after: after_turn,
          events: new_events,
          prompt: prompt,
          prose: prose
        })

      keys ->
        ["unsupported keys #{inspect(keys)}"]
    end
  end

  defp unsupported(turn) do
    expect = turn["expect"]
    keys = Map.keys(expect) -- @supported
    keys = if Map.has_key?(turn, "dice"), do: ["dice" | keys], else: keys
    if Map.has_key?(expect, "npc"), do: Enum.uniq(["npc" | keys]), else: keys
  end

  defp stub_gm(prose) do
    test_pid = self()

    stub_llm(fn
      :gm, user, _system ->
        send(test_pid, {:replay_gm_prompt, user})
        %{"narrative" => prose, "gm_notes" => "n"}

      _kind, _user, _system ->
        :default
    end)
  end

  defp events(session_id) do
    SessionEvent
    |> where([e], e.game_session_id == ^session_id)
    |> select([e], %{kind: e.kind, payload: e.payload})
    |> Repo.all()
  end

  # The stub intent: the first expected action, with an item id for a buy.
  defp player_action(text, expect, context) do
    first = expect |> get_in(["intent", "actions"]) |> List.first() || %{"action" => "other"}

    %{
      "overall_intent" => text,
      "action" => %{
        "action_type" => first["action"],
        "target" => first["target"],
        "parameters" => params(first["action"], text, first["target"], context)
      },
      "deferred_actions" => [],
      "confidence" => 0.9
    }
  end

  defp params("buy", text, target, context), do: %{"item_id" => item_id(text, target, context)}
  defp params(_action, _text, _target, _context), do: %{}

  # A stock item named in the text, else the words after "buy a/an/the".
  defp item_id(text, target, context) do
    down = String.downcase(text)
    stock = get_in(context, ["stock", target || ""]) || []

    case Enum.find(stock, &String.contains?(down, String.downcase(&1["name"]))) do
      %{"id" => id} ->
        id

      nil ->
        case Regex.run(~r/buy (?:a |an |the |some )?([a-z' -]+?)(?: from |\.|$)/, down) do
          [_, words] -> words |> String.trim() |> String.replace(~r/\s+/, "_")
          _ -> "unknown"
        end
    end
  end

  # --- checks ------------------------------------------------------------------

  defp check(expect, turn) do
    record = turn.events |> Enum.find(&(&1.kind == "turn.outcome")) |> then(&(&1 && &1.payload))

    if record do
      outcome_checks(expect["outcome"] || %{}, record, turn) ++
        premise_checks(expect["premise"], turn) ++
        prompt_checks(expect["gm_prompt"], turn) ++
        coins_after_checks(expect["coins_after"], turn) ++
        post_checks(expect, record, turn)
    else
      ["no turn.outcome event (is TURN_OUTCOME_RECORD on?)"]
    end
  end

  defp outcome_checks(outcome, record, turn) do
    actions = record["actions"]
    accepted = for %{"status" => "accepted", "type" => t} <- actions, do: t

    rejected =
      for %{"status" => "rejected"} = a <- actions,
          do: %{"action" => a["type"], "reason" => a["code"]}

    delta = record["coins"]["delta_copper"]
    gained = Enum.map(record["items"]["gained"], & &1["id"])
    lost = Enum.map(record["items"]["lost"], & &1["id"])

    [
      same(:accepted, outcome["accepted"], accepted),
      same(:rejected, outcome["rejected"], rejected),
      coins(outcome["coins_delta_copper"], delta),
      same(:items_added, outcome["items_added"], gained),
      same(:items_removed, outcome["items_removed"], lost),
      clock(outcome["clock"], record["clock"]),
      location(outcome["location_id"], record["location"]["to"]),
      same(:skill_changes, outcome["skill_changes"], skill_changes(turn.before, turn.after))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp same(_key, nil, _actual), do: nil
  defp same(_key, want, want), do: nil
  defp same(key, want, actual), do: "#{key}: want #{inspect(want)}, got #{inspect(actual)}"

  defp coins(nil, _delta), do: nil
  defp coins("any", _delta), do: nil
  defp coins(want, delta) when is_integer(want), do: same(:coins_delta_copper, want, delta)
  defp coins(">0", delta) when delta > 0, do: nil
  defp coins(">=0", delta) when delta >= 0, do: nil
  defp coins(want, delta), do: "coins_delta_copper: want #{want}, got #{delta}"

  defp clock(nil, _clock), do: nil
  defp clock("unspecified", _clock), do: nil
  defp clock("none", %{"tick_before" => t, "tick_after" => t}), do: nil
  defp clock("advances", %{"tick_before" => a, "tick_after" => b}) when b > a, do: nil
  defp clock(want, clock), do: "clock: want #{want}, got #{inspect(clock)}"

  defp location(want, _actual) when want in [nil, "any"], do: nil
  defp location(want, actual), do: same(:location_id, want, actual)

  defp skill_changes(before, after_turn) do
    old = get_in(before, ["character", "skills"]) || %{}
    new = get_in(after_turn, ["character", "skills"]) || %{}

    for {skill, level} <- new, level != Map.get(old, skill, 0), into: %{} do
      {skill, level - Map.get(old, skill, 0)}
    end
  end

  defp premise_checks(nil, _turn), do: []

  defp premise_checks(%{"rejected_claims" => want}, turn) do
    got =
      for %{kind: "player.false_premise", payload: %{"claims" => claims}} <- turn.events,
          claim <- claims,
          do: claim_code(claim)

    [same(:rejected_claims, Enum.sort(want), Enum.sort(Enum.uniq(got)))] |> Enum.reject(&is_nil/1)
  end

  @claim_kinds %{
    "purchase" => "past_purchase",
    "item" => "owns",
    "wearing" => "wearing",
    "kill" => "kill",
    "coins" => "coins"
  }

  defp claim_code(%{"kind" => kind, "claim" => claim}) do
    slug =
      claim
      |> String.downcase()
      |> String.replace(~r/^(the|a|an|my)\s+/, "")
      |> String.replace(~r/\W+/, "_")

    "#{Map.get(@claim_kinds, kind, kind)}:#{slug}"
  end

  defp prompt_checks(nil, _turn), do: []

  defp prompt_checks(gm_prompt, turn) do
    Enum.flat_map(gm_prompt, fn
      {"rejection_phrasing", "fixed_template"} ->
        if String.contains?(turn.prompt, OutcomeRecord.rejection_template()),
          do: [],
          else: ["gm_prompt: the fixed rejection template is missing"]

      {key, _value} ->
        ["gm_prompt: unsupported key #{key}"]
    end)
  end

  defp coins_after_checks(nil, _turn), do: []

  # The coin total in copper. The server makes change when it books a
  # payment (`Inventory.deduct_coins/2`), so the split into copper, silver
  # and gold can differ from the fixture while the total is the same.
  defp coins_after_checks(want, turn) do
    got = get_in(turn.after, ["character", "coins"]) || %{}

    if Inventory.coin_total_copper(want) == Inventory.coin_total_copper(got),
      do: [],
      else: ["coins_after: want #{inspect(want)}, got #{inspect(got)}"]
  end

  defp post_checks(expect, record, turn) do
    if Code.ensure_loaded?(@prose_check) do
      kinds = @prose_check |> apply(:check, [turn.prose, record]) |> Enum.map(&to_string(&1.kind))
      want = get_in(expect, ["post_check", "mismatches"]) || 0

      [
        same(:post_check_mismatches, want, length(kinds)),
        if(expect["mismatch_kinds"],
          do: same(:mismatch_kinds, Enum.sort(expect["mismatch_kinds"]), Enum.sort(kinds))
        )
      ]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end
end
