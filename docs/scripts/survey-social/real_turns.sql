-- The 2026-10-18 (Europe/Stockholm) player turns, read-only. Run through a
-- wrapper that adds `SET default_transaction_read_only = on; BEGIN TRANSACTION
-- READ ONLY;` before and `ROLLBACK;` after, e.g.
--   flyctl postgres connect -a tales-forge-playtest-db-wa -d tales_forge_playtest
-- Prod (tales-forge-db-wa, tales_forge) had no turns that day (checked the same way).
-- Only the player's line and the GM narration are read: no founder, user or
-- character-sheet columns, no Jev readings (ai_calls is not read).
\pset tuples_only on
\pset format unaligned
SELECT 'TURN|' || json_build_object(
         's', game_session_id, 'n', turn_number,
         'text', player_action, 'narr', narrative, 'at', inserted_at)::text
FROM turns
WHERE inserted_at >= '2026-10-17 22:00Z' AND inserted_at < '2026-10-18 22:00Z'
ORDER BY game_session_id, turn_number;
