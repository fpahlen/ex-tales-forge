defmodule TalesForge.Repo.Migrations.CreateAdventures do
  use Ecto.Migration

  def change do
    create table(:adventures, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :adventure_id, :string, null: false
      add :name, :string, null: false
      add :synopsis, :text
      add :starting_location_id, :string
      add :initial_present_npc_ids, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventures, [:adventure_id])
  end
end
