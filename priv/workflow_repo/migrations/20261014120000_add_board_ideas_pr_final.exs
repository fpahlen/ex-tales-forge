defmodule TalesForge.Workflow.Repo.Migrations.AddBoardIdeasPrFinal do
  @moduledoc """
  Adds `pr_final` to the cards: false when the linked PR is one part of a
  card with more PRs to come. The board moves a card to Done only when its PR
  on prod is final (`TalesForge.Board.Workers.AutoDone`). The default true
  keeps the one-PR cards as they are.
  """

  use Ecto.Migration

  def change do
    alter table(:board_ideas, prefix: "workflow") do
      add :pr_final, :boolean, null: false, default: true
    end
  end
end
