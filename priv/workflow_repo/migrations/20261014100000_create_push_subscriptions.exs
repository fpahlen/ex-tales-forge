defmodule TalesForge.Workflow.Repo.Migrations.CreatePushSubscriptions do
  @moduledoc """
  Adds `push_subscriptions`: one row for each founder and browser profile
  (`Workflow.Push.Subscription`). The push endpoint is unique, because each
  browser profile has its own endpoint.
  """

  use Ecto.Migration

  def change do
    create table(:push_subscriptions, primary_key: false, prefix: "workflow") do
      add :id, :binary_id, primary_key: true
      add :handle, :string, null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
      add :user_agent, :string
      add :last_sent_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:push_subscriptions, [:endpoint], prefix: "workflow")
    create index(:push_subscriptions, [:handle], prefix: "workflow")
  end
end
