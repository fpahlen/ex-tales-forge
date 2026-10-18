defmodule TalesForge.Repo.Migrations.CharacterLifetime do
  use Ecto.Migration

  # Refactor plan 10f PR 4: how long a character's row lives. Every row
  # written so far is "persistent", the default; a minor foe is "scene" and
  # its row is removed when its scene ends. Additive: no existing row changes.
  def change do
    alter table(:characters) do
      add :lifetime, :string, null: false, default: "persistent"
    end
  end
end
