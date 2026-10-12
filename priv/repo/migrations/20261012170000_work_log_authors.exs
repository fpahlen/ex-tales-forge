defmodule TalesForge.Repo.Migrations.WorkLogAuthors do
  @moduledoc """
  Work log PR 1: the author and time of card text edits and game turns.
  Add-only: a nullable column on `turns` and a new table `board_edits`.
  """
  use Ecto.Migration

  def change do
    alter table(:turns) do
      add :founder, :string
    end

    create index(:turns, [:founder, :inserted_at])

    create table(:board_edits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :idea_id, references(:board_ideas, type: :binary_id, on_delete: :delete_all), null: false
      add :author, :string, null: false
      add :fields, {:array, :string}, null: false, default: []
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:board_edits, [:idea_id])
    create index(:board_edits, [:author, :inserted_at])
  end
end
