defmodule TalesForge.Game.Catalogue.Act do
  @moduledoc """
  One catalogue v2 action (`TalesForge.Game.Catalogue.apply/2`): the
  resolved `handler`, the player's words (`text`) and the target NPC's
  profile (`npc`, for `give`).
  """

  defstruct handler: nil, text: "", npc: nil

  @type t :: %__MODULE__{handler: struct() | map() | nil, text: String.t(), npc: map() | nil}
end
