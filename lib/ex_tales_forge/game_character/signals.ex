defmodule TalesForge.GameCharacter.Signals do
  @moduledoc """
  What a finished turn means for the present NPCs, as Intentions
  (`TalesForge.Intention`, `by: :system`) for the turn to apply
  (`TalesForge.Game.Turn.Intentions.apply_all/2`), in this order:

    1. time passed, for every present NPC (`GameCharacter.Actions.ReactToTime`);
    2. the player spoke to a present NPC (`GameCharacter.Actions.OnPlayerTalked`);
    3. the other present NPCs overheard it (`GameCharacter.Actions.OnOverheard`),
       unless the turn was quiet (wait, train) or had no words.

  Before refactor step 10e these were Jido signals to the NPC agents, which
  wrote after the commit; a missing agent dropped its signal.
  """

  alias TalesForge.GameCharacter.Actions.{OnOverheard, OnPlayerTalked, ReactToTime}
  alias TalesForge.GameCharacter.Signals.Turn
  alias TalesForge.Intention

  @doc "The present NPCs' Intentions after `turn`: time passed, talked to, overheard."
  @spec intentions(Turn.t()) :: [Intention.t()]
  def intentions(%Turn{handler: handler} = turn) do
    present = Map.get(turn.world_state, "present_npcs", [])
    target = if speak_to_npc?(handler), do: handler.target

    Enum.flat_map(present, &ReactToTime.intentions(&1, turn)) ++
      talked(target in present && target, turn) ++ overheard(present, target, turn)
  end

  # Only a present NPC hears it, as only present NPCs had agents before.
  defp talked(false, _turn), do: []
  defp talked(npc_id, turn), do: OnPlayerTalked.intentions(npc_id, turn)

  defp overheard(present, target, %Turn{handler: handler} = turn) do
    if quiet?(handler) or String.trim(turn.raw_action || "") == "" do
      []
    else
      present
      |> Enum.reject(&(&1 == target))
      |> Enum.flat_map(&OnOverheard.intentions(&1, turn))
    end
  end

  defp speak_to_npc?(%{handler: "speak", target: target}) when is_binary(target), do: true
  defp speak_to_npc?(_), do: false

  defp quiet?(%{handler: handler}) when handler in ["wait", "train"], do: true
  defp quiet?(_), do: false
end
