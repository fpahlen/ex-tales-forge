defmodule TalesForge.Repo.Migrations.InboxItems do
  use Ecto.Migration

  # Board card "Inbox: one triage queue per person" (Workflow.Inbox).
  def change do
    create table(:inbox_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :recipient, :string, null: false
      add :rule, :string, null: false
      add :kind, :string, null: false
      add :state, :string, null: false, default: "new"
      add :position, :integer, null: false
      add :source, :string, null: false
      add :source_id, :string
      add :idea_id, :binary_id
      add :url, :string, null: false
      add :title, :string
      add :author, :string
      add :body, :text, null: false, default: ""
      add :acted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:inbox_items, [:recipient, :state, :position])
    create index(:inbox_items, [:idea_id])
    create unique_index(:inbox_items, [:recipient, :source, :source_id])
  end
end
