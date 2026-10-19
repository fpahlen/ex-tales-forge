# Prod (:lean) GM turn latency. Measure only, no DB writes (messages built in a
# READ ONLY transaction; calls go straight through Req and are not recorded).
# Binding: n (int). Prompt: role :production + prod's feature flags (read from the
# prod machine on 2026-10-18), :lean schema, prod output settings.
alias TalesForge.{Repo, LLM, AICalls}
alias TalesForge.Game.{Context, Prompts}
alias TalesForge.Game.Schemas.{PlayerAction, SingleAction, HandlerResult, MechanicalResolution}
alias TalesForge.Prompt.Assemble
import Ecto.Query

prod_flags = %{character_memory: false, combat_opposed: false, history_strip_injection: false, jev_catalogue_v2: false,
  npc_dialogue_memory: false, npc_first_meeting: true, npc_reactions: false, skill_detail_level: false, skill_split: false,
  turn_apply_outcomes: false, turn_outcome_record: false, turn_premise_first: false, turn_state_from_mechanics: false, world_agents: false}

base = Application.get_env(:ex_tales_forge, :xai_api_base, "https://api.x.ai/v1")
model = LLM.tier2_model() |> String.replace_prefix("xai/", "")
key = TalesForge.Config.xai_api_key()
auth = [{"authorization", "Bearer " <> key}, {"content-type", "application/json"}]
now = fn -> System.monotonic_time(:microsecond) end
ms = fn us -> Float.round(us / 1000, 1) end
sid = "643b8031-771d-42af-a63f-ddebbfe1ba82"
conv = "latency-exp-2026-10-18-lean"

messages = fn ->
  {:ok, msgs} = Repo.transaction(fn ->
    Repo.query!("SET TRANSACTION READ ONLY")
    session = Repo.get!(TalesForge.Schemas.GameSession, sid) |> TalesForge.Characters.put_sheet()
    last = Repo.one(from t in TalesForge.Schemas.Turn, where: t.game_session_id == ^sid, order_by: [desc: t.turn_number], limit: 1)
    ctx = Context.build_gm_context(session)
      |> Map.merge(%{npc_reactions: [], world_facts: nil, price_lines: [], moved_from: nil, premise_findings: [], outcome_record: nil, rest_growth: nil, noticed: nil, combat: nil})
    pa = %PlayerAction{overall_intent: last.player_action, action: %SingleAction{action_type: :observe}}
    mech = if last.mechanical_resolution && last.mechanical_resolution != %{}, do: MechanicalResolution.decode(last.mechanical_resolution)
    Assemble.gm_messages(ctx, %Prompts.GmTurn{mechanical: mech, player_action: pa, handler: %HandlerResult{handler: "observe"}, turn_number: last.turn_number + 1},
      role: :production, flags: prod_flags)
  end)
  msgs
end.()

# Same budget as LLM.gm_opts(:lean, ...): TIER2_MAX_TOKENS + notes_budget(:lean) = 700 + 0.
body = %{model: model, temperature: TalesForge.Config.tier2_temperature(), messages: messages,
  response_format: %{type: "json_schema", json_schema: %{name: "narration", schema: LLM.narration_schema(:lean), strict: true}},
  max_tokens: TalesForge.Config.tier2_max_tokens() + 0, stream: true, stream_options: %{include_usage: true}}
IO.puts("PROMPT chars=#{messages |> Enum.map(&String.length(&1.content)) |> Enum.sum()} msgs=#{length(messages)} max_tokens=#{body.max_tokens} temp=#{body.temperature} schema_keys=#{inspect(Map.keys(LLM.narration_schema(:lean)["properties"].values |> Map.new()))}")

# Where the narrative string value ends: index just after its closing quote, or nil.
narr_end = fn text ->
  case Regex.run(~r/"narrative"\s*:\s*"/, text, return: :index) do
    [{s, l}] ->
      rest = binary_part(text, s + l, byte_size(text) - s - l)
      scan = fn scan, <<c, r::binary>>, i, esc ->
        cond do
          esc -> scan.(scan, r, i + 1, false)
          c == ?\\ -> scan.(scan, r, i + 1, true)
          c == ?" -> {s + l, s + l + i + 1}
          true -> scan.(scan, r, i + 1, false)
        end
        end
      scan2 = fn scan2, bin, i, esc -> if bin == "", do: nil, else: scan.(scan, bin, i, esc) end
      _ = scan2
      try do
        scan.(scan, rest, 0, false)
      rescue
        FunctionClauseError -> nil
      end
    _ -> nil
  end
end

for i <- 1..n do
  Process.put(:lat, %{buf: "", text: "", chunks: 0, ttft: nil, first_narr: nil, narr_end: nil, usage: nil})
  t0 = now.()
  res = Req.post(base <> "/chat/completions", headers: auth ++ [{"x-grok-conv-id", conv}], json: body, receive_timeout: 120_000, retry: false,
    into: fn {:data, data}, acc ->
      st = Process.get(:lat)
      lines = String.split(st.buf <> data, "\n")
      {done, [rest]} = Enum.split(lines, -1)
      st = Enum.reduce(done, %{st | buf: rest}, fn
        "data: [DONE]" <> _, s -> s
        "data: " <> json, s ->
          case Jason.decode(json) do
            {:ok, ev} ->
              s = if ev["usage"], do: %{s | usage: ev}, else: s
              txt = get_in(ev, ["choices", Access.at(0), "delta", "content"])
              if is_binary(txt) and txt != "" do
                t = now.() - t0
                text = s.text <> txt
                s = %{s | text: text, chunks: s.chunks + 1, ttft: s.ttft || t}
                s = if is_nil(s.first_narr) and Regex.match?(~r/"narrative"\s*:\s*"[^"]/, text), do: %{s | first_narr: t}, else: s
                if is_nil(s.narr_end) do
                  case narr_end.(text) do
                    {_, e} -> %{s | narr_end: %{t: t, chunk: s.chunks, char: e}}
                    nil -> s
                  end
                else
                  s
                end
              else
                s
              end
            _ -> s
          end
        _, s -> s
      end)
      Process.put(:lat, st)
      {:cont, acc}
    end)
  total = now.() - t0
  st = Process.get(:lat)
  status = case res do {:ok, %{status: s}} -> s; {:error, e} -> inspect(e.__struct__) end
  u = AICalls.usage(st.usage || %{})
  {c, _} = AICalls.cost("xai/" <> model, u)
  ne = st.narr_end || %{t: nil, chunk: nil, char: nil}
  IO.puts("LEAN,#{i},status=#{status},ttft=#{ms.(st.ttft)},first_narr=#{st.first_narr && ms.(st.first_narr)},narr_end_ms=#{ne.t && ms.(ne.t)},total=#{ms.(total)}," <>
    "in=#{u[:input_tokens]},out=#{u[:output_tokens]},cached=#{u[:cached_tokens]},cost=#{c},chunks=#{st.chunks},narr_end_chunk=#{ne.chunk},narr_end_char=#{ne.char},chars=#{String.length(st.text)}")
  IO.puts("TAIL,#{i}," <> Jason.encode!(%{tail: ne.char && binary_part(st.text, ne.char, byte_size(st.text) - ne.char)}))
end
:ok
