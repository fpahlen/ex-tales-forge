defmodule TalesForge.Actions.NPC.UpdateMemory do
  @moduledoc false

  use Jido.Action,
    name: "npc_update_memory",
    description: "Persist a short memory summary for an NPC",
    schema: [
      summary: [type: :string, required: true],
      world_tick: [type: :integer, required: true]
    ]

  alias TalesForge.NPC

  @impl true
  def run(%{summary: summary, world_tick: world_tick}, %{state: state}) do
    :ok = NPC.record_memory(state.session_id, state.npc_id, summary, world_tick)
    {:ok, %{last_memory_summary: summary}}
  end
end
