defmodule TalesForge.NPCSignals.Delivery do
  @moduledoc "One signal of `TalesForge.NPCSignals` to one NPC agent: the session, the NPC and the signal type."

  @enforce_keys [:session_id, :npc_id, :type]
  defstruct [:session_id, :npc_id, :type]

  @type t :: %__MODULE__{session_id: String.t(), npc_id: String.t(), type: String.t()}
end
