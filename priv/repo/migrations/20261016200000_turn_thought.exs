defmodule TalesForge.Repo.Migrations.TurnThought do
  use Ecto.Migration

  # Board card 845b6b15, PR 3: the player character's thought after a turn
  # (text, trigger, about), stored with the log so a reload shows it again.
  def change do
    alter table(:turns) do
      add :thought, :map
    end
  end
end
