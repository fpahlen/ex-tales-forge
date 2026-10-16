defmodule TalesForge.Repo.Migrations.CharacterMemoryCompression do
  use Ecto.Migration

  # Board card 845b6b15, PR 2: the belief of a long-term memory, and the tick
  # of the last compression per character.
  # A compressed short-term row and a faded long-term row get the tier
  # `faded`: the row stays (the NPC mirror matches on it), recall skips it.
  def up do
    alter table(:character_memories) do
      add :belief, :string
    end

    drop constraint(:character_memories, :character_memories_tier_check)

    create constraint(:character_memories, :character_memories_tier_check,
             check: "tier IN ('working', 'short', 'long', 'faded')"
           )

    alter table(:characters) do
      add :memory_compressed_tick, :integer
    end
  end

  def down do
    execute "UPDATE character_memories SET tier = 'short' WHERE tier = 'faded'"
    drop constraint(:character_memories, :character_memories_tier_check)

    create constraint(:character_memories, :character_memories_tier_check,
             check: "tier IN ('working', 'short', 'long')"
           )

    alter table(:characters), do: remove(:memory_compressed_tick)
    alter table(:character_memories), do: remove(:belief)
  end
end
