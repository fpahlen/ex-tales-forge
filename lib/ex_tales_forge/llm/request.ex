defmodule TalesForge.LLM.Request do
  @moduledoc """
  One model call on its way through `TalesForge.LLM`: the model, the
  messages, the temperature and the call options (`:tier`, `:session_id`,
  `:turn_number`, `:max_tokens`, `:response_format`, `:stream`, `:on_text`,
  `:variant`, ...).
  """

  @enforce_keys [:model, :messages, :temperature]
  defstruct [:model, :messages, :temperature, opts: []]

  @type t :: %__MODULE__{
          model: String.t(),
          messages: [map()],
          temperature: number(),
          opts: keyword()
        }
end
