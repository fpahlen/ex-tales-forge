defmodule TalesForge.Game.Fronts.Move do
  @moduledoc """
  One legal move of a front (`TalesForge.Game.Fronts.Moves.apply/1`): the
  front's `runtime_state`, the `move` name, the front's pack definition
  (`pack_def`) and the `opts` (`:player_at`).
  """

  defstruct runtime_state: %{}, move: nil, pack_def: %{}, opts: []

  @type t :: %__MODULE__{
          runtime_state: map(),
          move: String.t() | nil,
          pack_def: map(),
          opts: keyword()
        }
end
