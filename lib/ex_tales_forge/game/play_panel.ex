defmodule TalesForge.Game.PlayPanel do
  @moduledoc """
  Pure read models of the play screen panels: the people present, the
  character quick stats and the coin line. TalesForgeWeb.PlayComponents
  delegates here (and keeps the doctests), and `TalesForge.Playtest.PlayerView`
  calls this module so the domain layer does not reference the web layer.
  """

  alias TalesForge.Game.Cast
  alias TalesForge.Game.Inventory

  @doc """
  The people of the Present panel, from the world and the session's cast
  (`TalesForge.Game.Cast`). See TalesForgeWeb.PlayComponents.present_npcs/2.
  """
  def present_npcs(world_state, cast) when is_map(world_state) and is_map(cast) do
    listed = world_state |> Map.get("present_npcs", []) |> List.wrap()
    living = Enum.reject(listed, &Cast.dead?(cast, &1))
    others = Cast.others_here(cast, world_state["location_id"], listed)
    Enum.map(living ++ others, &person(&1, cast[&1]))
  end

  defp person(npc_id, nil), do: person(npc_id, %TalesForge.GameCharacter{slug: npc_id})

  defp person(npc_id, member) do
    detail = Cast.details(member)

    %{
      id: npc_id,
      name: detail["name"],
      role: detail["role"],
      concern_priority: detail["concern_priority"],
      portrait_url: detail["portrait_url"],
      wounds_label: wounds_label(member)
    }
  end

  defp wounds_label(%{vitality: "dead"}), do: "dead"

  defp wounds_label(%{wounds: wounds} = member) when is_integer(wounds) do
    max = member.wound_max || 3

    case {member.vitality, wounds} do
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
