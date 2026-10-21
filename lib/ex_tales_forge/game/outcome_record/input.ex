defmodule TalesForge.Game.OutcomeRecord.Input do
  @moduledoc """
  What `TalesForge.Game.OutcomeRecord.build/1` reads: the world before the
  turn (`world_before`), the world after the board step (`world_after`), the
  played `action`, the resolved `handler` and the inventory step result
  (`inventory_result`, nil without an inventory action).
  """

  alias TalesForge.Game.Schemas.SingleAction

  @enforce_keys [:action]
  defstruct [:action, world_before: %{}, world_after: %{}, handler: %{}, inventory_result: nil]

  @type t :: %__MODULE__{
          world_before: map(),
          world_after: map(),
          action: SingleAction.t(),
          handler: map(),
          inventory_result: {:ok, term()} | {:error, String.t()} | nil
        }
end
