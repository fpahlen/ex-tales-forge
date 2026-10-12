defmodule TalesForge.Game.Turn.Adapters do
  @moduledoc """
  The IO of a turn (`TalesForge.Game.Turn`). The stages call these functions
  and do no other IO, so a test gives plain functions instead of mocks.

    * `npc` — the NPC reactions (`TalesForge.Game.NpcReactions.react/6`; the
      Jev call with its timeout, `NPC_REACTIONS_TIMEOUT_MS`, default 600 ms);
    * `gm` — the GM call (`TalesForge.LLM.complete_turn/5`);
    * `stream` — gets each GM text chunk (`{:turn_stream, chunk}` on the
      session topic);
    * `store` — persists the turn and signals
      (`TalesForge.Game.TurnProcessor.persist_and_signal/5`).
  """

  defstruct npc: &TalesForge.Game.NpcReactions.react/6,
            gm: &TalesForge.LLM.complete_turn/5,
            stream: &__MODULE__.broadcast/2,
            store: &TalesForge.Game.TurnProcessor.persist_and_signal/5

  @type t :: %__MODULE__{
          npc: function(),
          gm: function(),
          stream: (String.t(), String.t() -> term()),
          store: function()
        }

  @doc "The default `stream` adapter: broadcasts the chunk on the session topic."
  @spec broadcast(String.t(), String.t()) :: :ok | {:error, term()}
  def broadcast(session_id, chunk),
    do: TalesForge.PubSub.GameSession.broadcast(session_id, {:turn_stream, chunk})
end
