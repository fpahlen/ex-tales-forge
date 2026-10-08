# Pilot (ex-tales-forge PR #69): re-score the 2026-10-07 baseline Paul and Lotta runs with the old and
# the stricter rubric (Jev jev-1.13.0), from /workspace/baseline/final/jev_export.json.
# Run from an ex-tales-forge checkout on the jev-stricter-rubric branch (or main
# after it merges) with TYPESAFE_API_KEY set:
#   EXPORT=jev_export.json OUT=rescore.json mix run path/to/rescore.exs
# Jev only; no game calls. About 52 Jev calls for 26 runs.
# RUBRICS=new runs only the current (stricter) rubric: 26 Jev calls. Since 2026-10-08 each row also keeps
# the turn confidences, the turn and session probabilities and the rubric hash, which the
# confidence-aware reading (docs/scripts/jev-confidence/) needs.
Code.require_file(Path.join(__DIR__, "old_affect_levels.exs"))
{:ok, _} = Application.ensure_all_started(:jev)

alias TalesForge.Playtest.AffectLevels

# SINCE / UNTIL (2026-10-08) pick the runs by start time; the defaults are the 2026-10-07 baseline series.
# Post-rework: EXPORT=/workspace/compare/final/series_done.json SINCE=2026-10-08T00:00.
since = System.get_env("SINCE", "2026-10-07T17:25")
until = System.get_env("UNTIL", "9999")

runs =
  System.get_env("EXPORT", "/workspace/baseline/final/jev_export.json")
  |> File.read!()
  |> Jason.decode!()
  |> Enum.filter(fn r ->
    r["run"]["persona"] in ["paul", "lotta"] and r["run"]["started_at"] >= since and
      r["run"]["started_at"] < until
  end)

IO.puts("runs: #{length(runs)}")

state = fn r ->
  opening = if r["opening"], do: ["Opening (GM):\n#{r["opening"]}"], else: []

  turns =
    r["turns"]
    |> Enum.sort_by(& &1["n"])
    |> Enum.map(fn t -> "Turn #{t["n"]}\nPlayer: #{t["player"]}\nGM: #{t["gm"]}" end)

  Enum.join(opening ++ turns, "\n\n")
end

questions = fn mod, persona, name, ns ->
  levels = mod.levels(persona)

  ns
  |> Map.new(fn n -> {:"persona_turn_affect_#{n}", {mod.turn_question(persona, name, n), levels}} end)
  |> Map.put(:persona_session_affect, {mod.session_question(persona, name), levels})
end

rubrics =
  System.get_env("RUBRICS", "old,new")
  |> String.split(",", trim: true)
  |> Enum.map(fn
    "old" -> {"old", OldAffectLevels}
    "new" -> {"new", AffectLevels}
  end)

rows =
  for r <- runs, {label, mod} <- rubrics do
    persona = r["run"]["persona"]
    name = String.capitalize(persona)
    ns = r["turns"] |> Enum.map(& &1["n"]) |> Enum.sort()

    case Jev.HTTP.post(state.(r), questions.(mod, persona, name, ns), model: "jev-1.13.0") do
      {:ok, reply} ->
        probs = Map.get(reply, :probabilities) || %{}

        argmax = fn key ->
          case probs[key] do
            nil -> nil
            p -> p |> Enum.max_by(fn {_k, v} -> v end) |> elem(0) |> to_string() |> String.to_integer() |> Kernel.+(1)
          end
        end

        turn_keys = Enum.map(ns, &:"persona_turn_affect_#{&1}")

        row = %{
          "run" => r["run"]["id"],
          "persona" => persona,
          "rubric" => label,
          "session" => reply[:persona_session_affect] && Float.round(reply[:persona_session_affect] + 1.0, 2),
          "session_conf" => get_in(reply, [:confidence, :persona_session_affect]),
          "turns" => Enum.map(turn_keys, &(reply[&1] && Float.round(reply[&1] + 1.0, 2))),
          "turn_argmax" => Enum.map(turn_keys, argmax),
          "turn_conf" => Enum.map(turn_keys, &get_in(reply, [:confidence, &1])),
          "turn_probs" => Enum.map(turn_keys, &probs[&1]),
          "session_probs" => probs[:persona_session_affect],
          "rubric_hash" => if(label == "new", do: AffectLevels.rubric_hash(persona)),
          "usage" => Map.get(reply, :usage)
        }

        IO.puts(Jason.encode!(row))
        row

      {:error, reason} ->
        IO.puts("error #{r["run"]["id"]} #{label}: #{inspect(reason)}")
        nil
    end
  end

File.write!(System.get_env("OUT", "rescore.json"), Jason.encode!(Enum.reject(rows, &is_nil/1)))
