defmodule TalesForge.Agents.NPCAgent do
  @moduledoc """
  Jido agent for one present NPC in a play session.
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
      last_interaction_tick: [type: :integer, default: nil]
    ],
    signal_routes: [
      {"world.time.passed", TalesForge.Actions.NPC.ReactToTime},
      {"player.talked_to", TalesForge.Actions.NPC.OnPlayerTalked},
      {"conversation.message", TalesForge.Actions.NPC.OnOverheard}
    ]
end
