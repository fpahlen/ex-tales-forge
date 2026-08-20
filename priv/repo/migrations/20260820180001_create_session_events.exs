defmodule TalesForge.Repo.Migrations.CreateSessionEvents do
  use Ecto.Migration

  def change do
    create table(:session_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_session_id, references(:game_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :actor, :string
      add :player_aware, :boolean, null: false, default: true
      add :tick, :integer, null: false
      add :location_id, :string
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:session_events, [:game_session_id, :tick])
    create index(:session_events, [:game_session_id, :kind])
    create index(:session_events, [:game_session_id, :player_aware])
  end
end
