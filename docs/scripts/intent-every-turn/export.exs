# Read-only export of the intent-every-turn batch (series names starting with "intent-").
import Ecto.Query
alias TalesForge.Repo
alias TalesForge.Schemas.{PlaytestRun, PlaytestScore, AICall, Turn}
runs = Repo.all(from r in PlaytestRun, where: like(r.notes, "series=intent-%"), order_by: r.started_at)
out = Enum.map(runs, fn r ->
  gs = r.game_session_id
  %{run: Map.take(r, [:id, :persona, :build, :git_sha, :turn_limit, :turns_played, :status, :stop_reason, :started_at, :finished_at, :notes, :game_ms, :persona_calls, :persona_ms, :persona_cost_micro_usd, :persona_input_tokens, :persona_output_tokens, :flags]),
    scores: Repo.all(from s in PlaytestScore, where: s.playtest_run_id == ^r.id, order_by: [s.kind, s.turn_number]) |> Enum.map(&Map.take(&1, [:source, :kind, :turn_number, :overall, :confidence, :rubric_version])),
    turns: Repo.all(from t in Turn, where: t.game_session_id == ^gs, order_by: t.turn_number) |> Enum.map(&%{n: &1.turn_number, player: &1.player_action, gm: &1.narrative, at: &1.inserted_at}),
    calls: Repo.all(from c in AICall, where: c.game_session_id == ^gs, order_by: c.inserted_at) |> Enum.map(&Map.take(&1, [:turn_number, :purpose, :model, :status, :latency_ms, :cost_micro_usd, :input_tokens, :output_tokens, :cached_tokens, :call_type, :started_at, :inserted_at, :meta]))}
end)
File.write!("/tmp/intent_export.json", Jason.encode!(out))
IO.puts("RUNS #{length(out)} BYTES #{byte_size(Jason.encode!(out))}")
