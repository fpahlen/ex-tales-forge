defmodule TalesForge.Actions.Character.OnOverheard do
  @moduledoc """
  A present NPC overheard what the acting character said or did: it
  remembers the first 100 characters. The turn applies it
  (`TalesForge.Game.Turn.Intentions.apply_all/2`).
  """

  alias TalesForge.GameCharacter.Signals.Turn
  alias TalesForge.Intention

  @doc "The Intention of NPC `npc_id` when it overheard `message` in `turn`."
  @spec intentions(String.t(), Turn.t()) :: [Intention.t()]
  def intentions(npc_id, %Turn{} = turn) do
    message = String.trim(turn.raw_action || "")
    summary = "Overheard player: #{String.slice(message, 0, 100)}"
    [Intention.system(npc_id, {:remember, summary}, Turn.world_tick(turn))]
  end
end
