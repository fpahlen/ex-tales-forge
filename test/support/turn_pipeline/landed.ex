defmodule TalesForge.TurnPipeline.Landed do
  @moduledoc """
  The `pending_on` keys of the turn pipeline fixtures that this branch
  implements (`test/fixtures/turn_pipeline/README.md`). A fixture runs in CI
  when all its `pending_on` keys are in this list. Each migration PR adds its
  key here when it turns its fixtures on.
  """

  @keys ~w(replay_harness outcome_record)

  @doc "The landed keys."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "True when every key in the fixture's `pending_on` has landed."
  @spec active?(map()) :: boolean()
  def active?(item), do: Enum.all?(item["pending_on"], &(&1 in @keys))
end
