alias TalesForge.Repo
IO.puts("CFG model=#{TalesForge.LLM.tier2_model()} temp=#{TalesForge.Config.tier2_temperature()} max=#{TalesForge.Config.tier2_max_tokens()} role=#{TalesForge.AppRole.role()} variant=#{TalesForge.LLM.gm_variant()} base=#{Application.get_env(:ex_tales_forge, :xai_api_base, "default")}")
IO.puts("FLAGS " <> inspect(TalesForge.Game.Turn.read_flags() |> Enum.sort()))
Repo.transaction(fn ->
  Repo.query!("SET TRANSACTION READ ONLY")
  r = Repo.query!("""
  select game_session_id::text, turn_number, purpose, call_type, model, status, latency_ms, ttft_ms, input_tokens, output_tokens, cached_tokens, cost_micro_usd,
    to_char((started_at at time zone 'UTC') at time zone 'Europe/Stockholm','HH24:MI:SS.MS') st, to_char((inserted_at at time zone 'UTC') at time zone 'Europe/Stockholm','HH24:MI:SS.MS') ins
  from ai_calls where inserted_at >= (date_trunc('day', now() at time zone 'Europe/Stockholm') at time zone 'Europe/Stockholm') and game_session_id is not null
  order by game_session_id, turn_number, coalesce(started_at, inserted_at)
  """)
  IO.puts("NROWS #{length(r.rows)}")
  for row <- r.rows, do: IO.puts(Enum.map_join(row, "\t", &to_string/1))
end)
