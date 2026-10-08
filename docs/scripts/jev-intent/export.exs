# Read-only export for the Jev intent design note (2026-10-08). No writes.
import Ecto.Query
alias TalesForge.Repo
alias TalesForge.Schemas.{AICall, Turn, PlaytestRun}
alias TalesForge.Game.{Intent, Context}

since = ~U[2026-10-06 00:00:00Z]

pct = fn list, p ->
  s = Enum.sort(list)
  case s do
    [] -> nil
    _ -> Enum.at(s, min(length(s) - 1, round(p * (length(s) - 1))))
  end
end

stats = fn purpose, call_type ->
  rows = Repo.all(from c in AICall, where: c.purpose == ^purpose and c.call_type == ^call_type and c.inserted_at > ^since and c.status == "ok",
    select: %{lat: c.latency_ms, cost: c.cost_micro_usd, inp: c.input_tokens, out: c.output_tokens, cached: c.cached_tokens, model: c.model})
  lats = Enum.map(rows, & &1.lat) |> Enum.reject(&is_nil/1)
  costs = Enum.map(rows, & &1.cost) |> Enum.reject(&is_nil/1)
  inps = Enum.map(rows, & &1.inp) |> Enum.reject(&is_nil/1)
  outs = Enum.map(rows, & &1.out) |> Enum.reject(&is_nil/1)
  %{purpose: purpose, call_type: call_type, n: length(rows), lat_p50: pct.(lats, 0.5), lat_p90: pct.(lats, 0.9),
    cost_mean: (costs != [] && Enum.sum(costs) / length(costs)) || nil, in_mean: (inps != [] && Enum.sum(inps) / length(inps)) || nil,
    out_mean: (outs != [] && Enum.sum(outs) / length(outs)) || nil, models: rows |> Enum.map(& &1.model) |> Enum.frequencies()}
end

agg = [stats.("intent", "llm"), stats.("npc_reaction", "jev"), stats.("scorer", "jev"), stats.("gm", "llm"), stats.("turn.intent", "function")]

# Runs, default variant, excluding the intent-on series (flag forced the LLM call).
runs = Repo.all(from r in PlaytestRun, where: r.started_at > ^since, order_by: r.started_at,
  select: %{id: r.id, gs: r.game_session_id, persona: r.persona, notes: r.notes, flags: r.flags, status: r.status})

turn_rows = Enum.flat_map(runs, fn r ->
  turns = Repo.all(from t in Turn, where: t.game_session_id == ^r.gs, order_by: t.turn_number,
    select: %{n: t.turn_number, player: t.player_action, mech: t.mechanical_resolution})
  calls = Repo.all(from c in AICall, where: c.game_session_id == ^r.gs and c.purpose in ["intent", "turn.intent"],
    select: %{n: c.turn_number, purpose: c.purpose, lat: c.latency_ms, status: c.status})
  by_turn = Enum.group_by(calls, & &1.n)
  Enum.map(turns, fn t ->
    cs = Map.get(by_turn, t.n, [])
    %{run: r.id, persona: r.persona, notes: r.notes, flags: r.flags, n: t.n, player: t.player,
      skill: t.mech["skill"], outcome: t.mech["outcome"],
      intent_calls: Enum.count(cs, &(&1.purpose == "intent")),
      intent_steps: Enum.count(cs, &(&1.purpose == "turn.intent")),
      intent_step_ms: cs |> Enum.filter(&(&1.purpose == "turn.intent")) |> Enum.map(& &1.lat)}
  end)
end)

# Heuristic re-read of player texts against each session's current context (pure function; approximate context).
heur = runs
|> Enum.reject(&String.contains?(&1.notes || "", "series=intent-on"))
|> Enum.flat_map(fn r ->
  session = Repo.get(TalesForge.Schemas.GameSession, r.gs)
  ctx = try do Context.build_intent_context(session) rescue _ -> nil end
  if ctx do
    Repo.all(from t in Turn, where: t.game_session_id == ^r.gs, order_by: t.turn_number, select: {t.turn_number, t.player_action})
    |> Enum.map(fn {n, text} ->
      h = try do
        e = Intent.heuristic_intent(text, ctx)
        a = hd(e.actions)
        %{type: a.action_type, target: a.target, skill: a.parameters["skill"], conf: e.confidence}
      rescue err -> %{error: Exception.message(err)} end
      %{run: r.id, n: n, heur: h}
    end)
  else [] end
end)

File.write!("/tmp/jev_intent_export.json", Jason.encode!(%{agg: agg, turns: turn_rows, heur: heur}))
IO.puts("OK runs=#{length(runs)} turns=#{length(turn_rows)} heur=#{length(heur)}")
