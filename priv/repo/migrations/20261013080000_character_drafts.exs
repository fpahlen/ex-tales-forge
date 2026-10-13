defmodule TalesForge.Repo.Migrations.CharacterDrafts do
  @moduledoc """
  Character creation PR 1: the server keeps the draft of each player for each
  adventure (`TalesForge.CharacterDrafts`), so a reload keeps the dice roll.
  Add-only: a new table.
  """
  use Ecto.Migration

  def change do
    create table(:character_drafts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner, :string, null: false
      add :adventure_id, :string, null: false
      add :draft, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:character_drafts, [:owner, :adventure_id])
  end
end
