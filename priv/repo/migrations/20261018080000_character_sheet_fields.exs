defmodule TalesForge.Repo.Migrations.CharacterSheetFields do
  use Ecto.Migration

  # Refactor plan 10b-1.5: the sheet keys the characters row kept in
  # runtime["sheet"] become columns. Nullable: nil means the sheet has no
  # such key (a character with no class, nothing reflected since the rest).
  def change do
    alter table(:characters) do
      add :class, :string
      add :creation, :map
      add :reflecting, {:array, :string}
      add :improved_since_rest, {:array, :string}
    end
  end
end
