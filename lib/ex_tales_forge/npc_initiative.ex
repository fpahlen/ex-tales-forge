defmodule TalesForge.NPCInitiative do
  @moduledoc """
  An NPC speaking up about a concern that has waited long enough.

  The turn applies a `:speak_up` Intention with `speak_up/3` in its
  transaction and returns the payload in the turn's `:npc_initiatives`;
  `TalesForge.World.Instance` broadcasts it to the play page with
  `broadcast/2` once the turn has committed.
  """
  alias TalesForge.GameCharacter.Rows

  alias TalesForge.GameCharacter.Person
  alias TalesForge.NPC
  alias TalesForge.PubSub.GameSession, as: SessionPubSub

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
  payload; `:none` when the NPC has spoken already, has no line to say
  (`TalesForge.NPC.initiative_text/1`) or is not in the session.
  """
  @spec speak_up(Ecto.UUID.t(), String.t(), integer() | nil) :: {:ok, payload()} | :none
  def speak_up(session_id, npc_id, world_tick) when is_binary(session_id) and is_binary(npc_id) do
    case Rows.get(session_id, npc_id) do
      %Person{} = inst ->
        if Map.get(inst.runtime_state, "initiative_emitted", false) do
          :none
        else
          :ok = NPC.mark_initiative_emitted(inst, world_tick)
          payload(inst, NPC.initiative_text(inst), world_tick)
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

  defp payload(_inst, nil, _world_tick), do: :none

  defp payload(inst, text, world_tick) do
    {:ok,
     %{
       session_id: inst.row.game_session_id,
       npc_id: inst.npc_id,
       npc_name: Map.get(inst.personality, "name", inst.npc_id),
       text: text,
       concern_priority: NPC.concern_priority(inst),
       world_tick: world_tick
     }}
  end
end
