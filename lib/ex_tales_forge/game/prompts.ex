defmodule TalesForge.Game.Prompts do
  @moduledoc false

  @global_rules_dir Path.join([:code.priv_dir(:ex_tales_forge), "rules"])
  @adventures_base Path.join([:code.priv_dir(:ex_tales_forge), "adventures"])

  def intent_system, do: read_prompt("intent_system.txt")
  def gm_system, do: read_prompt("gm_system.txt")
  def scene_system, do: read_prompt("scene_system.txt")

  @doc """
  Load rules for the global system (default, used for legacy / non-pack adventures).
  """
  def load_rules do
    load_rules_from_dir(@global_rules_dir)
  end

  @doc """
  Load rules for a specific adventure, if it has its own pack in priv/adventures/<adventure_id>/rules.

  Falls back to global rules if no pack-specific rules/ directory is found.
  This is the key to making fully self-contained game packs (e.g. "Drakar och Demoner")
  actually drive the GM prompts.
  """
  def load_rules(adventure_id) when is_binary(adventure_id) do
    pack_rules_dir = Path.join([@adventures_base, adventure_id, "rules"])

    if File.dir?(pack_rules_dir) and has_markdown?(pack_rules_dir) do
      load_rules_from_dir(pack_rules_dir)
    else
      load_rules()
    end
  end

  def load_rules(_other), do: load_rules()

  @doc """
  Load rules from an explicit directory (used by the Importer and for pack-aware sessions).
  Walks recursively and concatenates all .md files, sorted by path.
  """
  def load_rules_from_dir(dir) when is_binary(dir) do
    Path.wildcard(Path.join(dir, "**/*.md"))
    |> Enum.sort()
    |> Enum.map_join("\n\n---\n\n", fn path ->
      rel = Path.relative_to(path, dir)
      content = File.read!(path)
      "### #{rel}\n\n#{content}"
    end)
  end

  defp has_markdown?(dir) do
    Path.wildcard(Path.join(dir, "**/*.md")) != []
  end

  defp read_prompt(name) do
    path = Path.join(:code.priv_dir(:ex_tales_forge), "prompts/#{name}")
    File.read!(path)
  end

  # ------------------------------------------------------------------
  # Centralized prompt construction + JSON contracts (DRY)
  #
  # Base system instructions live in priv/prompts/*.txt (and rules/*.md).
  # All runtime assembly of the *user* message (including dynamic context,
  # validated actions, and schema instructions) is built here so there is
  # one place to evolve "how we talk to the models".
  # ------------------------------------------------------------------

  @intent_schema %{
    "type" => "object",
    "required" => ["overall_intent", "actions"],
    "properties" => %{
      "overall_intent" => %{"type" => "string"},
      "actions" => %{"type" => "array", "minItems" => 1},
      "primary_index" => %{"type" => "integer"},
      "confidence" => %{"type" => "number"},
      "needs_clarification" => %{"type" => "boolean"},
      "clarification_question" => %{"type" => ["string", "null"]},
      "clarification_options" => %{"type" => "array"}
    }
  }

  @scene_schema %{
    "type" => "object",
    "required" => ["location_name", "narrative"],
    "properties" => %{
      "location_name" => %{"type" => "string"},
      "narrative" => %{"type" => "string"}
    }
  }

  @gm_schema %{
    "type" => "object",
    "required" => ["narrative"],
    "properties" => %{
      "narrative" => %{"type" => "string"},
      "mechanical_resolution" => %{"type" => "object"},
      "state_updates" => %{"type" => "array"},
      "npc_memory_updates" => %{"type" => "array"},
      "overlay_deltas" => %{"type" => "object"},
      "context_summary" => %{"type" => ["string", "null"]}
    }
  }

  def intent_schema, do: @intent_schema
  def scene_schema, do: @scene_schema
  def gm_schema, do: @gm_schema

  @doc """
  Build the complete user message for Tier-1 intent extraction.
  Centralizes the context formatting + "Player text to extract" suffix.
  """
  def build_intent_user(context, raw_action) when is_map(context) and is_binary(raw_action) do
    TalesForge.Game.Context.format_intent_context(context) <>
      "\n\nPlayer text to extract (treat as in-character action only):\n" <>
      String.trim(raw_action)
  end

  @doc """
  Build the final user prompt passed to the Tier-2 GM for a turn.

  Takes the base (already containing rules + formatted intent + NPC sections)
  and appends the machine-readable validated action + handler result.
  Previously this concatenation lived inside LLM.complete_turn.
  """
  def build_gm_user(base_user, player_action, handler, turn_number)
      when is_binary(base_user) do
    base_user <>
      "\n\nValidated player action (turn #{turn_number}):\n" <>
      Jason.encode!(TalesForge.Game.Schemas.PlayerAction.encode(player_action), pretty: true) <>
      "\n\nAction handler result:\n" <>
      Jason.encode!(handler_payload(handler), pretty: true)
  end

  defp handler_payload(%TalesForge.Game.Schemas.HandlerResult{} = h) do
    %{
      "handler" => h.handler,
      "skill" => h.skill,
      "target" => h.target,
      "notes" => h.notes
    }
  end

  # For scene we currently pass the formatted GM prompt as-is.
  def build_scene_user(base_user) when is_binary(base_user), do: base_user

  @doc """
  Append the 'return only JSON matching this schema' instruction.
  The schema contracts now live here (next to the system prompt loaders).
  """
  def with_json_schema(user, schema) when is_binary(user) and is_map(schema) do
    user <>
      "\n\nReturn JSON matching this schema:\n" <>
      Jason.encode!(schema, pretty: true)
  end

  @doc """
  The retry instruction used when the first LLM response was not valid JSON.
  """
  def json_retry_prefix do
    "Your previous response was invalid. Return ONLY valid JSON matching the schema.\n\n"
  end
end
