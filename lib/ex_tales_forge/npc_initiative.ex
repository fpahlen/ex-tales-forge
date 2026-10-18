defmodule TalesForge.NPCInitiative do
  @moduledoc """
  An NPC speaking up about a concern that has waited long enough.

  The turn applies a `:speak_up` Intention with `speak_up/3` in its
  transaction and returns the payload in the turn's `:npc_initiatives`;
  `TalesForge.World.Instance` broadcasts it to the play page with
  `broadcast/2` once the turn has committed.
  """

  alias TalesForge.NPC
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Schemas.NpcInstance

  @typedoc "What the play page shows when an NPC speaks up."
  @type payload :: %{
          session_id: Ecto.UUID.t(),
          npc_id: String.t(),
          npc_name: String.t(),
          text: String.t(),
          concern_priority: integer(),
          world_tick: integer() | nil
        }

  @doc """
  Marks the NPC's initiative as spoken at `world_tick` and returns its
  payload; `:none` when the NPC has spoken already or has no instance.
  """
  @spec speak_up(Ecto.UUID.t(), String.t(), integer() | nil) :: {:ok, payload()} | :none
  def speak_up(session_id, npc_id, world_tick) when is_binary(session_id) and is_binary(npc_id) do
    case NPC.get_instance(session_id, npc_id) do
      %NpcInstance{} = inst ->
        if Map.get(inst.runtime_state, "initiative_emitted", false) do
          :none
        else
          payload = build_payload(inst, world_tick)
          :ok = NPC.mark_initiative_emitted(inst, world_tick)
          {:ok, payload}
        end

      nil ->
        :none
    end
  end

  @doc "Sends an initiative payload to the session's play page."
  @spec broadcast(Ecto.UUID.t(), payload()) :: :ok
  def broadcast(session_id, payload) do
    SessionPubSub.broadcast(session_id, {:npc_initiative, payload})
    :ok
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
