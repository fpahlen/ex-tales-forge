defmodule TalesForge.NPCSignals.Turn do
  @moduledoc """
  A finished turn as `TalesForge.NPCSignals.emit_turn_signals/1` sees it:
  the session, the world after the turn, the action handler, the player's
  words and, when known, the world before the turn (for the tick delta).
  """

  @enforce_keys [:session_id, :world_state, :handler, :raw_action]
  defstruct [:session_id, :world_state, :handler, :raw_action, world_before: nil]

  @type t :: %__MODULE__{
          session_id: String.t(),
          world_state: map(),
          handler: map(),
          raw_action: String.t() | nil,
          world_before: map() | nil
        }
end
