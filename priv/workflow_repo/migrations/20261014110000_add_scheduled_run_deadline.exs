defmodule TalesForge.Workflow.Repo.Migrations.AddScheduledRunDeadline do
  @moduledoc """
  Adds `deadline_at` (UTC) to `scheduled_runs`: the end of the time limit of
  a bot run. A bot run that is still open at that time gets "no_report".
  """

  use Ecto.Migration

  def change do
    alter table(:scheduled_runs, prefix: "workflow") do
      add :deadline_at, :utc_datetime_usec
    end
  end
end
