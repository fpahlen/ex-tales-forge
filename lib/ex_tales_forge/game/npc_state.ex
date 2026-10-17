defmodule TalesForge.Game.NpcState do
  @moduledoc """
  Pure helpers on `world_state["npc_state"]`, the per-NPC combat state. A
  leaf module: the NPC code (`TalesForge.NPC`,
  `TalesForge.Game.NpcReactions`) gets the npc_state passed in and reads it
  here, so it does not call back into `TalesForge.Game.Combat` or
  `TalesForge.Game.Context`, which reach the turn processor.
  """

  @combat_keys ~w(wounds wound_max vitality minor)

  @doc """
  Keeps the combat keys (`wounds`, `wound_max`, `vitality`, `minor`) and the
  minor foes of `before` in the `after_state` npc_state map. The board
  rebuilds npc_state from the NPC instances each turn, so this step carries
  the session combat state over.
  """
  @spec carry(map(), map()) :: map()
  def carry(before, after_state) do
    before = before || %{}

    Enum.reduce(before, after_state || %{}, fn {id, npc}, acc ->
      kept = Map.take(npc || %{}, @combat_keys)

      cond do
        npc["minor"] == true -> Map.put(acc, id, npc)
        kept == %{} -> acc
        Map.has_key?(acc, id) -> Map.update!(acc, id, &Map.merge(&1, kept))
        true -> acc
      end
    end)
  end

  @doc "True when the npc_state marks `npc_id` as dead."
  @spec dead?(map(), String.t()) :: boolean()
  def dead?(npc_state, npc_id) when is_map(npc_state),
    do: get_in(npc_state, [npc_id, "vitality"]) == "dead"

  def dead?(_npc_state, _npc_id), do: false
end
