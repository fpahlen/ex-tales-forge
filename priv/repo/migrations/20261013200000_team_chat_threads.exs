defmodule TalesForge.Repo.Migrations.TeamChatThreads do
  @moduledoc """
  Threads for the team chat. A thread has a subject, a kind (`subject` or
  `direct`), the members and the time of the last message. A direct thread
  has two founder handles as members. A subject thread has no members: each
  founder and each bot can read it.

  The migration makes one subject thread with the key `general` and the
  subject "General". It moves all old messages and all read marks to that
  thread. The read marks then have one row for each founder and thread.
  """
  use Ecto.Migration

  @general "00000000-0000-0000-0000-00000000c4a7"

  def up do
    create table(:team_chat_threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string
      add :subject, :string, null: false
      add :kind, :string, null: false
      add :members, {:array, :string}, null: false, default: []
      add :created_by, :string
      add :last_message_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:team_chat_threads, [:key])
    create index(:team_chat_threads, [:last_message_at])

    create unique_index(:team_chat_threads, [:members],
             where: "kind = 'direct'",
             name: :team_chat_threads_direct_members_index
           )

    create constraint(:team_chat_threads, :kind_is_known,
             check: "kind IN ('subject', 'direct')"
           )

    create constraint(:team_chat_threads, :direct_has_two_members,
             check: "kind <> 'direct' OR cardinality(members) = 2"
           )

    execute("""
    INSERT INTO team_chat_threads
      (id, key, subject, kind, members, last_message_at, inserted_at, updated_at)
    VALUES (
      '#{@general}', 'general', 'General', 'subject', '{}',
      COALESCE((SELECT max(inserted_at) FROM team_chat_messages), now()),
      now(), now()
    )
    """)

    alter table(:team_chat_messages) do
      add :thread_id, references(:team_chat_threads, type: :binary_id, on_delete: :restrict)
    end

    execute("UPDATE team_chat_messages SET thread_id = '#{@general}'")
    execute("ALTER TABLE team_chat_messages ALTER COLUMN thread_id SET NOT NULL")
    create index(:team_chat_messages, [:thread_id, :inserted_at])

    alter table(:team_chat_reads) do
      add :thread_id, references(:team_chat_threads, type: :binary_id, on_delete: :delete_all)
    end

    execute("UPDATE team_chat_reads SET thread_id = '#{@general}'")
    execute("ALTER TABLE team_chat_reads ALTER COLUMN thread_id SET NOT NULL")
    execute("ALTER TABLE team_chat_reads DROP CONSTRAINT team_chat_reads_pkey")
    execute("ALTER TABLE team_chat_reads ADD PRIMARY KEY (handle, thread_id)")
  end

  def down do
    execute("DELETE FROM team_chat_reads WHERE thread_id <> '#{@general}'")
    execute("ALTER TABLE team_chat_reads DROP CONSTRAINT team_chat_reads_pkey")
    execute("ALTER TABLE team_chat_reads ADD PRIMARY KEY (handle)")

    alter table(:team_chat_reads) do
      remove :thread_id
    end

    execute("DELETE FROM team_chat_messages WHERE thread_id <> '#{@general}'")

    alter table(:team_chat_messages) do
      remove :thread_id
    end

    drop table(:team_chat_threads)
  end
end
