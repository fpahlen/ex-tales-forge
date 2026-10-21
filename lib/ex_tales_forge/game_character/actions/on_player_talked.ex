defmodule TalesForge.GameCharacter.Actions.OnPlayerTalked do
  @moduledoc """
  The acting character spoke to this NPC: it remembers the words and warms
  a little to the speaker. The turn applies both
  (`TalesForge.Game.Turn.Intentions.apply_all/2`).
  """

  alias TalesForge.GameCharacter.Signals.Turn
  alias TalesForge.Intention

  @relationship_bump 0.05

  @doc "The Intentions of NPC `npc_id` when the player of `turn` spoke to it."
  @spec intentions(String.t(), Turn.t()) :: [Intention.t()]
  def intentions(npc_id, %Turn{} = turn) do
    tick = Turn.world_tick(turn)
    summary = "Player spoke to me: #{String.slice(turn.raw_action || "", 0, 120)}"

    [
      Intention.system(npc_id, {:remember, summary}, tick),
      Intention.system(npc_id, {:warm, @relationship_bump}, tick)
    ]
  end
end
