defmodule TalesForge.Playtest.Reports do
  @moduledoc """
  Read side of playtest runs: the runs list, per-turn records with the turn's
  code-layer session events, cost per AI purpose and the latest scorecard.
  Admin and judge only; never shown to players.
  """

  import Ecto.Query

  alias TalesForge.AICalls
  alias TalesForge.AICalls.Metrics
  alias TalesForge.Game.OutcomeRecord
  alias TalesForge.GMReasoning
  alias TalesForge.Playtest.JevHeadline
  alias TalesForge.Repo
  alias TalesForge.Schemas.{AICall, PlaytestRun, PlaytestScore, SessionEvent, Turn}

  @runs_shown 100

  # Session events that are not the code layer's record of a turn: the GM's
  # raw reply and the facts extracted from the narration.
  @not_turn_events ~w(gm_reasoning world_fact)

  def list_runs do
    runs =
      PlaytestRun
      |> order_by(desc: :started_at)
      |> limit(@runs_shown)
      |> Repo.all()

    costs = session_costs(Enum.map(runs, & &1.game_session_id))
    scores = latest_scores(Enum.map(runs, & &1.id))
    turns = turn_affects_by_run(Enum.map(runs, & &1.id))

    Enum.map(runs, fn run ->
      %{
        run: run,
        game_cost_micro_usd: Map.get(costs, run.game_session_id, 0),
        score: Map.get(scores, run.id),
        jev: jev_headline(Map.get(turns, run.id, []))
      }
    end)
  end

  @doc """
  The Jev headline for a run's turn rows (`TalesForge.Playtest.JevHeadline`):
  the confidence-weighted turn average with the confident share and the
  breakdown, or nil when the run has no Jev turn scores.
  """
  @spec jev_headline([JevHeadline.row()]) :: JevHeadline.t() | nil
  def jev_headline([]), do: nil
  def jev_headline(turn_rows), do: JevHeadline.summarize(turn_rows)

  def get_run(id) do
    with {:ok, id} <- Ecto.UUID.cast(id), %PlaytestRun{} = run <- Repo.get(PlaytestRun, id) do
      {:ok, run}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Headline score for a run: newest Jev `session_affect` if any, else newest LLM
  `rubric` row (or any other kind as a last resort).
  """
  def latest_score(run_id), do: run_id |> List.wrap() |> latest_scores() |> Map.get(run_id)

  @doc "Jev per-turn affect rows for a run, oldest turn first (the newest row per turn)."
  def turn_affect_scores(run_id),
    do: run_id |> List.wrap() |> turn_affects_by_run() |> Map.get(run_id, [])

  defp turn_affects_by_run([]), do: %{}

  defp turn_affects_by_run(run_ids) do
    PlaytestScore
    |> where([s], s.playtest_run_id in ^run_ids and s.kind == "turn_affect")
    |> order_by([s], asc: s.turn_number, desc: s.inserted_at, desc: s.id)
    |> Repo.all()
    |> Enum.group_by(& &1.playtest_run_id)
    |> Map.new(fn {run_id, rows} ->
      {run_id, rows |> Enum.uniq_by(& &1.turn_number) |> Enum.sort_by(& &1.turn_number)}
    end)
  end

  @doc """
  Turns in order, each with its server roll and `events`: one line per
  session event the code layer wrote for the turn (`event_line/1`), in the
  order written. The GM's raw reply and the extracted world facts are left out.
  """
  def turn_records(session_id) do
    turns =
      Turn
      |> where([t], t.game_session_id == ^session_id)
      |> order_by(:turn_number)
      |> Repo.all()

    events = turn_events(session_id, turns)

    Enum.map(turns, fn turn ->
      %{
        id: turn.id,
        turn_number: turn.turn_number,
        player_action: turn.player_action,
        narrative: turn.narrative,
        roll: roll_text(turn.mechanical_resolution || %{}),
        events: Map.get(events, turn.turn_number, [])
      }
    end)
  end

  @doc """
  One short line for a session event of a turn: the kind, then the payload's
  plain values. A `turn.outcome` record reads as in the GM prompt
  (`TalesForge.Game.OutcomeRecord.prompt_lines/1`). A hidden event
  (`player_aware: false`) is marked.

      iex> TalesForge.Playtest.Reports.event_line(%{kind: "player.travel", player_aware: true,
      ...>   payload: %{"from" => "valley_inn", "to" => "market_square"}})
      "player.travel: from valley_inn, to market_square"
      iex> TalesForge.Playtest.Reports.event_line(%{kind: "turn.prose_mismatch", player_aware: false,
      ...>   payload: %{"count" => 1, "mismatches" => [%{"kind" => "coins", "detail" => "paid 5"}]}})
      "(hidden) turn.prose_mismatch: count 1, mismatches paid 5 coins"
  """
  @spec event_line(%{kind: String.t(), player_aware: boolean(), payload: map()}) :: String.t()
  def event_line(%{player_aware: false} = event),
    do: "(hidden) " <> event_line(%{event | player_aware: true})

  def event_line(%{kind: "turn.outcome", payload: record}),
    do: "turn.outcome: " <> Enum.join(OutcomeRecord.prompt_lines(record), " ")

  def event_line(%{kind: kind, payload: payload}) do
    case payload |> Enum.sort() |> Enum.flat_map(&detail/1) do
      [] -> kind
      details -> kind <> ": " <> Enum.join(details, ", ")
    end
  end

  defp detail({_key, value}) when value in [nil, "", []], do: []

  defp detail({key, items}) when is_list(items),
    do: ["#{key} #{Enum.map_join(items, "; ", &plain/1)}"]

  defp detail({key, value}), do: if(plain?(value), do: ["#{key} #{value}"], else: [])

  defp plain(%{} = item) do
    item |> Enum.sort() |> Enum.map(&elem(&1, 1)) |> Enum.filter(&plain?/1) |> Enum.join(" ")
  end

  defp plain(value), do: if(plain?(value), do: to_string(value), else: "")

  defp plain?(value), do: is_binary(value) or is_number(value) or is_boolean(value)

  # The session's code-layer events by turn number.
  defp turn_events(_session_id, []), do: %{}

  defp turn_events(session_id, turns) do
    ticks =
      session_id
      |> GMReasoning.list_for_session()
      |> Map.new(&{&1.payload["turn_number"], &1.tick})

    placed = Enum.map(turns, &Map.put(&1, :tick, Map.get(ticks, &1.turn_number)))

    SessionEvent
    |> where([e], e.game_session_id == ^session_id and e.kind not in ^@not_turn_events)
    |> order_by([e], asc: e.inserted_at, asc: e.tick)
    |> Repo.all()
    |> Enum.group_by(&turn_for(&1, placed), &event_line/1)
  end

  # A turn's events are written in its transaction at its world tick (the
  # tick its gm_reasoning event records): of the turns at the event's tick,
  # else of all turns, the last one written by the time the event was.
  defp turn_for(event, turns) do
    at_tick = Enum.filter(turns, &(&1.tick == event.tick))

    if(at_tick == [], do: turns, else: at_tick)
    |> Enum.filter(&(DateTime.compare(&1.inserted_at, event.inserted_at) != :gt))
    |> List.last()
    |> case do
      nil -> nil
      turn -> turn.turn_number
    end
  end

  @doc "The GM's opening narration the player (or persona) saw before turn 1, or nil."
  def opening(session_id) do
    case TalesForge.Scenes.opening(session_id) do
      nil -> nil
      scene -> %{location_name: scene.location_name, narrative: scene.narrative}
    end
  end

  @doc """
  Call-type metrics for a run's session (`TalesForge.AICalls.Metrics.session_report/1`):
  breakdown by call_type and purpose with p50/p90 latency, per-turn rows, cache
  hit rate and GM idle gaps. Persona and scorer are their own sections.
  """
  def metrics(session_id), do: Metrics.session_report(session_id)

  @doc """
  Compact metrics for `Runner.status/1` (rpc and `mix playtest.run` output):
  USD floats and ms, GM turns 2+ cache figures, one entry per turn.
  """
  def metrics_summary(session_id) do
    m = metrics(session_id)
    usd = fn micro -> micro && micro / 1_000_000 end
    later = m.cache.gm_later

    %{
      turns: m.turns,
      gm_p50_ms: m.gm.p50_ms,
      gm_p90_ms: m.gm.p90_ms,
      gm_cost_per_call_usd: usd.(m.gm.avg_cost_micro_usd),
      game_cost_usd: usd.(m.game.cost_micro_usd),
      game_cost_per_turn_usd: usd.(m.game_cost_per_turn),
      persona_cost_usd: usd.(m.persona.cost_micro_usd),
      gm_later_hits: "#{later.hits}/#{later.calls}",
      gm_later_hit_rate: later.hit_rate && Float.round(later.hit_rate, 3),
      gm_idle_gap_p50_ms: m.idle_gap.p50_ms,
      per_turn:
        Enum.map(m.per_turn, fn t ->
          %{
            turn: t.turn_number,
            gm_ms: t.gm_latency_ms,
            input: t.gm_input_tokens,
            cached: t.gm_cached_tokens,
            output: t.gm_output_tokens,
            gm_cost_usd: usd.(t.gm_cost_micro_usd),
            idle_gap_ms: t.idle_gap_ms,
            steps_ms: t.steps
          }
        end)
    }
  end

  def roll_text(%{"roll" => roll} = mechanical) when is_integer(roll) do
    against =
      if mechanical["effective_skill"], do: " vs #{mechanical["effective_skill"]}", else: ""

    [mechanical["skill"], "d100 #{roll}#{against}", mechanical["outcome"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  def roll_text(%{"outcome" => outcome}) when outcome not in [nil, "none"], do: outcome
  def roll_text(_mechanical), do: nil

  @doc """
  Game cost per session in micro-USD (every AI call except the bots' own:
  persona and scorer), as `%{session_id => micro_usd}`. Sessions without calls
  are left out.
  """
  @spec session_costs([Ecto.UUID.t()]) :: %{optional(Ecto.UUID.t()) => non_neg_integer()}
  def session_costs([]), do: %{}

  def session_costs(session_ids) do
    AICall
    |> where([c], c.game_session_id in ^session_ids and c.purpose not in ^AICalls.bot_purposes())
    |> group_by([c], c.game_session_id)
    |> select([c], {c.game_session_id, type(coalesce(sum(c.cost_micro_usd), 0), :integer)})
    |> Repo.all()
    |> Map.new()
  end

  defp latest_scores([]), do: %{}

  defp latest_scores(run_ids) do
    PlaytestScore
    |> where([s], s.playtest_run_id in ^run_ids)
    |> where([s], s.kind in ^["session_affect", "rubric"])
    |> order_by([s], [
      s.playtest_run_id,
      asc: fragment("CASE WHEN ? = 'session_affect' THEN 0 ELSE 1 END", s.kind),
      desc: s.inserted_at,
      desc: s.id
    ])
    |> distinct([s], s.playtest_run_id)
    |> Repo.all()
    |> Map.new(&{&1.playtest_run_id, &1})
  end
end
