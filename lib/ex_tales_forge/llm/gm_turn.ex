defmodule TalesForge.LLM.GmTurn do
  @moduledoc """
  One GM call (`TalesForge.LLM.complete_turn/1`): the prompt `messages`
  (from `TalesForge.Prompt.Assemble.gm_messages/3`), the `player_action`, the
  resolved `handler`, the `turn_number` and the call `opts` (`:session_id`,
  `:on_text`, `:variant`).
  """

  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}

  @enforce_keys [:player_action, :handler]
  defstruct [:player_action, :handler, messages: [], turn_number: 0, opts: []]

  @type t :: %__MODULE__{
          messages: [map()],
          player_action: PlayerAction.t(),
          handler: HandlerResult.t(),
          turn_number: integer(),
          opts: keyword()
        }
end
