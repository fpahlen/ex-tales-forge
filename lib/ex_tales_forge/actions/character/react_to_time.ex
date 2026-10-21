defmodule TalesForge.Actions.Character.ReactToTime do
  @moduledoc """
  Time passed for a present NPC: its concern waits `delta_ticks` longer
  (`{:wait, delta}`), and it speaks up when the concern has waited long
  enough (`:speak_up`). The turn applies both
  (`TalesForge.Game.Turn.Intentions.apply_all/2`).
  """

  alias TalesForge.GameCharacter.Signals.Turn
  alias TalesForge.Intention

  @doc "The Intentions of NPC `npc_id` when the time of `turn` passed."
  @spec intentions(String.t(), Turn.t()) :: [Intention.t()]
  def intentions(npc_id, %Turn{} = turn) do
    tick = Turn.world_tick(turn)

    [
      Intention.system(npc_id, {:wait, Turn.tick_delta(turn)}, tick),
      Intention.system(npc_id, :speak_up, tick)
    ]
  end
end
