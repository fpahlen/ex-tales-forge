defmodule TalesForge.Game.Turn.Npcs do
  @moduledoc """
  Stage 4 of a turn: the NPC reactions (prototype, `NPC_REACTIONS=on` or
  `WORLD_AGENTS=on`), before the GM call. Moods carry over in
  `world_state["npc_moods"]`; this turn's reactions go to the per-turn prompt.
  The reactions come from the `npc` adapter (the Jev call and its 600 ms
  timeout).

  With `NPC_DIALOGUE_MEMORY=on` the premise check runs before this stage, so
  the NPCs get its findings. Writes `npcs`, the board of `outcome` and
  `premise.findings`.
  """

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.NpcReactions
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.Premise

  @doc "Writes `npcs.reactions` and `premise.findings`."
  @spec react(Turn.t()) :: Turn.t()
  def react(%Turn{outcome: %{board: board} = outcome} = turn) do
    early = turn.premise.first || memory_premises(turn, board)
    {reactions, board} = reactions(turn, board, early || [])
    findings = early || Premise.findings(turn, board)

    %{
      turn
      | outcome: %{outcome | board: board},
        npcs: %{reactions: reactions},
        premise: %{turn.premise | findings: findings}
    }
  end

  defp memory_premises(turn, board) do
    if Turn.flag?(turn, :npc_dialogue_memory), do: Premise.findings(turn, board)
  end

  defp reactions(turn, board, findings) do
    if enabled?(turn) do
      Steps.time(:npc_reactions, fn ->
        {reactions, world} =
          turn.adapters.npc.(%NpcReactions.Moment{
            session_id: turn.session.id,
            world: board.world,
            turn_number: turn.number,
            raw_action: turn.raw_action,
            mechanical: turn.outcome.mechanical,
            findings: findings
          })

        {reactions, %{board | world: world}}
      end)
    else
      {[], board}
    end
  end

  defp enabled?(turn),
    do:
      (Turn.flag?(turn, :npc_reactions) or Turn.flag?(turn, :world_agents)) and
        NpcReactions.configured?()
end
