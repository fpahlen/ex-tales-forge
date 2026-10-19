\set ON_ERROR_STOP 1
\pset pager off
SET default_transaction_read_only = on;
BEGIN TRANSACTION READ ONLY;
SELECT current_database() db, current_setting('transaction_read_only') ro;
SELECT t.game_session_id, t.founder, count(*) turns, min(t.inserted_at), max(t.inserted_at)
FROM turns t WHERE t.inserted_at >= '2026-10-17 22:00Z' AND t.inserted_at < '2026-10-18 22:00Z'
GROUP BY 1,2 ORDER BY 4;
SELECT purpose, call_type, count(*) FROM ai_calls WHERE game_session_id IN ('8a9dbde9-5971-47eb-b4a6-d0d852869014','253e26a5-e4ab-46cb-b472-7af6cdb3c25d','6d938a30-aaa6-46cf-8db8-f7e6f8c28f39') GROUP BY 1,2 ORDER BY 1;
ROLLBACK;
