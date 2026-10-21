defmodule TalesForge.Social.Clarity do
  @moduledoc """
  How well one listener heard an utterance (`docs/design-social-layer.md`
  §2.3): the `level` (`:clear`, `:partial` or `:none`), the signal-to-noise
  ratio at her ear (`snr_db`, nil without speech) and `keep`, the share of
  words heard (1.0 clear, 0.3..0.9 partial, 0.0 none).
  """

  defstruct level: :none, snr_db: nil, keep: 0.0

  @type level :: :clear | :partial | :none
  @type t :: %__MODULE__{level: level(), snr_db: float() | nil, keep: float()}
end
