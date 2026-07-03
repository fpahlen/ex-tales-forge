defmodule TalesForge.Actions.NPC.AdjustConcern do
  @moduledoc false

  use Jido.Action,
    name: "npc_adjust_concern",
    description: "Rule-based concern priority escalation as in-game time passes",
    schema: [
      delta_ticks: [type: :integer, default: 1]
    ]

  alias TalesForge.NPC

  @impl true
  def run(%{delta_ticks: delta_ticks}, %{state: state}) do
    case NPC.adjust_concern(state.session_id, state.npc_id, delta_ticks) do
      {:ok, concern_state} ->
        {:ok, concern_state}

      :ok ->
        {:ok, %{}}
    end
  end
end
