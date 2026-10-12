defmodule TalesForge.Repo.Migrations.WorkLogEntries do
  @moduledoc """
  Work log PR 3: manual work log entries (`TalesForge.WorkLog.Entry`).
  Add-only: a new table.
  """
  use Ecto.Migration

  def change do
    create table(:work_log_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :founder, :string, null: false
      add :date, :date, null: false
      add :minutes, :integer, null: false
      add :reason, :text, null: false
      add :added_by, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:work_log_entries, [:date])
  end
end
