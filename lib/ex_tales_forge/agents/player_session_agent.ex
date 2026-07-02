defmodule TalesForge.Agents.PlayerSessionAgent do
  @moduledoc """
  Owns hot state for one active play session.
  """
  use Jido.Agent,
    name: "player_session",
    description: "Tales Forge player session agent",
    schema: [
      session_id: [type: :string, required: true],
      turn_count: [type: :integer, default: 0],
      entries: [type: {:list, :map}, default: []]
    ],
    signal_routes: [
      {"player.message", TalesForge.Actions.PlayerMessage}
    ]
end
