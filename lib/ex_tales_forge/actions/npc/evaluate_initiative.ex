defmodule TalesForge.Actions.NPC.EvaluateInitiative do
  @moduledoc false

  use Jido.Action,
    name: "npc_evaluate_initiative",
    description: "Rule-based v1 initiative check from concern priority",
    schema: []

  alias TalesForge.NPC

  @impl true
  def run(_params, %{state: state}) do
    %{initiative_pending: pending?, concern_priority: priority} =
      NPC.evaluate_initiative(state.session_id, state.npc_id)

    {:ok, %{initiative_pending: pending?, concern_priority: priority}}
  end
end
