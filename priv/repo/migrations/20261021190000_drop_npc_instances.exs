defmodule TalesForge.Repo.Migrations.DropNpcInstances do
  @moduledoc """
  Drops `npc_instances`. Nothing has read or written it since an NPC's state
  moved to its `characters` row (20261018130000); its schema module is gone.
  Fredrik approved the drop; the prod rows were dumped first (see the PR).

  `down` recreates the empty table and its index exactly as
  20260702190000_create_game_core made them. The rows are not restored.
  """

  use Ecto.Migration

  def up do
    drop table(:npc_instances)
  end

  def down do
    create table(:npc_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_session_id, references(:game_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :npc_id, :string, null: false
      add :personality, :map, null: false, default: %{}
      add :runtime_state, :map, null: false, default: %{}
      add :disposition, :float, null: false, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:npc_instances, [:game_session_id, :npc_id])
  end
end
