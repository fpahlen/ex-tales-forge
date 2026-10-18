defmodule TalesForge.Agents.NPCAgent do
  @moduledoc """
  Jido agent for one present NPC in a play session. Since refactor step 10e
  it gets no signals: what it handled comes in as Intentions that the turn
  applies (`TalesForge.NPCSignals`). Refactor step 10f, PR 2, deletes it.

  Core runtime. Ecto only.
  """
  use Jido.Agent,
    name: "npc",
    description: "Tales Forge NPC runtime agent",
    schema: [
      session_id: [type: :string, required: true],
      npc_id: [type: :string, required: true],
      location_id: [type: :string, default: nil],
      mood: [type: :string, default: "neutral"],
      relationship_score: [type: :float, default: 0.0],
      concern_priority: [type: :integer, default: 0],
      concern_wait_ticks: [type: :integer, default: 0],
      initiative_pending: [type: :boolean, default: false],
      initiative_emitted: [type: :boolean, default: false],
      last_initiative_tick: [type: :integer, default: nil],
      last_interaction_tick: [type: :integer, default: nil]
    ]
end
