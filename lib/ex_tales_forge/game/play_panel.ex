defmodule TalesForge.Game.PlayPanel do
  @moduledoc """
  Pure read models of the play screen panels: the people present, the
  character quick stats and the coin line. TalesForgeWeb.PlayComponents
  delegates here (and keeps the doctests), and `TalesForge.Playtest.PlayerView`
  calls this module so the domain layer does not reference the web layer.
  """

  alias TalesForge.Game.Inventory

  @doc "The people of the Present panel. See TalesForgeWeb.PlayComponents.present_npcs/1."
  def present_npcs(world_state) when is_map(world_state) do
    npc_state = Map.get(world_state, "npc_state") || %{}
    npc_ids = living_present(world_state, npc_state)
    foe_ids = minor_foes_here(npc_state, npc_ids, world_state["location_id"])
    Enum.map(npc_ids ++ foe_ids, &person(&1, Map.get(npc_state, &1) || %{}))
  end

  defp living_present(world_state, npc_state) do
    world_state
    |> Map.get("present_npcs", [])
    |> List.wrap()
    |> Enum.reject(&(get_in(npc_state, [&1, "vitality"]) == "dead"))
  end

  defp minor_foes_here(npc_state, npc_ids, location_id) do
    npc_state
    |> Enum.filter(&minor_foe_here?(&1, npc_ids, location_id))
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp minor_foe_here?({id, npc}, npc_ids, location_id) do
    is_map(npc) and npc["minor"] == true and npc["vitality"] != "dead" and
      id not in npc_ids and npc["location_id"] == location_id
  end

  defp person(npc_id, detail) do
    %{
      id: npc_id,
      name: Map.get(detail, "name", npc_id),
      role: Map.get(detail, "role", "present"),
      concern_priority: Map.get(detail, "concern_priority", 0),
      portrait_url: Map.get(detail, "portrait_url"),
      wounds_label: wounds_label(detail)
    }
  end

  defp wounds_label(%{"vitality" => "dead"}), do: "dead"

  defp wounds_label(%{"wounds" => wounds} = detail) when is_integer(wounds) do
    max = detail["wound_max"] || 3

    case {detail["vitality"], wounds} do
      {"down", _} -> "down · #{wounds}/#{max} wounds"
      {_, 0} -> nil
      _ -> "#{wounds}/#{max} wounds"
    end
  end

  defp wounds_label(_detail), do: nil

  @doc "The wounds, vitality and coins line of the character."
  def quick_stats(character) when is_map(character) do
    wounds = Map.get(character, "wounds", 0)
    wound_max = Map.get(character, "wound_max", 3)
    coins = format_coins(Map.get(character, "coins", %{}))
    wounds_part = "#{wounds}/#{wound_max} wounds · #{coins}"

    case Map.get(character, "vitality", "ok") do
      "ok" -> wounds_part
      vitality -> "#{vitality} · #{wounds_part}"
    end
  end

  @doc "The coins as gold, silver and copper. See TalesForgeWeb.PlayComponents.format_coins/1."
  def format_coins(coins) when is_map(coins) do
    normal = Inventory.normalize_coins(coins)

    "#{Map.get(normal, "gold", 0)}g #{Map.get(normal, "silver", 0)}s #{Map.get(normal, "copper", 0)}c"
  end

  def format_coins(_), do: "—"
end
