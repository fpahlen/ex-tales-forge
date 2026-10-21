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
    * The spent gestures the GM used anyway are logged.

  The `store` adapter persists the turn. Writes `result`. A turn with a
  failed GM call passes through.
  """

  require Logger

  alias TalesForge.AICalls.{Steps, Tags}
  alias TalesForge.Game.DialogueMemory
  alias TalesForge.Game.Gestures
  alias TalesForge.Game.OutcomeRecord
  alias TalesForge.Game.ProseCheck
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.{Board, NarratedArrival, Premise, Store}
  alias TalesForge.World, as: WorldAgents
  alias TalesForge.World.Extract

  @doc "Writes `result`."
  @spec persist(Turn.t()) :: Turn.t()
  def persist(%Turn{narration: {:ok, gm_result}} = turn) do
    %{board: booked, handler: handler, mechanical: mechanical} = turn.outcome
    {board, checks} = checked(turn, booked, gm_result.narrative)
    log_gestures(turn, gm_result.narrative)

    result =
      Steps.time(:persist, fn ->
        write(turn, board, %{
          handler: handler,
          mechanical: mechanical,
          gm_result: gm_result,
          events: turn_events(turn, board, checks)
        })
      end)

    commit_agents(result, turn, board)
    %{turn | result: result}
  end

  def persist(%Turn{} = turn), do: turn

  # The prose check's mismatches and the NPC memory step's repeats, with the
  # board after the memory step.
  defp checked(turn, booked, narrative) do
    mismatches = prose_check(turn, narrative, booked)
    {board, repeats} = npc_memory(turn, booked, narrative)
    {board, List.wrap(mismatches) ++ List.wrap(repeats)}
  end

  defp log_gestures(turn, narrative) do
    Gestures.log_repeats(narrative, Map.get(turn.prompt.context, :recent_gestures),
      session: turn.session.id,
      turn: turn.number
    )
  end

  # The events of the turn: the board's, the premise findings, the outcome
  # record's and the prose and repeat checks.
  defp turn_events(turn, board, checks) do
    board.events ++
      Premise.events(turn.premise.findings, board.world) ++
      record_events(turn, board) ++ checks
  end

  # The store adapter's write: the world after the allow-listed GM patches.
  defp write(%Turn{} = turn, board, ctx) do
    turn.adapters.store.(%Store{
      session: turn.session,
      world:
        board.world
        |> Board.turn_patches(ctx.gm_result, turn.injected)
        |> NarratedArrival.mark(turn.session.world_state),
      number: turn.number,
      raw_action: turn.history_action,
      ctx:
        Map.merge(ctx, %{
          sim: board.sim,
          cast: board.cast,
          traders: Map.get(board, :traders, []),
          founder: turn.opts[:founder],
          intention: turn.intention
        })
    })
  end

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
      npcs = DialogueMemory.present_npcs(turn.prompt.context.intent_context)

      {memory, repeats} =
        DialogueMemory.put(
          board.world["npc_memory"] || %{},
          DialogueMemory.lines(narrative, npcs)
        )

      if repeats != [],
        do:
          Logger.warning(
            "npc repeat session=#{turn.session.id} turn=#{turn.number} count=#{length(repeats)} " <>
              "npcs=#{inspect(Enum.map(repeats, &elem(&1, 0)))}"
          )

      world = Map.put(board.world, "npc_memory", memory)

      {%{board | world: world},
       DialogueMemory.event(repeats, world["world_tick"] || 0, world["location_id"])}
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

  defp commit_agents({:ok, _}, %Turn{outcome: %{agents: agents}} = turn, board)
       when agents != [] do
    {:ok, gm_result} = turn.narration
    WorldAgents.commit(turn.session.id, [], turn.npcs.reactions)

    Extract.run_async(%Extract.Job{
      session_id: turn.session.id,
      turn_number: turn.number,
      raw_action: turn.history_action,
      narrative: gm_result.narrative,
      agents: agents,
      tags: Tags.for_world(board.world)
    })
  end

  defp commit_agents(_result, _turn, _board), do: :ok
end
