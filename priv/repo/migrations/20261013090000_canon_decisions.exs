defmodule TalesForge.Repo.Migrations.CanonDecisions do
  @moduledoc """
  Session versus canon: founder decisions on session differences
  (`TalesForge.Canon.Decision`). Add-only: a new table.
  """
  use Ecto.Migration

  def change do
    create table(:canon_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :game_session_id, references(:game_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :diff_key, :string, null: false
      add :action, :string, null: false
      add :founder, :string, null: false
      add :difference, :map, null: false, default: %{}
      add :seed_patch, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:canon_decisions, [:game_session_id, :diff_key])
  end
end
