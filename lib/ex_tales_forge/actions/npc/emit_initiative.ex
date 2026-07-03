defmodule TalesForge.Actions.NPC.EmitInitiative do
  @moduledoc false

  use Jido.Action,
    name: "npc_emit_initiative",
    description: "Broadcast proactive NPC dialogue when initiative triggers",
    schema: []

  alias TalesForge.NPCInitiative

  @impl true
  def run(_params, %{state: state, signal: signal}) do
    if state.initiative_pending and not state.initiative_emitted do
      world_tick = signal_field(signal, "world_tick", 0)
      :ok = NPCInitiative.emit(state.session_id, state.npc_id, world_tick)
      {:ok, %{initiative_emitted: true, last_initiative_tick: world_tick}}
    else
      {:ok, %{}}
    end
  end

  defp signal_field(signal, key, default) do
    signal.data
    |> normalize_keys()
    |> Map.get(key, default)
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
