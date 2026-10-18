defmodule TalesForge.Repo.Migrations.BackfillNpcStateToCharacters do
  @moduledoc """
  Refactor plan 10f PR 4, data step (pending Fredrik's OK). Main kept an
  NPC's wounds, wound_max and vitality only in `world_state["npc_state"]`;
  from PR 4 the GM character row holds them and the blob key is ignored. This
  copies them onto the matching `controller = 'gm'` row, and the gut reaction
  in `world_state["npc_moods"]` into `runtime["reaction"]` where the row has
  none.

    * Reads `world_state`, never writes it.
    * Idempotent: a step changes only rows that differ, so a re-run changes 0.
    * First saves each row it will change in `characters_backup_10f4` (rows
      already there are kept as they were). Keep that table until
      GameCharacter is on prod and stable; drop it only with Fredrik's OK.
    * Logs the rows each step changed.
    * `down` restores the saved columns from the backup and keeps the table.
      Run it only soon after `up`: it overwrites later changes to those rows.

  Undo by hand (the same as `down`):

      UPDATE characters c SET wounds = b.wounds, wound_max = b.wound_max,
        vitality = b.vitality, runtime = b.runtime, updated_at = now()
      FROM characters_backup_10f4 b WHERE c.id = b.id;
  """
  use Ecto.Migration

  require Logger

  @npc_state """
  jsonb_each(CASE WHEN jsonb_typeof(g.world_state->'npc_state') = 'object'
                  THEN g.world_state->'npc_state' ELSE '{}'::jsonb END) s
  """

  @npc_moods """
  jsonb_each(CASE WHEN jsonb_typeof(g.world_state->'npc_moods') = 'object'
                  THEN g.world_state->'npc_moods' ELSE '{}'::jsonb END) m
  """

  # The values from npc_state, the row's own where npc_state has none.
  @wounds "CASE WHEN jsonb_typeof(s.value->'wounds') = 'number' THEN (s.value->>'wounds')::numeric::int ELSE c.wounds END"
  @wound_max "CASE WHEN jsonb_typeof(s.value->'wound_max') = 'number' THEN (s.value->>'wound_max')::numeric::int ELSE c.wound_max END"
  @vitality "COALESCE(s.value->>'vitality', c.vitality)"

  # The other tables and the condition of each step (`UPDATE characters c
  # ... FROM <tables> WHERE <condition>`).
  @wound_tables "game_sessions g, #{@npc_state}"
  @wound_rows """
  c.game_session_id = g.id AND c.controller = 'gm' AND c.slug = s.key
    AND jsonb_typeof(s.value) = 'object'
    AND (s.value ? 'wounds' OR s.value ? 'wound_max' OR s.value ? 'vitality')
    AND (#{@wounds}, #{@wound_max}, #{@vitality})
        IS DISTINCT FROM (c.wounds, c.wound_max, c.vitality)
  """

  @reaction_tables "game_sessions g, #{@npc_moods}"
  @reaction_rows """
  c.game_session_id = g.id AND c.controller = 'gm' AND c.slug = m.key
    AND jsonb_typeof(m.value) = 'object' AND NOT (c.runtime ? 'reaction')
  """

  def up do
    run!("""
    CREATE TABLE IF NOT EXISTS characters_backup_10f4 (
      id uuid PRIMARY KEY,
      wounds integer,
      wound_max integer,
      vitality varchar,
      runtime jsonb,
      saved_at timestamp NOT NULL DEFAULT now()
    )
    """)

    backed_up =
      run!("""
      INSERT INTO characters_backup_10f4 (id, wounds, wound_max, vitality, runtime)
      SELECT DISTINCT c.id, c.wounds, c.wound_max, c.vitality, c.runtime
      FROM characters c
      WHERE c.id IN (SELECT c.id FROM characters c, #{@wound_tables} WHERE #{@wound_rows}
                     UNION
                     SELECT c.id FROM characters c, #{@reaction_tables} WHERE #{@reaction_rows})
      ON CONFLICT (id) DO NOTHING
      """)

    wounds =
      run!("""
      UPDATE characters c
      SET wounds = #{@wounds}, wound_max = #{@wound_max}, vitality = #{@vitality},
          lock_version = c.lock_version + 1, updated_at = now()
      FROM #{@wound_tables}
      WHERE #{@wound_rows}
      """)

    reactions =
      run!("""
      UPDATE characters c
      SET runtime = c.runtime || jsonb_build_object('reaction', m.value),
          lock_version = c.lock_version + 1, updated_at = now()
      FROM #{@reaction_tables}
      WHERE #{@reaction_rows}
      """)

    Logger.info(
      "10f-4 backfill: backed_up=#{backed_up} wound_rows=#{wounds} reaction_rows=#{reactions}"
    )
  end

  def down do
    restored =
      run!("""
      UPDATE characters c
      SET wounds = b.wounds, wound_max = b.wound_max, vitality = b.vitality,
          runtime = b.runtime, lock_version = c.lock_version + 1, updated_at = now()
      FROM characters_backup_10f4 b
      WHERE c.id = b.id
        AND (c.wounds, c.wound_max, c.vitality, c.runtime)
            IS DISTINCT FROM (b.wounds, b.wound_max, b.vitality, b.runtime)
      """)

    Logger.info("10f-4 backfill undone: restored_rows=#{restored} (backup table kept)")
  end

  defp run!(sql), do: repo().query!(sql, [], log: false).num_rows
end
