defmodule TalesForge.Social.Listener do
  @moduledoc """
  A character who may hear an utterance (`docs/design-social-layer.md`
  §2.1): its id, its distance to the speaker in metres (default 3 m, the
  decided distance of everyone but the addressee) and its hearing modifier
  in dB (`TalesForge.Social.Hearing.modifier/1`).
  """

  @enforce_keys [:character_id]
  defstruct [:character_id, distance_m: 3.0, hearing_db: 0]

  @type t :: %__MODULE__{character_id: String.t(), distance_m: number(), hearing_db: integer()}
end
