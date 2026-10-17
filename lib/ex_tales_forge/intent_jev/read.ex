defmodule TalesForge.IntentJev.Read do
  @moduledoc """
  One player message read by Jev in `TalesForge.IntentJev`: what was read
  (`context`, `raw_action`, the decision `opts`) and Jev's answer
  (`reading`, `candidates`, `latency_ms`).
  """

  @enforce_keys [:context, :raw_action]
  defstruct [:context, :raw_action, :reading, opts: [], candidates: [], latency_ms: 0]

  @type t :: %__MODULE__{
          context: map(),
          raw_action: String.t(),
          opts: keyword(),
          reading: TalesForge.Game.JevIntent.reading() | nil,
          candidates: [TalesForge.Game.JevIntent.candidate()],
          latency_ms: non_neg_integer()
        }
end
