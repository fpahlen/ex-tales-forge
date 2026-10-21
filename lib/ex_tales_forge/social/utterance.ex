defmodule TalesForge.Social.Utterance do
  @moduledoc """
  One line spoken in a place (`docs/design-social-layer.md` §2.1): the
  speaker, the `voice` (`:whisper`, `:talk`, `:shout` or `:none` for no
  speech), the words, the room's noise (`ambient_db`, default 50 dB), the
  addressee and the turn.
  """

  @enforce_keys [:speaker_id, :voice]
  defstruct [:speaker_id, :voice, text: "", ambient_db: 50, addressee_id: nil, turn_number: 0]

  @type voice :: :whisper | :talk | :shout | :none

  @type t :: %__MODULE__{
          speaker_id: String.t(),
          voice: voice(),
          text: String.t(),
          ambient_db: number(),
          addressee_id: String.t() | nil,
          turn_number: non_neg_integer()
        }
end
