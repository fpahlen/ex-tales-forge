defmodule TalesForge.Workflow.Repo.Migrations.CreateScheduledRuns do
  @moduledoc """
  Adds `scheduled_runs`: one row for each run of a scheduled job of the team
  config (`Workflow.Team` `jobs`). All times are in UTC.
  """

  use Ecto.Migration

  def change do
    create table(:scheduled_runs, primary_key: false, prefix: "workflow") do
      add :id, :binary_id, primary_key: true
      add :job_id, :string, null: false
      add :owner, :string, null: false
      add :status, :string, null: false, default: "open"
      add :detail, :text
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:scheduled_runs, [:job_id, :started_at], prefix: "workflow")
  end
end
