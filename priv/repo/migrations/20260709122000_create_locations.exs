defmodule TalesForge.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :location_id, :string, null: false
      add :adventure_id, :string, null: false
      add :name, :string, null: false
      add :exits, {:array, :string}, default: []
      add :blurb, :text
      add :fixtures, {:array, :string}, default: []
      add :ground_items, {:array, :map}, default: []
      add :scene_image_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:locations, [:adventure_id, :location_id])
    create index(:locations, [:adventure_id])
  end
end
