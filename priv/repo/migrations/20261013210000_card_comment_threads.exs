defmodule TalesForge.Repo.Migrations.CardCommentThreads do
  @moduledoc """
  Threads on card comments, the same as the team chat threads. A card
  thread is a subject thread in `team_chat_threads` with the `idea_id` of
  its card. A comment with no `thread_id` is in the General thread of its
  card, so the old comments stay in General.
  """
  use Ecto.Migration

  def change do
    alter table(:team_chat_threads) do
      add :idea_id, references(:board_ideas, type: :binary_id, on_delete: :delete_all)
    end

    create index(:team_chat_threads, [:idea_id])

    create constraint(:team_chat_threads, :card_thread_is_subject,
             check: "idea_id IS NULL OR kind = 'subject'"
           )

    alter table(:board_comments) do
      add :thread_id, references(:team_chat_threads, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
