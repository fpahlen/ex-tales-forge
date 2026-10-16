defmodule TalesForge.Repo.Migrations.CharacterMemoryTiers do
  use Ecto.Migration

  # Board card fc3c9371, PR 1: memory tiers, associations and weight.
  # Existing rows count as short-term memory.
  def change do
    alter table(:character_memories) do
      add :tier, :string, null: false, default: "short"
      add :about, {:array, :string}, null: false, default: []
      add :weight, :float, null: false, default: 1.0
    end

    create constraint(:character_memories, :character_memories_tier_check,
             check: "tier IN ('working', 'short', 'long')"
           )

    create index(:character_memories, [:character_id, :tier])
  end
end
