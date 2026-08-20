defmodule TalesForge.Game.Prompts do
  @moduledoc false

  @global_rules_dir Path.join([:code.priv_dir(:ex_tales_forge), "rules"])
  @adventures_base Path.join([:code.priv_dir(:ex_tales_forge), "adventures"])

  def intent_system, do: read_prompt("intent_system.txt")
  def gm_system, do: read_prompt("gm_system.txt")
  def scene_system, do: read_prompt("scene_system.txt")

  def build_scene_user(%TalesForge.Schemas.GameSession{} = session) do
    TalesForge.Game.Context.format_gm_prompt(TalesForge.Game.Context.build_gm_context(session))
  end

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
end
