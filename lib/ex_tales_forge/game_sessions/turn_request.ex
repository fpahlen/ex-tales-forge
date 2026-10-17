defmodule TalesForge.GameSessions.TurnRequest do
  @moduledoc """
  One player message on its way from `TalesForge.GameSessions.submit_message/3`
  to the turn job: the session, the player's words, the submit options
  (`:option_id`, `:clarification_id`, `:founder`, ...) and the intent context
  once it is built.
  """

  @enforce_keys [:session, :raw_action, :opts]
  defstruct [:session, :raw_action, :opts, context: nil]

  @type t :: %__MODULE__{
          session: TalesForge.Schemas.GameSession.t(),
          raw_action: String.t(),
          opts: keyword(),
          context: map() | nil
        }
end
