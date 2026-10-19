# LLM latency experiments. Measure only. No DB writes: messages are built in a
# READ ONLY transaction, the API calls go straight through Req and are not recorded.
# Binding: exp (string), n (int), model_override (string or nil).
alias TalesForge.{Repo, LLM, AICalls}
alias TalesForge.Game.{Context, Prompts}
alias TalesForge.Game.Schemas.{PlayerAction, SingleAction, HandlerResult, MechanicalResolution}
alias TalesForge.Prompt.Assemble
import Ecto.Query

base = Application.get_env(:ex_tales_forge, :xai_api_base, "https://api.x.ai/v1")
app_model = LLM.tier2_model() |> String.replace_prefix("xai/", "")
model = model_override || app_model
key = TalesForge.Config.xai_api_key()
auth = [{"authorization", "Bearer " <> key}, {"content-type", "application/json"}]
uri = URI.parse(base)
now = fn -> System.monotonic_time(:microsecond) end
ms = fn us -> Float.round(us / 1000, 1) end
sid = "643b8031-771d-42af-a63f-ddebbfe1ba82"
conv = "latency-exp-2026-10-18-" <> exp

emit = fn m -> IO.puts("ROW," <> Enum.map_join([m[:exp], m[:mode], m[:model], m[:run], m[:connect_ms], m[:ttfb_ms], m[:ttft_ms], m[:total_ms], m[:in], m[:out], m[:cached], m[:cost], m[:status]], ",", &to_string(&1 || ""))) end

usage_cost = fn mdl, body ->
  u = AICalls.usage(body)
  {c, _} = AICalls.cost("xai/" <> mdl, u)
  {u, c}
end

stream_call = fn body, run, mode ->
  Process.put(:lat, %{buf: "", ttft: nil, ttfb: nil, usage: nil})
  t0 = now.()
  res = Req.post(base <> "/chat/completions",
    headers: auth ++ [{"x-grok-conv-id", conv}], json: Map.merge(body, %{stream: true, stream_options: %{include_usage: true}}),
    receive_timeout: 120_000, retry: false,
    into: fn {:data, data}, acc ->
      st = Process.get(:lat)
      st = if st.ttfb, do: st, else: %{st | ttfb: now.() - t0}
      lines = String.split(st.buf <> data, "\n")
      {done, [rest]} = Enum.split(lines, -1)
      st = Enum.reduce(done, %{st | buf: rest}, fn line, s ->
        case line do
          "data: [DONE]" <> _ -> s
          "data: " <> json ->
            case Jason.decode(json) do
              {:ok, ev} ->
                txt = get_in(ev, ["choices", Access.at(0), "delta", "content"])
                s = if is_binary(txt) and txt != "" and is_nil(s.ttft), do: %{s | ttft: now.() - t0}, else: s
                if ev["usage"], do: %{s | usage: ev}, else: s
              _ -> s
            end
          _ -> s
        end
      end)
      Process.put(:lat, st)
      {:cont, acc}
    end)
  total = now.() - t0
  st = Process.get(:lat)
  status = case res do {:ok, %{status: s}} -> s; {:error, e} -> inspect(e.__struct__) end
  {u, c} = usage_cost.(body.model, st.usage || %{})
  emit.(%{exp: exp, mode: mode, model: body.model, run: run, ttfb_ms: st.ttfb && ms.(st.ttfb), ttft_ms: st.ttft && ms.(st.ttft), total_ms: ms.(total),
    in: u[:input_tokens], out: u[:output_tokens], cached: u[:cached_tokens], cost: c, status: status})
end

plain_call = fn body, run, mode ->
  t0 = now.()
  res = Req.post(base <> "/chat/completions", headers: auth ++ [{"x-grok-conv-id", conv}], json: body, receive_timeout: 120_000, retry: false)
  total = now.() - t0
  {status, b} = case res do {:ok, %{status: s, body: b}} -> {s, b}; {:error, e} -> {inspect(e.__struct__), %{}} end
  {u, c} = usage_cost.(body.model, b)
  emit.(%{exp: exp, mode: mode, model: body.model, run: run, total_ms: ms.(total), in: u[:input_tokens], out: u[:output_tokens], cached: u[:cached_tokens], cost: c, status: status})
end

