defmodule TalesForge.Game.Turn.Outcome do
  @moduledoc """
  Stage 7 of a turn: the checks on the narration and the persistence.

    * `TURN_STATE_FROM_MECHANICS=on` or `TURN_APPLY_OUTCOMES=on`: the prose post-check. Each mismatch
      between the GM prose and the outcome record is logged and stored as a
      `turn.prose_mismatch` event. There is no GM re-run.
    * `COMBAT_OPPOSED=on`: the post-check also runs for the `:wound` kind
      alone. Each hit or blood in the prose that the exchange does not have
      is logged and stored as a `turn.prose_mismatch` event.
    * `NPC_DIALOGUE_MEMORY=on`: the server (never the GM) writes the lines
      that the NPCs spoke, and the repetition guard counts each repeat.
    * `TURN_OUTCOME_RECORD=on`: the outcome record goes to the turn as a
      `turn.outcome` event.
    * Default variant: the spent gestures the GM used anyway are logged.

  The `store` adapter persists the turn. Writes `result`. A turn with a
  failed GM call passes through.
  """

  require Logger

  alias TalesForge.AICalls.{Steps, Tags}
  alias TalesForge.Game.Gestures
  alias TalesForge.Game.NpcMemory
  alias TalesForge.Game.OutcomeRecord
  alias TalesForge.Game.ProseCheck
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.Premise
  alias TalesForge.Game.TurnProcessor
  alias TalesForge.World, as: WorldAgents
  alias TalesForge.World.Extract

  @doc "Writes `result`."
  @spec persist(Turn.t()) :: Turn.t()
  def persist(%Turn{narration: {:ok, gm_result}} = turn) do
    %{board: booked, handler: handler, mechanical: mechanical} = turn.outcome
    mismatches = prose_check(turn, gm_result.narrative, booked)
    {board, repeats} = npc_memory(turn, booked, gm_result.narrative)

    Gestures.log_repeats(gm_result.narrative, Map.get(turn.prompt.context, :recent_gestures),
      session: turn.session.id,
      turn: turn.number
    )

    result =
      Steps.time(:persist, fn ->
        world_final = TurnProcessor.turn_patches(board.world, gm_result, turn.injected)

        turn.adapters.store.(turn.session, world_final, turn.number, turn.history_action, %{
          handler: handler,
          mechanical: mechanical,
          gm_result: gm_result,
          events:
            board.events ++
              Premise.events(turn.premise.findings, board.world) ++
              record_events(turn, board) ++
              List.wrap(mismatches) ++ List.wrap(repeats),
          sim: board.sim,
          founder: turn.opts[:founder]
        })
      end)

    commit_agents(result, turn, board, gm_result)
    %{turn | result: result}
  end

  def persist(%Turn{} = turn), do: turn

  defp prose_check(turn, narrative, board) do
    record = Map.get(board, :outcome)

    state? =
      Turn.flag?(turn, :turn_state_from_mechanics) or Turn.flag?(turn, :turn_apply_outcomes)

    if (state? or Turn.flag?(turn, :combat_opposed)) and record do
      mismatches =
        narrative
        |> ProseCheck.check(record)
        |> Enum.filter(&(state? or &1.kind == :wound))

      if mismatches != [],
        do:
          Logger.warning(
            "prose mismatch session=#{turn.session.id} turn=#{turn.number} " <>
              "count=#{length(mismatches)} kinds=#{inspect(Enum.map(mismatches, & &1.kind))}"
          )

      ProseCheck.event(mismatches, record)
    end
  end

  defp npc_memory(turn, board, narrative) do
    if Turn.flag?(turn, :npc_dialogue_memory) do
      npcs = NpcMemory.present_npcs(turn.prompt.context.intent_context)

      {memory, repeats} =
        NpcMemory.put(board.world["npc_memory"] || %{}, NpcMemory.lines(narrative, npcs))

      if repeats != [],
        do:
          Logger.warning(
            "npc repeat session=#{turn.session.id} turn=#{turn.number} count=#{length(repeats)} " <>
              "npcs=#{inspect(Enum.map(repeats, &elem(&1, 0)))}"
          )

      world = Map.put(board.world, "npc_memory", memory)

      {%{board | world: world},
       NpcMemory.event(repeats, world["world_tick"] || 0, world["location_id"])}
    else
      {board, nil}
    end
  end

  defp record_events(turn, board) do
    case Map.get(board, :outcome) do
      record when is_map(record) ->
        if Turn.flag?(turn, :turn_outcome_record), do: [OutcomeRecord.event(record)], else: []

      _ ->
        []
    end
  end

  defp commit_agents({:ok, _}, %Turn{outcome: %{agents: agents}} = turn, board, gm_result)
       when agents != [] do
    WorldAgents.commit(turn.session.id, [], turn.npcs.reactions)

    Extract.run_async(
      turn.session.id,
      turn.number,
      turn.history_action,
      gm_result.narrative,
      agents,
      Tags.for_world(board.world)
    )
  end

  defp commit_agents(_result, _turn, _board, _gm_result), do: :ok
end
