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
    location_id = Map.get(world, "location_id", "weary_pilgrim")
    location = World.runtime_location(world, location_id)
    present_npcs = Map.get(world, "present_npcs", ["marta_kellen"])
    npc_state = Map.get(world, "npc_state", World.npcs())
    character = Map.get(world, "character", %{})
    npc_stock = NPC.stock_map(session.id, present_npcs)

    %{
      "location_id" => location_id,
      "location_name" => Map.get(world, "location_name", Map.get(location, "name", location_id)),
      "location_blurb" => Map.get(location, "blurb", ""),
      "fixtures" => Map.get(location, "fixtures", []),
      "ground_items" => Map.get(location, "ground_items", []),
      "npc_stock" => npc_stock,
      "exits" => Map.get(location, "exits", []),
      "exit_names" => exit_names(Map.get(location, "exits", [])),
      "present_npcs" => present_npcs,
      "npc_details" => npc_details(present_npcs, npc_state),
      "character" => character_summary(character),
      "player_inventory" => Map.get(character, "inventory", []),
      "situation_lines" => Map.get(world, "situation_lines", []),
      "recent_turns" => recent_turns(session.id),
      "valid_skills" => Mechanics.skill_stat_map() |> Map.keys() |> Enum.sort()
    }
  end

  def format_intent_context(context) do
    exit_lines =
      Enum.map(context["exits"], fn exit_id ->
        "- #{exit_id} (#{Map.get(context["exit_names"], exit_id, exit_id)})"
      end)

    npc_lines =
      Enum.map(context["present_npcs"], fn npc_id ->
        detail = Map.get(context["npc_details"], npc_id, %{})
        mood = Map.get(detail, "disposition", Map.get(detail, "mood", "present"))

        "- #{npc_id}: #{Map.get(detail, "name", npc_id)} (#{Map.get(detail, "role", "present")}, mood: #{mood})"
      end)

    turn_lines =
      Enum.map(context["recent_turns"], fn turn ->
        "- #{turn["action"]} → #{turn["outcome"]}"
      end)

    [
      "Current location: #{context["location_name"]} (#{context["location_id"]})",
      "Location features:",
      context["location_blurb"] || "(none)",
      "Fixtures:",
      Enum.join(context["fixtures"] || [], ", ") || "none",
      "Ground items:",
      Jason.encode!(context["ground_items"] || [], pretty: true),
      "Player inventory:",
      Jason.encode!(context["player_inventory"] || [], pretty: true),
      "Situation:",
      Enum.join(context["situation_lines"] || ["(none)"], "\n"),
      "Character:",
      Jason.encode!(context["character"] || %{}, pretty: true),
      "Recent turns:",
      Enum.join(turn_lines ++ ["- none"], "\n"),
      "Available exits:",
      Enum.join(exit_lines ++ ["- none"], "\n"),
      "Present NPCs:",
      Enum.join(npc_lines ++ ["- none"], "\n"),
      "Valid skills: #{Enum.join(context["valid_skills"], ", ")}"
    ]
    |> Enum.join("\n")
  end

  def build_gm_context(%GameSession{} = session) do
    intent = build_intent_context(session)
    world = session.world_state || %{}
    adventure_id = Map.get(world, "adventure_id")

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
        Map.get(context.intent_context, "present_npcs", [])
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
      "location_id" => Map.get(character, "location_id"),
      "coins" => Map.get(character, "coins", %{}),
      "inventory" => Map.get(character, "inventory", [])
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
end
