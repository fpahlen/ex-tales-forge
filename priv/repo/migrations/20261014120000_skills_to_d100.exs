defmodule TalesForge.Repo.Migrations.SkillsToD100 do
  @moduledoc """
  The d100 switch: skills go from the 1d20 scale to the 1d100 scale. Every
  saved skill level is multiplied by 5 one time, so the odds stay the same
  (level n on 1d20 is n × 5 on 1d100).

  The flag `game_system = "skill_d100"` makes the step idempotent:

    * `game_sessions`: `world_state->>'game_system'`; the step multiplies
      `world_state.character.skills` and sets the flag.
    * `characters`: `runtime->>'game_system'`; the step multiplies `skills`.
    * `npc_instances`: `runtime_state->>'game_system'`; the step multiplies
      `personality.skills`.

  A row that has the flag is not changed again. `down` divides by 5 (rounded
  down) and removes the flag.
  """
  use Ecto.Migration

  @flag "skill_d100"

  def up, do: Enum.each(statements(:up), &execute/1)

  def down, do: Enum.each(statements(:down), &execute/1)

  @doc "The SQL statements of one direction, in order (the test runs them too)."
  def statements(:up) do
    [
      scale_fn(:up),
      """
      UPDATE game_sessions
      SET world_state = CASE
        WHEN jsonb_typeof(world_state #> '{character,skills}') = 'object'
          THEN jsonb_set(world_state, '{character,skills}', tf_scale_skills(world_state #> '{character,skills}', 5))
        ELSE world_state
      END || jsonb_build_object('game_system', '#{@flag}')
      WHERE world_state IS NOT NULL
      AND coalesce(world_state->>'game_system', '') <> '#{@flag}'
      """,
      """
      UPDATE characters
      SET skills = tf_scale_skills(skills, 5),
        runtime = coalesce(runtime, '{}'::jsonb) || jsonb_build_object('game_system', '#{@flag}')
      WHERE coalesce(runtime->>'game_system', '') <> '#{@flag}'
      """,
      """
      UPDATE npc_instances
      SET personality = CASE
        WHEN jsonb_typeof(personality->'skills') = 'object'
          THEN jsonb_set(personality, '{skills}', tf_scale_skills(personality->'skills', 5))
        ELSE personality
      END,
      runtime_state = coalesce(runtime_state, '{}'::jsonb) || jsonb_build_object('game_system', '#{@flag}')
      WHERE coalesce(runtime_state->>'game_system', '') <> '#{@flag}'
      """,
      "DROP FUNCTION tf_scale_skills(jsonb, integer)"
    ]
  end

  def statements(:down) do
    [
      scale_fn(:down),
      """
      UPDATE game_sessions
      SET world_state = CASE
        WHEN jsonb_typeof(world_state #> '{character,skills}') = 'object'
          THEN jsonb_set(world_state, '{character,skills}', tf_scale_skills(world_state #> '{character,skills}', 5))
        ELSE world_state
      END - 'game_system'
      WHERE world_state->>'game_system' = '#{@flag}'
      """,
      """
      UPDATE characters
      SET skills = tf_scale_skills(skills, 5), runtime = runtime - 'game_system'
      WHERE runtime->>'game_system' = '#{@flag}'
      """,
      """
      UPDATE npc_instances
      SET personality = CASE
        WHEN jsonb_typeof(personality->'skills') = 'object'
          THEN jsonb_set(personality, '{skills}', tf_scale_skills(personality->'skills', 5))
        ELSE personality
      END,
      runtime_state = runtime_state - 'game_system'
      WHERE runtime_state->>'game_system' = '#{@flag}'
      """,
      "DROP FUNCTION tf_scale_skills(jsonb, integer)"
    ]
  end

  # Multiplies (up) or divides (down) every numeric value of a skills object.
  # Other values stay as they are.
  defp scale_fn(direction) do
    op =
      if direction == :up,
        do: "(value::text)::numeric * factor",
        else: "floor((value::text)::numeric / factor)"

    """
    CREATE OR REPLACE FUNCTION tf_scale_skills(skills jsonb, factor integer) RETURNS jsonb AS $$
      SELECT coalesce(
        jsonb_object_agg(
          key,
          CASE WHEN jsonb_typeof(value) = 'number' THEN to_jsonb((#{op})::integer) ELSE value END
        ),
        '{}'::jsonb
      )
      FROM jsonb_each(CASE WHEN jsonb_typeof(skills) = 'object' THEN skills ELSE '{}'::jsonb END)
    $$ LANGUAGE sql IMMUTABLE
    """
  end
end
