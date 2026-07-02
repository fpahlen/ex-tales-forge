defmodule TalesForge.Repo.Migrations.CreateGameCore do
  use Ecto.Migration

  def change do
    create table(:game_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :world_state, :map, null: false, default: %{}
      add :world_clock, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:turns, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_session_id, references(:game_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :turn_number, :integer, null: false
      add :player_action, :text, null: false
      add :narrative, :text
      add :mechanical_resolution, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:turns, [:game_session_id, :turn_number])

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
