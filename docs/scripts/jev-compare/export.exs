# Read-only export of every playtest run with its Jev scores, turns, AI calls and
# character, for compare.py. Run on the playtest machine (see the plan doc):
#   /app/bin/ex_tales_forge rpc 'Code.eval_file("/tmp/export.exs")'
# Writes /tmp/jev_export.json. No writes to the database, no AI calls.
import Ecto.Query
alias TalesForge.Repo
alias TalesForge.Schemas.{AICall, GameSession, PlaytestRun, PlaytestScore, Turn}

runs = Repo.all(from r in PlaytestRun, order_by: r.started_at)

out =
  Enum.map(runs, fn r ->
    gs = r.game_session_id
    ws =
      case Repo.get(GameSession, gs) do
        %{world_state: ws} when is_map(ws) -> ws
        _ -> %{}
      end

    scores =
      Repo.all(from s in PlaytestScore, where: s.playtest_run_id == ^r.id, order_by: [s.kind, s.turn_number])

    turns = Repo.all(from t in Turn, where: t.game_session_id == ^gs, order_by: t.turn_number)
    calls = Repo.all(from c in AICall, where: c.game_session_id == ^gs, order_by: c.inserted_at)
    opening = TalesForge.GameSessions.opening_scene(gs)

    %{
      run:
        r
        |> Map.take([:id, :persona, :module, :build, :turn_limit, :turns_played, :status, :stop_reason,
                     :started_at, :finished_at, :notes, :game_ms, :persona_calls, :persona_ms,
                     :persona_cost_micro_usd])
        # git_sha and flags exist once ex-tales-forge #55 is merged.
        |> Map.put(:git_sha, Map.get(r, :git_sha))
        |> Map.put(:flags, Map.get(r, :flags) || %{}),
      variant: ws["variant"] || "default",
      character: Map.take(ws["character"] || %{}, ["name", "race", "class", "level"]),
      scores: Enum.map(scores, &Map.take(&1, [:source, :kind, :turn_number, :overall, :confidence,
                                              :probabilities, :rubric_version, :model, :inserted_at])),
      turns: Enum.map(turns, &%{n: &1.turn_number, player: &1.player_action, gm: &1.narrative,
                                mech: &1.mechanical_resolution, at: &1.inserted_at}),
      calls: Enum.map(calls, &Map.take(&1, [:turn_number, :purpose, :model, :status, :latency_ms,
                                            :input_tokens, :output_tokens, :cached_tokens,
                                            :cost_micro_usd, :inserted_at])),
      opening: opening && opening.narrative
    }
  end)

File.write!("/tmp/jev_export.json", Jason.encode!(out))
IO.puts("runs=#{length(out)} bytes=#{File.stat!("/tmp/jev_export.json").size}")
