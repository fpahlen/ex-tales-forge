defmodule TalesForge.Repo.Migrations.CreateNpcDefinitions do
  use Ecto.Migration

  def change do
    create table(:npc_definitions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :npc_id, :string, null: false
      add :name, :string, null: false
      add :race, :string
      add :role, :string
      add :default_location_id, :string

      add :appearance, :text
      add :personality, :text
      add :backstory, :text

      add :motivations, :map, default: %{}
      add :stock, {:array, :map}, default: []

      add :portrait_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:npc_definitions, [:npc_id])
  end
end
