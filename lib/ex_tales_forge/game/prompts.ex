defmodule TalesForge.Game.Prompts do
  @moduledoc false

  @rules_dir Path.join([:code.priv_dir(:ex_tales_forge), "rules"])

  def intent_system, do: read_prompt("intent_system.txt")
  def gm_system, do: read_prompt("gm_system.txt")
  def scene_system, do: read_prompt("scene_system.txt")

  def load_rules do
    @rules_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.sort()
    |> Enum.map_join("\n\n", fn file ->
      name = Path.basename(file, ".md")
      content = File.read!(Path.join(@rules_dir, file))
      "### #{name}\n\n#{content}"
    end)
  end

  defp read_prompt(name) do
    path = Path.join(:code.priv_dir(:ex_tales_forge), "prompts/#{name}")
    File.read!(path)
  end
end
