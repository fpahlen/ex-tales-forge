defmodule TalesForge.Game.Progression.RestAcc do
  @moduledoc false

  # The running long rest (TalesForge.Game.Progression.resolve_rest/3): the
  # character so far, the attempts and the pending skills in order, and the
  # injected rolls left.
  defstruct char: %{}, attempts: [], pending: [], rolls: %{}
end
