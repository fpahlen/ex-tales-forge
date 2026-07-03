defmodule TalesForge.Actions.NPC.EvaluateInitiative do
  @moduledoc false

  use Jido.Action,
    name: "npc_evaluate_initiative",
    description: "Rule-based v1 initiative check from concern priority",
    schema: []

  @impl true
  def run(_params, %{state: state}) do
    pending? = Map.get(state, :initiative_ready?, false) and not state.initiative_emitted

    {:ok,
     %{
       initiative_pending: pending?,
       concern_priority: Map.get(state, :concern_priority, 0)
     }}
  end
end
