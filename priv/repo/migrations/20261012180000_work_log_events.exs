defmodule TalesForge.Repo.Migrations.WorkLogEvents do
  @moduledoc """
  Work log PR 2: one row for each founder action (`TalesForge.WorkLog.Event`).
  Add-only: a new table. Production also stores the playtest rows, so the
  unique index is on the app, the kind and the source row.
  """
  use Ecto.Migration

  def change do
    create table(:work_log_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :founder, :string, null: false
      add :kind, :string, null: false
      add :app, :string, null: false
      add :ref, :string, null: false
      add :at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:work_log_events, [:app, :kind, :ref])
    create index(:work_log_events, [:founder, :at])
    create index(:work_log_events, [:app, :at])
  end
end
