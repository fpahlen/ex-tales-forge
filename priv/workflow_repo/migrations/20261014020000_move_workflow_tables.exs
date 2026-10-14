defmodule TalesForge.Workflow.Repo.Migrations.MoveWorkflowTables do
  @moduledoc """
  Moves the Workflow tables from `public` to the Postgres schema `workflow`
  and adds the Oban tables of the Workflow Oban instance there.

  The game migrations in `priv/repo/migrations` made these tables first. The
  release runs those migrations before this one (`TalesForge.Release`).
  The foreign keys between Workflow tables stay. The foreign key from
  `board_ideas.collab_decision_id` goes, so the id is a plain id.
  """

  use Ecto.Migration

  @tables ~w(
    collab_decisions collab_comments collab_docs collab_interests
    board_goals board_ideas board_comments board_votes board_goal_votes
    board_links board_transitions board_approvals board_answers board_pings
    board_edits board_deletions
    team_chat_threads team_chat_messages team_chat_reads team_images
    work_log_events work_log_entries
    inbox_items
  )

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS workflow")
    execute("ALTER TABLE board_ideas DROP CONSTRAINT IF EXISTS board_ideas_collab_decision_id_fkey")

    for table <- @tables do
      execute("ALTER TABLE public.#{table} SET SCHEMA workflow")
    end

    Oban.Migration.up(version: 14, prefix: "workflow")
  end

  def down do
    Oban.Migration.down(version: 1, prefix: "workflow")

    for table <- Enum.reverse(@tables) do
      execute("ALTER TABLE workflow.#{table} SET SCHEMA public")
    end

    execute("""
    ALTER TABLE board_ideas
      ADD CONSTRAINT board_ideas_collab_decision_id_fkey
      FOREIGN KEY (collab_decision_id) REFERENCES collab_decisions (id) ON DELETE SET NULL
    """)

    execute("DROP SCHEMA IF EXISTS workflow CASCADE")
  end
end
