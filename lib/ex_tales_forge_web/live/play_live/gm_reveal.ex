defmodule TalesForgeWeb.PlayLive.GmReveal do
  @moduledoc """
  The pacing of the streamed GM narration on the play page
  (docs/design-gm-streaming.md): the minimum "GM thinking" pause and the
  slowest reveal speed. PlayLive reads it at mount, and the `.GmReveal` hook
  (in the play components' GM streaming block) gets it as `data-`
  attributes, so a config change shows on the next page load.
  """

  alias TalesForge.Config

  @enforce_keys [:min_delay_ms, :min_ms_per_char]
  defstruct [:min_delay_ms, :min_ms_per_char]

  @type t :: %__MODULE__{min_delay_ms: integer(), min_ms_per_char: integer()}

  @doc "Today's pacing, from `GM_MIN_DELAY_MS` and `GM_REVEAL_MIN_MS_PER_CHAR`."
  @spec from_config() :: t()
  def from_config do
    %__MODULE__{
      min_delay_ms: Config.gm_min_delay_ms(),
      min_ms_per_char: Config.gm_reveal_min_ms_per_char()
    }
  end
end
