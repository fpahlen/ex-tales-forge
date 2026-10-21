defmodule TalesForge.GameCharacter.Seeding do
  @moduledoc """
  Seeds a session's pack NPCs: one `characters` row each, from the pack
  (tin_valley) or the `priv/npcs` files, with its definition and first
  runtime state (`TalesForge.GameCharacter.Seed`).
  """

  alias TalesForge.Game.Features
  alias TalesForge.Game.Pack
  alias TalesForge.Game.WorldClock
  alias TalesForge.GameCharacter.{Defaults, Levers, Person, Seed}
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, GameSession}

  @doc """
  Seeds the session's NPCs (their character rows) from the pack (tin_valley) or the
  `priv/npcs` files. Definitions with a `derive` block get their defaults from
  `TalesForge.GameCharacter.Defaults` (skills on the PC scale, stats, OCEAN), seeded
  per session and NPC; the authored keys stay as overrides.
  """
  @spec seed_session(GameSession.t()) :: :ok
  def seed_session(%{id: session_id, world_state: world_state}) do
    adventure_id = Map.get(world_state, "adventure_id")
    world_tick = Map.get(world_state, "world_tick", WorldClock.default_start_tick())
    rules = Defaults.rules(adventure_id)

    definitions =
      case adventure_id do
        "tin_valley" ->
          Pack.load("tin_valley", Features.of(world_state)).npcs

        _ ->
          load_definitions_from_files(rules)
      end

    Enum.each(definitions, fn definition ->
      npc_id = Map.get(definition, "id") || Map.get(definition, :id)

      if npc_id do
        npc_id = to_string(npc_id)
        definition = Defaults.apply(definition, rules, Defaults.seed(session_id, npc_id))
        insert_row!(%{session_id: session_id, world_tick: world_tick}, npc_id, definition)
      end
    end)

    :ok
  end

  defp load_definitions_from_files(rules) do
    npc_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(fn file ->
      source = "priv/npcs/#{file}"
      definition = load_definition_file(file)
      Levers.validate!(definition, source)
      validate_derive!(definition, rules, source)
      definition
    end)
  end

  defp validate_derive!(%{"derive" => inputs}, rules, source),
    do: Defaults.validate_inputs!(inputs, rules, source)

  defp validate_derive!(_definition, _rules, _source), do: :ok

  # `seed` has the session id and the world tick the session starts at. The
  # player character's relationship is set when its row is written
  # (`GameCharacter.Store.seed_session/2`).
  defp insert_row!(%{session_id: session_id, world_tick: world_tick}, npc_id, definition) do
    location_id = Map.get(definition, "default_location_id", "weary_pilgrim")

    runtime =
      %{
        "location_id" => location_id,
        "mood" => get_in(definition, ["motivations", "mood"]) || "neutral",
        "relationship_score" => 0.0,
        "memories" => [],
        "since_tick" => world_tick,
        "stock" => seed_stock(definition),
        "resources" => definition["resources"] || %{},
        "public_facts" => definition["public_facts"] || []
      }
      |> maybe_seed_concern_tick(definition, world_tick)

    attrs =
      %Person{npc_id: npc_id, personality: definition, runtime_state: runtime}
      |> Seed.attrs(world_tick)
      |> Map.put(:game_session_id, session_id)

    %Character{}
    |> Character.changeset(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:game_session_id, :slug])
  end

  defp maybe_seed_concern_tick(runtime, definition, world_tick) do
    case get_in(definition, ["motivations", "current_concern"]) do
      %{} = concern ->
        Map.put(runtime, "current_concern", Map.put(concern, "since_tick", world_tick))

      _ ->
        runtime
    end
  end

  defp seed_stock(definition) do
    definition
    |> Map.get("stock", [])
    |> TalesForge.Game.Inventory.normalize_stock()
  end

  defp load_definition_file(file) do
    npc_dir()
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
  end

  # Resolved at runtime (not a module attribute): in a release priv is not at its build path.
  defp npc_dir, do: Path.join(:code.priv_dir(:ex_tales_forge), "npcs")
end
