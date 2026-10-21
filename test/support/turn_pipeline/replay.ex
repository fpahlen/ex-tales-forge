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
    * With `npc_memory` in `pending_on`, the NPC reactions run with a stub
      Jev reply. The harness reads the input of each NPC call.
    * `history` reads what the next turn reads: the stored turns (player text
      and narration), the situation lines and the NPC memory.
    * `stage_order` compares the fixture order with `Steps.purposes/0`.
    * A key that the harness does not support fails the fixture, so that a
      fixture never passes without its checks.
  """

  import ExUnit.Assertions, only: [assert_received: 1]
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.Inventory
  alias TalesForge.Game.OutcomeRecord
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.Game.WorldClock
  alias TalesForge.GameCharacter.Roster
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, SessionEvent, Turn}

  import Ecto.Query

  @worlds %{"1e9114ed" => "tin_valley", "8eab5ea0" => "crossroads_ledger"}

  @flags %{
    "outcome_record" => "TURN_OUTCOME_RECORD",
    "premise_first" => "TURN_PREMISE_FIRST",
    "state_from_mechanics" => "TURN_STATE_FROM_MECHANICS",
    "npc_memory" => ["NPC_DIALOGUE_MEMORY", "NPC_REACTIONS"],
    "history_strip" => "HISTORY_STRIP_INJECTION"
  }

  # The stub Jev reply for an NPC reaction (NPC_REACTIONS=on).
  @npc_reply [
    emotion: :wary,
    intensity: 2.0,
    stance: 2.0,
    confidence: %{emotion: 0.8, stance: 0.8},
    usage: %{input_tokens: 400}
  ]

  # TURN_OUTCOME_RECORD is always on: the record is what the harness reads.
  @base_env %{"INN_WORLD" => "on", "WORLD_ANTAGONIST" => "on", "TURN_OUTCOME_RECORD" => "on"}

  @default_prose "The table waits."

  @supported ~w(intent premise outcome post_check mismatch_kinds fixture_fails gm_prompt
                coins_after npc stage_order history inventory_lacks)

  @prose_check TalesForge.Game.ProseCheck

  @doc "Plays the fixture. Returns `:ok` or `{:error, failures}`."
  @spec run(map()) :: :ok | {:error, [String.t()]}
  def run(item) do
    env = env_for(item)
    saved = Map.new(env, fn {key, _} -> {key, System.get_env(key)} end)
    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)
    jev_key = Application.get_env(:jev, :api_key)
    if "npc_memory" in item["pending_on"], do: stub_npcs()

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
      Application.put_env(:jev, :api_key, jev_key)

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
    session = GameSessions.get_session!(session.id)
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

    session =
      session
      |> GameSession.changeset(%{world_state: world})
      |> TalesForge.DataCase.save_session!()

    put_stock(session.id, context["stock"] || %{})
    session
  end

  defp put_skills(character, nil), do: character
  defp put_skills(character, skills), do: Map.put(character, "skills", skills)

  defp put_stock(session_id, stock) do
    # Written the way a trade writes goods (`Roster.put_inventories/2`).
    traders = Roster.traders(session_id, Map.keys(stock))

    :ok =
      Roster.put_inventories(session_id, for({id, t} <- traders, do: %{t | inventory: stock[id]}))
  end

  # --- one turn ----------------------------------------------------------------

  defp play(turn, session_id, context) do
    expect = turn["expect"]

    case unsupported(turn) do
      [] ->
        prose = turn["gm_mock_prose"] || @default_prose
        stub_gm(prose)
        before = GameSessions.get_session!(session_id).world_state
        events_before = events(session_id)
        action = player_action(turn["text"], expect, context)
        {:ok, _payload} = TurnProcessor.run(session_id, {turn["text"], action})
        assert_received {:replay_gm_prompt, prompt}
        npc_inputs = npc_inputs([])
        after_turn = GameSessions.get_session!(session_id).world_state
        new_events = events(session_id) -- events_before

        check(expect, %{
          before: before,
          after: after_turn,
          events: new_events,
          prompt: prompt,
          npc_inputs: npc_inputs,
          context: context,
          session_id: session_id,
          text: turn["text"],
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
    keys
  end

  defp stub_npcs do
    test_pid = self()
    Application.put_env(:jev, :api_key, "replay-key")

    Req.Test.stub(Jev.HTTP, fn conn ->
      {request, conn} = Jev.Test.request(conn)

      send(
        test_pid,
        {:replay_npc_input, inspect(request, limit: :infinity, printable_limit: :infinity)}
      )

      Jev.Test.respond(conn, @npc_reply)
    end)
  end

  defp npc_inputs(acc) do
    receive do
      {:replay_npc_input, input} -> npc_inputs([input | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp stub_gm(prose) do
    test_pid = self()

    stub_llm(fn
      :gm, user, _system ->
        send(test_pid, {:replay_gm_prompt, user})
        %{"narrative" => prose}

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
        npc_checks(expect["npc"], record, turn) ++
        stage_order_checks(expect["stage_order"]) ++
        history_checks(expect["history"], turn) ++
        inventory_lacks_checks(expect["inventory_lacks"], turn) ++
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
      |> String.replace(~r/^(killed|slew|slain|murdered)\s+/, "")
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

  # --- stage 4: NPC memory, repetition guard, NPC input ------------------------

  defp npc_checks(nil, _record, _turn), do: []

  defp npc_checks(npcs, record, turn) do
    Enum.flat_map(npcs, fn {npc_id, wants} ->
      wants
      |> Enum.flat_map(&npc_check(&1, npc_id, record, turn))
      |> Enum.map(&"npc #{npc_id}: #{&1}")
    end)
  end

  defp npc_check({"no_repeat_of_memory", true}, npc_id, _record, turn) do
    repeats =
      for %{kind: "turn.npc_repeat", payload: %{"repeats" => list}} <- turn.events,
          %{"npc_id" => ^npc_id, "line" => line} <- list,
          do: line

    memory = get_in(turn.before, ["npc_memory", npc_id]) || []

    cond do
      repeats != [] ->
        ["repeats a memory line: #{inspect(repeats)}"]

      memory != [] and not String.contains?(turn.prompt, "NPC dialogue memory") ->
        ["memory missing from the GM prompt"]

      true ->
        []
    end
  end

  defp npc_check({"memory_lines_max", max}, npc_id, _record, turn) do
    lines = get_in(turn.after, ["npc_memory", npc_id]) || []

    if length(lines) <= max,
      do: [],
      else: ["memory_lines_max: want <= #{max}, got #{length(lines)}"]
  end

  defp npc_check({"input_has_premise_findings", true}, npc_id, _record, turn) do
    name = npc_name(turn.context, npc_id)
    inputs = Enum.filter(turn.npc_inputs, &String.contains?(&1, "NPC: #{name}"))

    cond do
      inputs == [] -> ["no NPC reaction call for #{name}"]
      Enum.all?(inputs, &String.contains?(&1, "premise findings")) -> []
      true -> ["the NPC input has no premise findings"]
    end
  end

  defp npc_check({"no_free_items", true}, _npc_id, record, _turn) do
    case record["items"]["gained"] do
      [] -> []
      gained -> ["free items: #{inspect(Enum.map(gained, & &1["id"]))}"]
    end
  end

  defp npc_check({"lines_must_not_contain", words}, npc_id, _record, turn) do
    name = npc_name(turn.context, npc_id)
    npcs = [%{id: npc_id, names: Enum.uniq([name, name |> String.split() |> hd()])}]

    lines =
      for({^npc_id, line} <- TalesForge.Game.DialogueMemory.lines(turn.prose, npcs), do: line) ++
        (get_in(turn.after, ["npc_memory", npc_id]) || [])

    for word <- words, line <- lines, contains?(line, word), do: "line has #{inspect(word)}"
  end

  defp npc_check({key, _value}, _npc_id, _record, _turn), do: ["unsupported key #{key}"]

  defp contains?(text, word), do: String.contains?(String.downcase(text), String.downcase(word))

  # --- step 7: the history that the next turn reads -----------------------------

  defp history_checks(nil, _turn), do: []

  defp history_checks(want, turn) do
    history = history(turn)

    banned =
      for word <- want["must_not_contain"] || [],
          Enum.any?(history, &contains?(&1, word)),
          do: "history has #{inspect(word)}"

    marked =
      if want["no_marked_copy"] && Enum.any?(history, &contains?(&1, turn.text)),
        do: ["history keeps a copy of the injected text"],
        else: []

    banned ++ marked
  end

  defp history(turn) do
    turns =
      Turn
      |> where([t], t.game_session_id == ^turn.session_id)
      |> select([t], [t.player_action, t.narrative])
      |> Repo.all()
      |> List.flatten()

    memory = turn.after |> Map.get("npc_memory", %{}) |> Map.values() |> List.flatten()
    Enum.reject(turns ++ List.wrap(turn.after["situation_lines"]) ++ memory, &is_nil/1)
  end

  defp inventory_lacks_checks(nil, _turn), do: []

  defp inventory_lacks_checks(ids, turn) do
    held = turn.after |> get_in(["character", "inventory"]) |> List.wrap() |> Enum.map(& &1["id"])
    for id <- ids, id in held, do: "inventory_lacks: has #{id}"
  end

  defp npc_name(context, npc_id) do
    context["present_npcs"]
    |> Enum.find(%{}, &(&1["id"] == npc_id))
    |> Map.get("name", npc_id)
  end

  @stages %{
    "intent" => "turn.intent",
    "premise" => "turn.premise_check",
    "mechanics" => "turn.rules",
    "npcs" => "turn.npc_reactions",
    "narration" => "turn.gm"
  }

  defp stage_order_checks(nil), do: []

  defp stage_order_checks(stages) do
    order = TalesForge.AICalls.Steps.purposes()
    positions = Enum.map(stages, &Enum.find_index(order, fn p -> p == @stages[&1] end))

    if positions == Enum.sort(positions) and nil not in positions,
      do: [],
      else: ["stage_order: want #{inspect(stages)}, got #{inspect(order)}"]
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
