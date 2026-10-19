\set ON_ERROR_STOP 1
\pset pager off
\pset tuples_only on
\pset format unaligned
SET default_transaction_read_only = on;
BEGIN TRANSACTION READ ONLY;
SELECT 'RO|' || current_setting('transaction_read_only');
SELECT 'TURN|' || json_build_object('s', game_session_id, 'n', turn_number, 'text', player_action, 'narr', narrative, 'at', inserted_at)::text
FROM turns WHERE game_session_id IN ('8a9dbde9-5971-47eb-b4a6-d0d852869014','253e26a5-e4ab-46cb-b472-7af6cdb3c25d','6d938a30-aaa6-46cf-8db8-f7e6f8c28f39') ORDER BY inserted_at;
SELECT 'CALL|' || json_build_object('s', game_session_id, 'n', turn_number, 'purpose', purpose, 'model', model, 'status', status, 'ms', latency_ms, 'in', input_tokens, 'out', output_tokens, 'cost', cost_micro_usd, 'meta', meta, 'at', started_at)::text
FROM ai_calls WHERE game_session_id IN ('8a9dbde9-5971-47eb-b4a6-d0d852869014','253e26a5-e4ab-46cb-b472-7af6cdb3c25d','6d938a30-aaa6-46cf-8db8-f7e6f8c28f39') AND purpose IN ('intent','turn.intent','npc_reaction') ORDER BY started_at;
SELECT 'CHAR|' || json_build_object('s', game_session_id, 'slug', slug, 'name', name, 'role', role, 'ocean', ocean, 'maslow', maslow_level, 'concerns', concerns, 'mood', mood, 'rel', relationships, 'loc', location_id, 'def', definition)::text
FROM characters WHERE game_session_id IN ('253e26a5-e4ab-46cb-b472-7af6cdb3c25d','6d938a30-aaa6-46cf-8db8-f7e6f8c28f39','8a9dbde9-5971-47eb-b4a6-d0d852869014') AND slug IN ('innkeep','smith','prospector','guild_steward','herb_wife');
SELECT 'MEM|' || json_build_object('s', c.game_session_id, 'slug', c.slug, 'kind', m.kind, 'text', m.text, 'belief', m.belief, 'secret', m.secret, 'sal', m.salience)::text
FROM character_memories m JOIN characters c ON c.id = m.character_id
WHERE c.game_session_id IN ('253e26a5-e4ab-46cb-b472-7af6cdb3c25d','6d938a30-aaa6-46cf-8db8-f7e6f8c28f39','8a9dbde9-5971-47eb-b4a6-d0d852869014') AND c.slug IN ('innkeep','smith','prospector');
ROLLBACK;
