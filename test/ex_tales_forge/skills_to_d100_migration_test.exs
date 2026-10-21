defmodule TalesForge.SkillsToD100MigrationTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Repo

  @migration "priv/repo/migrations/20261014120000_skills_to_d100.exs"

  setup_all do
    [{mod, _}] = Code.require_file(@migration)
    %{mod: mod}
  end

  # npc_instances is dropped (20261021190000); this older migration still updates it.
  setup do
    Repo.query!("CREATE TEMP TABLE npc_instances (personality jsonb, runtime_state jsonb)")
    :ok
  end

  defp run(mod, direction),
    do: Enum.each(mod.statements(direction), &Repo.query!/1)

  defp world(id) do
    %{rows: [[world]]} =
      Repo.query!("SELECT world_state FROM game_sessions WHERE id = $1", [Ecto.UUID.dump!(id)])

    world
  end

  test "multiplies saved skills by 5 one time, and down undoes it", %{mod: mod} do
    id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO game_sessions (id, name, world_state, inserted_at, updated_at) VALUES ($1, 't', $2, now(), now())",
      [Ecto.UUID.dump!(id), %{"character" => %{"skills" => %{"stealth" => 3, "note" => "x"}}}]
    )

    run(mod, :up)
    assert world(id)["character"]["skills"] == %{"stealth" => 15, "note" => "x"}
    assert world(id)["game_system"] == "skill_d100"

    run(mod, :up)
    assert world(id)["character"]["skills"]["stealth"] == 15

    run(mod, :down)
    assert world(id)["character"]["skills"]["stealth"] == 3
    refute Map.has_key?(world(id), "game_system")
  end
end
