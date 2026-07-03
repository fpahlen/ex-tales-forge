defmodule TalesForge.NPCInitiative do
  @moduledoc """
  Bridges NPC agent initiative to Phoenix PubSub for LiveView.
  """

  alias TalesForge.NPC
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Schemas.NpcInstance

  def emit(session_id, npc_id, world_tick) when is_binary(session_id) and is_binary(npc_id) do
    case NPC.get_instance(session_id, npc_id) do
      %NpcInstance{} = inst ->
        if Map.get(inst.runtime_state, "initiative_emitted", false) do
          :ok
        else
          payload = build_payload(inst, world_tick)
          :ok = NPC.mark_initiative_emitted(inst, world_tick)
          SessionPubSub.broadcast(session_id, {:npc_initiative, payload})
          :ok
        end

      nil ->
        :ok
    end
  end

  defp build_payload(%NpcInstance{} = inst, world_tick) do
    definition = inst.personality || %{}

    %{
      session_id: inst.game_session_id,
      npc_id: inst.npc_id,
      npc_name: Map.get(definition, "name", inst.npc_id),
      text: NPC.initiative_text(inst),
      concern_priority: NPC.concern_priority(inst),
      world_tick: world_tick
    }
  end
end
