# Read-only export of every playtest run with its Jev scores, turns, AI calls and
# character, for compare.py. Run on the playtest machine (see the plan doc):
#   /app/bin/ex_tales_forge rpc 'Code.eval_file("/tmp/export.exs")'
# Writes /tmp/jev_export.json. No writes to the database, no AI calls.
import Ecto.Query
alias TalesForge.Repo
alias TalesForge.Schemas.{AICall, FrontInstance, GameSession, PlaytestRun, PlaytestScore, Scene, SessionEvent, Turn}

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
    opening = TalesForge.Scenes.opening(gs)
    # Scenes, world events and fronts (ex-tales-forge #68, #72, #73): where the character went and
    # what the Tinjacks did. gm_reasoning payloads are left out (large, not needed).
    scenes = Repo.all(from s in Scene, where: s.game_session_id == ^gs, order_by: s.inserted_at,
                                        select: %{location_id: s.location_id, location_name: s.location_name, at: s.inserted_at})
    events =
      Repo.all(from e in SessionEvent, where: e.game_session_id == ^gs, order_by: e.inserted_at)
      |> Enum.map(&%{kind: &1.kind, actor: &1.actor, tick: &1.tick, location_id: &1.location_id,
                     payload: if(&1.kind == "gm_reasoning", do: %{}, else: &1.payload), at: &1.inserted_at})
    fronts = Repo.all(from f in FrontInstance, where: f.game_session_id == ^gs,
                                                select: %{front_id: f.front_id, status: f.status, runtime_state: f.runtime_state})

    %{
      run:
        r
        |> Map.take([:id, :persona, :module, :build, :turn_limit, :turns_played, :status, :stop_reason,
                     :started_at, :finished_at, :notes, :game_ms, :persona_calls, :persona_ms,
                     :persona_cost_micro_usd])
        # git_sha and flags exist once ex-tales-forge #55 is merged.
        |> Map.put(:git_sha, Map.get(r, :git_sha))
        |> Map.put(:flags, Map.get(r, :flags) || %{})
        # growth (skill rolls, LP gained, improvements) exists once ex-tales-forge #66 is merged.
        |> Map.put(:growth, Map.get(r, :growth) || %{}),
      variant: ws["variant"] || "default",
      character: Map.take(ws["character"] || %{}, ["name", "race", "class", "level"]),
      scores: Enum.map(scores, &Map.take(&1, [:source, :kind, :turn_number, :overall, :confidence,
                                              :probabilities, :rubric_version, :model, :inserted_at])),
      turns: Enum.map(turns, &%{n: &1.turn_number, player: &1.player_action, gm: &1.narrative,
                                mech: &1.mechanical_resolution, at: &1.inserted_at}),
      calls: Enum.map(calls, &Map.take(&1, [:turn_number, :purpose, :model, :status, :latency_ms,
                                            :input_tokens, :output_tokens, :cached_tokens,
                                            :cost_micro_usd, :inserted_at])),
      opening: opening && opening.narrative,
      features: ws["features"] || [],
      location_id: ws["location_id"],
      scenes: scenes,
      events: events,
      fronts: fronts,
      # Per-run character-change numbers (memories added, NPCs changed, NPC attitude toward the
      # player character), once TalesForge.Playtest.CharacterChanges is deployed (read-only).
      character_changes:
        if Code.ensure_loaded?(TalesForge.Playtest.CharacterChanges) do
          gs
          |> TalesForge.Playtest.CharacterChanges.for_session()
          |> TalesForge.Playtest.CharacterChanges.run_metrics()
          |> Map.from_struct()
        end
    }
  end)

File.write!("/tmp/jev_export.json", Jason.encode!(out))
IO.puts("runs=#{length(out)} bytes=#{File.stat!("/tmp/jev_export.json").size}")
