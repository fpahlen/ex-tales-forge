defmodule TalesForge.Actions.NPC.OnPlayerTalked do
  @moduledoc false

  use Jido.Action,
    name: "npc_on_player_talked",
    description: "Record player dialogue and warm relationship on direct speech",
    schema: []

  alias TalesForge.Actions.NPC.UpdateMemory
  alias TalesForge.NPC

  @concern_relationship_bump 0.05

  @impl true
  def run(_params, context) do
    %{session_id: session_id, npc_id: npc_id} = context.state
    data = normalize_keys(context.signal.data)

    player_text = Map.get(data, "player_text", "")
    world_tick = Map.get(data, "world_tick", 0)

    summary = "Player spoke to me: #{String.slice(player_text, 0, 120)}"

    with {:ok, _} <- UpdateMemory.run(%{summary: summary, world_tick: world_tick}, context),
         {:ok, relationship_score} <-
           NPC.bump_relationship(session_id, npc_id, @concern_relationship_bump) do
      {:ok, %{last_interaction_tick: world_tick, relationship_score: relationship_score}}
    end
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
