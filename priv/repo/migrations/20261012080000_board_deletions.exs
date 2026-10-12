defmodule TalesForge.Repo.Migrations.BoardDeletions do
  @moduledoc """
  The audit record of the founders' hard deletes from the board's Archive
  (`TalesForge.Board.delete_archived/3`). Add-only: a new table. The card
  and its rows go; this row stays.
  """
  use Ecto.Migration

  def change do
    create table(:board_deletions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :idea_id, :binary_id, null: false
      add :title, :string, size: 200, null: false
      add :deleted_by, :string, null: false
      add :archive_reason, :text
      add :image_count, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:board_deletions, [:inserted_at])
  end
end