gm_messages = fn ->
  {:ok, msgs} = Repo.transaction(fn ->
    Repo.query!("SET TRANSACTION READ ONLY")
    session = Repo.get!(TalesForge.Schemas.GameSession, sid) |> TalesForge.Characters.put_sheet()
    last = Repo.one(from t in TalesForge.Schemas.Turn, where: t.game_session_id == ^sid, order_by: [desc: t.turn_number], limit: 1)
    ctx = Context.build_gm_context(session)
      |> Map.merge(%{npc_reactions: [], world_facts: nil, price_lines: [], moved_from: nil, premise_findings: [], outcome_record: nil, rest_growth: nil, noticed: nil, combat: nil})
    pa = %PlayerAction{overall_intent: last.player_action, action: %SingleAction{action_type: :observe}}
    mech = if last.mechanical_resolution && last.mechanical_resolution != %{}, do: MechanicalResolution.decode(last.mechanical_resolution)
    Assemble.gm_messages(ctx, %Prompts.GmTurn{mechanical: mech, player_action: pa, handler: %HandlerResult{handler: "observe"}, turn_number: last.turn_number + 1})
  end)
  msgs
end

gm_body = fn max_tokens ->
  %{model: model, temperature: TalesForge.Config.tier2_temperature(), messages: gm_messages.(),
    response_format: %{type: "json_schema", json_schema: %{name: "narration", schema: LLM.narration_schema(LLM.gm_variant()), strict: true}},
    max_tokens: max_tokens}
end

case exp do
  "models" ->
    {:ok, r} = Req.get(base <> "/models", headers: auth)
    IO.puts("MODELS " <> Enum.map_join(r.body["data"] || [], " ", & &1["id"]))
    {:ok, r2} = Req.get(base <> "/language-models", headers: auth)
    for m <- r2.body["models"] || [], do: IO.puts("LM #{m["id"]} in=#{m["prompt_text_token_price"]} cached=#{m["cached_prompt_text_token_price"]} out=#{m["completion_text_token_price"]} aliases=#{inspect(m["aliases"])}")
  "1" ->
    host = uri.host
    hc = String.to_charlist(host)
    for i <- 1..n do
      t0 = now.()
      {:ok, ip} = :inet.getaddr(hc, :inet)
      t1 = now.()
      {:ok, sock} = :gen_tcp.connect(ip, 443, [:binary, active: false], 10_000)
      t2 = now.()
      {:ok, tls} = :ssl.connect(sock, [verify: :verify_peer, cacerts: :public_key.cacerts_get(), server_name_indication: hc,
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]], 10_000)
      t3 = now.()
      req = "GET " <> uri.path <> "/models HTTP/1.1\r\nHost: " <> host <> "\r\nAuthorization: Bearer " <> key <> "\r\nConnection: close\r\n\r\n"
      :ok = :ssl.send(tls, req)
      {:ok, first} = :ssl.recv(tls, 0, 10_000)
      t4 = now.()
      rd = fn rd, acc -> case :ssl.recv(tls, 0, 10_000) do {:ok, d} -> rd.(rd, acc <> d); _ -> acc end end
      _ = rd.(rd, first)
      t5 = now.()
      :ssl.close(tls)
      [_, st | _] = String.split(first, " ", parts: 3)
      IO.puts("NET,#{i},dns=#{ms.(t1 - t0)},tcp=#{ms.(t2 - t1)},tls=#{ms.(t3 - t2)},ttfb=#{ms.(t4 - t3)},status=#{st}")
      emit.(%{exp: "1", mode: "cold_get_models", model: "-", run: i, connect_ms: ms.(t3 - t0), ttfb_ms: ms.(t4 - t0), total_ms: ms.(t5 - t0), status: st})
    end
    Req.get(base <> "/models", headers: auth)
    for i <- 1..n do
      t0 = now.()
      {:ok, r} = Req.get(base <> "/models", headers: auth)
      emit.(%{exp: "1", mode: "warm_get_models_req", model: "-", run: i, total_ms: ms.(now.() - t0), status: r.status})
    end
  "2" ->
    for i <- 1..n, do: stream_call.(%{model: model, temperature: 0.0, max_tokens: 5, messages: [%{role: "user", content: "Say ok"}]}, i, "stream_say_ok")
  "3" ->
    b = gm_body.(5)
    IO.puts("PROMPT_CHARS #{b.messages |> Enum.map(&String.length(&1.content)) |> Enum.sum()} msgs=#{length(b.messages)}")
    for i <- 1..n, do: stream_call.(b, i, "stream_gm_max5")
  "4s" ->
    b = gm_body.(TalesForge.Config.tier2_max_tokens() + 100)
    for i <- 1..n, do: stream_call.(b, i, "stream_gm_full")
  "4n" ->
    b = gm_body.(TalesForge.Config.tier2_max_tokens() + 100)
    for i <- 1..n, do: plain_call.(b, i, "nonstream_gm_full")
  "5" ->
    b = gm_body.(TalesForge.Config.tier2_max_tokens() + 100)
    for i <- 1..n, do: stream_call.(b, i, "stream_gm_full")
end
:ok
