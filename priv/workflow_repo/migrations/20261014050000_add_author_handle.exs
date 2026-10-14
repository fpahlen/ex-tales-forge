defmodule TalesForge.Workflow.Repo.Migrations.AddAuthorHandle do
  @moduledoc """
  Adds `author_handle` to the chat messages and the card comments: the
  founder handle of the author, when it is known. The thread participants
  (`TalesForge.Chat.ThreadRules.participants/4`) read it.
  """

  use Ecto.Migration

  def change do
    alter table(:team_chat_messages, prefix: "workflow") do
      add :author_handle, :string
    end

    alter table(:board_comments, prefix: "workflow") do
      add :author_handle, :string
    end
  end
end
