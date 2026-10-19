\set ON_ERROR_STOP 1
\pset pager off
\pset tuples_only on
\pset format unaligned
SET default_transaction_read_only = on;
BEGIN TRANSACTION READ ONLY;
SELECT 'RO|' || current_setting('transaction_read_only');
SELECT 'LOC|' || json_build_object('s', game_session_id, 'slug', slug, 'name', name, 'race', definition->>'race', 'controller', controller, 'loc', location_id)::text
FROM characters WHERE game_session_id IN ('8a9dbde9-5971-47eb-b4a6-d0d852869014','253e26a5-e4ab-46cb-b472-7af6cdb3c25d','6d938a30-aaa6-46cf-8db8-f7e6f8c28f39');
SELECT 'WS|' || json_build_object('s', id, 'loc', world_state->>'location_id', 'present', world_state->'present_npcs', 'keys', (SELECT json_agg(k) FROM jsonb_object_keys(world_state) k))::text
FROM game_sessions WHERE id IN ('8a9dbde9-5971-47eb-b4a6-d0d852869014','253e26a5-e4ab-46cb-b472-7af6cdb3c25d','6d938a30-aaa6-46cf-8db8-f7e6f8c28f39');
SELECT 'PRES|' || json_build_object('s', game_session_id, 'n', turn_number, 'present', mechanical_resolution->'present_npcs', 'mrkeys', (SELECT json_agg(k) FROM jsonb_object_keys(mechanical_resolution) k))::text
FROM turns WHERE game_session_id = '6d938a30-aaa6-46cf-8db8-f7e6f8c28f39' AND turn_number IN (1,12);
ROLLBACK;
