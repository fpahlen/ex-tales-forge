alias TalesForge.Repo
import Ecto.Query
Repo.transaction(fn ->
  Repo.query!("SET TRANSACTION READ ONLY")
  IO.puts("TIER2=#{TalesForge.LLM.tier2_model()} TIER1=#{TalesForge.LLM.tier1_model()} PROVIDER=#{TalesForge.Config.llm_provider()} role=#{TalesForge.AppRole.role()} variant=#{TalesForge.LLM.gm_variant()} max=#{TalesForge.Config.tier2_max_tokens()} temp=#{TalesForge.Config.tier2_temperature()}")
  r = Repo.query!("""
  select game_session_id::text, turn_number, purpose, call_type, model, status, latency_ms, ttft_ms, input_tokens, output_tokens, cached_tokens, cost_micro_usd,
    to_char((started_at at time zone 'UTC') at time zone 'Europe/Stockholm','HH24:MI:SS.MS') st, to_char((inserted_at at time zone 'UTC') at time zone 'Europe/Stockholm','HH24:MI:SS.MS') ins
  from ai_calls where inserted_at > now() - interval '20 hours' and game_session_id is not null
  order by game_session_id, turn_number, coalesce(started_at, inserted_at)
  """)
  IO.puts(Enum.join(r.columns, "\t"))
  for row <- r.rows, do: IO.puts(Enum.map_join(row, "\t", &to_string/1))
end)
