defmodule TalesForge.DropAuthoringTablesMigrationTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Repo

  @migration "priv/repo/migrations/20261007130000_drop_authoring_tables.exs"

  @module TalesForge.Repo.Migrations.DropAuthoringTables

  # Load the migration once. Another test can load it first (a migration
  # run), so load it only when it is missing: a second load redefines the
  # module and warns. The module comes from the test context, so the
  # compiler does not warn about a module that it cannot see.
  setup_all do
    unless Code.ensure_loaded?(@module), do: Code.require_file(@migration)
    {:ok, migration: @module}
  end

  # The test DB has already run the migration, so recreate the three tables
  # inside the sandbox transaction (rolled back after each test).
  setup do
    for table <- ~w(adventures locations npc_definitions) do
      Repo.query!("CREATE TABLE #{table} (id bigserial PRIMARY KEY)")
    end

    :ok
  end

  test "the safety check passes when all three tables are empty", %{migration: migration} do
    assert :ok = migration.assert_tables_empty!(Repo)
  end

  test "the safety check refuses to drop tables that still hold rows", %{migration: migration} do
    Repo.query!("INSERT INTO npc_definitions DEFAULT VALUES")

    assert_raise RuntimeError, ~r/still hold rows \(npc_definitions: 1\)/, fn ->
      migration.assert_tables_empty!(Repo)
    end
  end
end
