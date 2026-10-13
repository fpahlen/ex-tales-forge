defmodule TalesForge.Canon.SeedPatch do
  @moduledoc """
  The proposed seed change for one "Add to canon" decision, as text for a
  pull request. It names the pack file and the change, and it copies only
  the session data of the difference. The app never writes seed files: a
  person opens the pull request.
  """

  alias TalesForge.Canon.Difference

  @doc "Returns the proposed patch for the difference in the adventure."
  @spec propose(Difference.t(), String.t() | nil) :: String.t()
  def propose(%Difference{} = d, adventure_id) do
    dir = "priv/adventures/#{adventure_id || "<adventure>"}"
    {file, change} = change(d, dir)

    """
    File: #{file}
    Change (#{d.kind}, #{d.entity_id}):
    #{change}
    """
  end

  defp change(%Difference{kind: :new_place} = d, dir) do
    {"#{dir}/world/#{d.entity_id}.md",
     "Add the place #{d.entity_id}. Name: #{d.session["name"]}. Exits: #{exits(d.session)}."}
  end

  defp change(%Difference{kind: :changed_place} = d, dir) do
    {"#{dir}/world/#{d.entity_id}.md",
     "Set name #{inspect(d.seed["name"])} → #{inspect(d.session["name"])}. " <>
       "Set exits #{exits(d.seed)} → #{exits(d.session)}."}
  end

  defp change(%Difference{kind: :new_entity} = d, dir) do
    {"#{dir}/npcs/#{d.entity_id}.json",
     "Add the NPC #{d.entity_id}. Name: #{d.session["name"]}. Fill in the NPC fields from the session."}
  end

  defp change(%Difference{} = d, dir) do
    fact = %{"kind" => d.session["kind"] || "fact", "text" => d.session["text"]}

    {"#{dir}/world_agents.json",
     "Add to the \"facts\" of entity #{inspect(d.entity_id)}:\n" <>
       Jason.encode!(fact, pretty: true)}
  end

  defp exits(%{"exits" => exits}) when is_list(exits), do: "[" <> Enum.join(exits, ", ") <> "]"
  defp exits(_), do: "[]"
end
