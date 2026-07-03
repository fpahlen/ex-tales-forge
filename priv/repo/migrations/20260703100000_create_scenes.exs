defmodule TalesForge.Repo.Migrations.CreateScenes do
  use Ecto.Migration

  def change do
    create table(:scenes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_session_id, references(:game_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :location_id, :string, null: false
      add :location_name, :string, null: false
      add :narrative, :text, null: false
      add :image_url, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:scenes, [:game_session_id, :location_id])
    create index(:scenes, [:game_session_id])
  end
end
