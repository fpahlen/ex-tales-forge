# Jev's readings for the founder-survey-4-intent items (tune split only).
#
# Run from an ex-tales-forge checkout of the `intent-eval` branch (PR #81),
# which has TalesForge.Game.JevIntent and TalesForge.IntentEval:
#
#     mix run --no-start docs/scripts/survey-intent/jev_readings.exs \
#       docs/scripts/survey-intent/selection.json \
#       docs/scripts/survey-intent/jev-readings-2026-10-08.json
#
# The key is TYPESAFE_INTENT_PLAYTEST_API_KEY (billed to playtest; never printed).
# Refuses any id whose split is not "tune". Readings already in the output file
# are kept (Jev samples, so a re-run would shift the probabilities the survey
# choices were drawn from); only ids missing from it are read.

[selection_path, out_path] = System.argv()

{:ok, _} = Application.ensure_all_started(:ex_tales_forge)

alias TalesForge.Game.JevIntent
alias TalesForge.IntentEval

key = System.get_env("TYPESAFE_INTENT_PLAYTEST_API_KEY")
if key in [nil, ""], do: raise("TYPESAFE_INTENT_PLAYTEST_API_KEY is not set")
IO.puts("Jev key: TYPESAFE_INTENT_PLAYTEST_API_KEY")

ids = selection_path |> File.read!() |> Jason.decode!() |> Map.fetch!("items") |> Enum.map(& &1["id"])
items = IntentEval.load_items("test/fixtures/intent_eval/items.jsonl") |> Map.new(&{&1["id"], &1})
worlds = IntentEval.load_worlds("test/fixtures/intent_eval/worlds.json")

label_map = fn probs, by_label ->
  Map.new(probs || %{}, fn {label, p} ->
    name =
      case Map.get(by_label, label) do
        %{id: id} -> id
        nil -> to_string(label)
      end

    {name, p}
  end)
end

existing =
  case File.read(out_path) do
    {:ok, raw} -> raw |> Jason.decode!() |> Map.fetch!("readings") |> Map.new(&{&1["id"], &1})
    {:error, _} -> %{}
  end

readings =
  for id <- ids do
    if Map.has_key?(existing, id) do
      IO.puts("#{id}: kept from #{out_path}")
      Map.fetch!(existing, id)
    else
    item = Map.fetch!(items, id)
    if item["split"] != "tune", do: raise("#{id} is not in the tune split")

    context = IntentEval.build_context(item, worlds)
    candidates = JevIntent.candidates(context)
    by_label = Map.new(candidates, &{&1.label, &1})
    questions = JevIntent.questions(candidates)
    state = JevIntent.state(context, item["text"])

    {:ok, reply} =
      Jev.HTTP.post(state, questions,
        model: "jev-1.13.0",
        max_retries: 1,
        receive_timeout: 60_000,
        api_key: key
      )

    r = JevIntent.decode(reply, candidates, text: item["text"], context: context)
    probs = reply[:probabilities] || %{}

    IO.puts("#{id}: #{r.action} -> #{inspect(r.target)} later #{inspect(r.later)} -> #{inspect(r.later_target)} (conf #{inspect(r.confidence)})")

    %{
      id: id,
      candidates: Enum.map(candidates, &%{id: &1.id, kind: &1.kind, text: &1.text}),
      reading: %{
        action: r.action,
        target: r.target,
        skill: r.skill,
        later: r.later,
        later_target: r.later_target,
        confidence: r.confidence
      },
      probabilities: %{
        action: probs[:action] || %{},
        target: label_map.(probs[:target], by_label),
        later: probs[:later] || %{},
        later_target: label_map.(probs[:later_target], by_label)
      },
      model: r.model,
      cost: r.cost
    }
    end
  end

File.write!(out_path, Jason.encode_to_iodata!(%{model: "jev-1.13.0", readings: readings}, pretty: true))
IO.puts("Wrote #{out_path}; cost $#{readings |> Enum.map(&((&1[:cost] || &1["cost"]) || 0)) |> Enum.sum()}")
