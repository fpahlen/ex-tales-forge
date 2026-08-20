defmodule TalesForge.Repo.Migrations.CreateFrontInstances do
  use Ecto.Migration

  def change do
    create table(:front_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_session_id, references(:game_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :front_id, :string, null: false
      add :status, :string, null: false, default: "live"
      add :definition, :map, null: false, default: %{}
      add :runtime_state, :map, null: false, default: %{}
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create unique_index(:front_instances, [:game_session_id, :front_id])
    create index(:front_instances, [:game_session_id])
    create index(:front_instances, [:game_session_id, :status])
  end
end
