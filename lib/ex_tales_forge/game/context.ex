defmodule TalesForge.Game.Context do
  @moduledoc false

  # NON-NEGOTIABLE: Core runtime. Pure Ecto + game logic only.
  # No Ash (neither AdminResources nor Authoring) in context building for turns.
  # Rules come from Prompts (which may be pack-aware), but state is Ecto.

  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.World
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, Turn}

  def build_intent_context(%GameSession{} = session) do
    world = session.world_state || %{}
    location_id = location_id(world) || "weary_pilgrim"
    location = World.runtime_location(world, location_id)

    present =
      case present_npcs(world) do
        [] -> ["marta_kellen"]
        npcs -> npcs
      end

    npc_state = npc_state(world) || World.npcs()
    character = character(world)
    npc_stock = NPC.stock_map(session.id, present)

    %{
      "location_id" => location_id,
      "location_name" => location_name(world) || Map.get(location, "name", location_id),
      "location_blurb" => Map.get(location, "blurb", ""),
      "fixtures" => Map.get(location, "fixtures", []),
      "ground_items" => Map.get(location, "ground_items", []),
      "npc_stock" => npc_stock,
      "exits" => Map.get(location, "exits", []),
      "exit_names" => exit_names(Map.get(location, "exits", [])),
      "present_npcs" => present,
      "npc_details" => npc_details(present, npc_state),
      "character" => character_summary(character),
      "player_inventory" => player_inventory(character),
      "situation_lines" => situation_lines(world),
      "recent_turns" => recent_turns(session.id),
      "valid_skills" => Mechanics.skill_stat_map() |> Map.keys() |> Enum.sort()
    }
  end

  def format_intent_context(context) do
    [
      location_section(context),
      fixtures_section(context),
      ground_items_section(context),
      player_inventory_section(context),
      situation_section(context),
      character_section(context),
      recent_turns_section(context),
      exits_section(context),
      npcs_section(context),
      valid_skills_section(context)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp location_section(c) do
    [
      "Current location: #{c["location_name"]} (#{c["location_id"]})",
      "Location features:",
      c["location_blurb"] || "(none)"
    ]
  end

  defp fixtures_section(c) do
    [
      "Fixtures:",
      Enum.join(c["fixtures"] || [], ", ") || "none"
    ]
  end

  defp ground_items_section(c) do
    [
      "Ground items:",
      Jason.encode!(c["ground_items"] || [], pretty: true)
    ]
  end

  defp player_inventory_section(c) do
    [
      "Player inventory:",
      Jason.encode!(c["player_inventory"] || [], pretty: true)
    ]
  end

  defp situation_section(c) do
    [
      "Situation:",
      Enum.join(c["situation_lines"] || ["(none)"], "\n")
    ]
  end

  defp character_section(c) do
    [
      "Character:",
      Jason.encode!(c["character"] || %{}, pretty: true)
    ]
  end

  defp recent_turns_section(c) do
    turn_lines =
      Enum.map(c["recent_turns"] || [], fn turn ->
        "- #{turn["action"]} → #{turn["outcome"]}"
      end)

    [
      "Recent turns:",
      Enum.join(turn_lines ++ ["- none"], "\n")
    ]
  end

  defp exits_section(c) do
    exit_lines =
      Enum.map(c["exits"] || [], fn exit_id ->
        "- #{exit_id} (#{Map.get(c["exit_names"] || %{}, exit_id, exit_id)})"
      end)

    [
      "Available exits:",
      Enum.join(exit_lines ++ ["- none"], "\n")
    ]
  end

  defp npcs_section(c) do
    npc_lines =
      Enum.map(present_npcs(c), fn npc_id ->
        detail = Map.get(c["npc_details"] || %{}, npc_id, %{})
        mood = Map.get(detail, "disposition", Map.get(detail, "mood", "present"))

        "- #{npc_id}: #{Map.get(detail, "name", npc_id)} (#{Map.get(detail, "role", "present")}, mood: #{mood})"
      end)

    [
      "Present NPCs:",
      Enum.join(npc_lines ++ ["- none"], "\n")
    ]
  end

  defp valid_skills_section(c) do
    ["Valid skills: #{Enum.join(c["valid_skills"] || [], ", ")}"]
  end

  def build_gm_context(%GameSession{} = session) do
    intent = build_intent_context(session)
    world = session.world_state || %{}
    adventure_id = adventure_id(world)

    %{
      session_id: session.id,
      rules: TalesForge.Game.Prompts.load_rules(adventure_id),
      intent_context: intent,
      formatted_intent: format_intent_context(intent),
      world_state: world
    }
  end

  def format_gm_prompt(context) do
    npc_sections =
      NPC.format_gm_sections(
        context.session_id,
        present_npcs(context.intent_context)
      )

    """
    #{context.rules}

    ---

    #{context.formatted_intent}

    ---

    #{npc_sections}
    """
  end

  defp exit_names(exits) do
    Enum.into(exits, %{}, fn exit_id ->
      name = World.location(exit_id) |> then(&Map.get(&1 || %{}, "name", exit_id))
      {exit_id, name}
    end)
  end

  defp npc_details(npc_ids, npc_state) do
    Enum.into(npc_ids, %{}, fn npc_id ->
      detail = Map.get(npc_state, npc_id, %{})
      {npc_id, detail}
    end)
  end

  defp character_summary(character) do
    %{
      "name" => Map.get(character, "name"),
      "wounds" => Map.get(character, "wounds", 0),
      "location_id" => character_location_id(character),
      "coins" => Map.get(character, "coins", %{}),
      "inventory" => player_inventory(character)
    }
  end

  defp recent_turns(session_id) do
    import Ecto.Query

    Turn
    |> where([t], t.game_session_id == ^session_id)
    |> order_by([t], desc: t.turn_number)
    |> limit(2)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(fn turn ->
      outcome =
        turn.mechanical_resolution
        |> Kernel.||(%{})
        |> Map.get("outcome", "none")

      %{"action" => String.slice(turn.player_action, 0, 120), "outcome" => outcome}
    end)
  end

  # ------------------------------------------------------------------
  # Small pure accessors for the common world_state shape (raw).
  # Goal: DRY up the dozens of Map.get / get_in calls for world_state keys.
  # These are intentionally tiny, pure, and nil-safe.
  # Use these in game logic instead of raw Map.get on world_state.
  #
  # Note: build_intent_context builds a *different* enriched "intent context" map
  # (with "npc_details", "player_inventory" etc.). These accessors are for the
  # raw GameSession.world_state (and similar maps).
  # ------------------------------------------------------------------

  def character(world_state) when is_map(world_state),
    do: Map.get(world_state, "character", %{})

  def character(_), do: %{}

  def location_id(world_state) when is_map(world_state),
    do: Map.get(world_state, "location_id")

  def location_id(_), do: nil

  def location_name(world_state) when is_map(world_state),
    do: Map.get(world_state, "location_name")

  def location_name(_), do: nil

  def present_npcs(world_state) when is_map(world_state),
    do: Map.get(world_state, "present_npcs", [])

  def present_npcs(_), do: []

  def npc_state(world_state) when is_map(world_state),
    do: Map.get(world_state, "npc_state", %{})

  def npc_state(_), do: %{}

  def world_tick(world_state) when is_map(world_state),
    do: Map.get(world_state, "world_tick", 0)

  def world_tick(_), do: 0

  def situation_lines(world_state) when is_map(world_state),
    do: Map.get(world_state, "situation_lines", [])

  def situation_lines(_), do: []

  def ground_items(world_state) when is_map(world_state) do
    # ground_items often lives under the current location in world_state["locations"]
    # or passed separately; here we provide a safe top-level fallback
    Map.get(world_state, "ground_items", [])
  end

  def ground_items(_), do: []

  # Convenience for character subfields (very common)
  def player_inventory(character) when is_map(character),
    do: Map.get(character, "inventory", [])

  def player_inventory(_), do: []

  def character_location_id(character) when is_map(character),
    do: Map.get(character, "location_id")

  def character_location_id(_), do: nil

  # Convenience for the most common "where is the character?" lookup.
  def current_location_id(world_state) when is_map(world_state) do
    character_location_id(character(world_state)) || location_id(world_state)
  end

  def current_location_id(_), do: nil

  def adventure_id(world_state) when is_map(world_state),
    do: Map.get(world_state, "adventure_id")

  def adventure_id(_), do: nil

  def last_scene_location(world_state) when is_map(world_state),
    do: Map.get(world_state, "last_scene_location")

  def last_scene_location(_), do: nil

  # Simple mutators for common updates (helps keep world_state changes centralized).
  def put_character(world_state, char) when is_map(world_state) do
    Map.put(world_state, "character", char || %{})
  end

  def update_character(world_state, fun) when is_map(world_state) and is_function(fun, 1) do
    char = character(world_state)
    Map.put(world_state, "character", fun.(char) || %{})
  end
end
