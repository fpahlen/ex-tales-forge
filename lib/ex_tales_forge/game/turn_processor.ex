defmodule TalesForge.Game.TurnProcessor do
  @moduledoc """
  Runs a turn: one pipe over a `%TalesForge.Game.Turn{}` struct (premise,
  mechanics, NPCs, notice, prompt, GM, outcome; the stages are in
  `TalesForge.Game.Turn`), timed per step, then broadcast. The board step is
  `TalesForge.Game.Turn.Board`; the Multi and the signals are
  `TalesForge.Game.Turn.Store`. Neither calls back into this module.

  `TURN_PREMISE_FIRST=on`: the premise check runs first, against the state
  before the turn. A claim that the state contradicts blocks the action: the
  turn rolls nothing, books nothing and costs no game time.

  Core runtime is 100% Ecto.
  """

  require Logger

  alias TalesForge.GameCharacter

  alias TalesForge.AICalls.{Steps, Tags}

  alias TalesForge.Game.Schemas.{GMStructuredResponse, PlayerAction}

  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.{Board, Store}
  alias TalesForge.Intention
  alias TalesForge.LLM
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  @doc """
  Runs one turn. The main steps (rules, prompt build, GM call, persistence)
  are timed and recorded in `ai_calls` as `call_type` `function` rows
  (`TalesForge.AICalls.Steps`), whether the turn succeeds or fails.

  `player_action_map` is the encoded `PlayerAction` from the intent step.
  Returns `{:ok, payload}` once the turn is persisted and broadcast, or
  `{:error, reason}` (also broadcast as `:turn_failed`).

  A crash in a step (a raise, throw or exit) is logged with its stacktrace,
  broadcast as `:turn_failed` and recorded on the step's row, then re-raised
  so the Oban job records it. The job does not retry
  (`TalesForge.Workers.ProcessTurn`). Before this a crashed turn was
  silent: the job failed three times, nothing was logged or broadcast, and
  the player (or the playtest runner) waited until its timeout.

  `opts` (set only by the Jev intent path, `INTENT_JEV=on`):

    * `:gm_quote` — the text the GM gets as the action's `overall_intent`: the
      player's own words when the safety read was confidently benign, else a
      typed summary (`TalesForge.Game.PlayerQuote`). The rules still read
      `player_action_map`.
    * `:gm_note` — `"decline_nefarious"`: the GM declines the request in
      character (`TalesForge.Game.Context.player_request_section/1`).
    * `:founder` — the email of the signed-in founder who plays the turn. The
      turn row stores it for the work log. The GM prompt does not use it.

  Without them the GM prompt is byte-identical to before.
  """
  @spec run(String.t(), {String.t(), map()}, keyword()) :: {:ok, map()} | {:error, term()}
  def run(session_id, {raw_action, player_action_map}, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    case Repo.get(GameSession, session_id) do
      nil ->
        {:error, :not_found}

      %GameSession{} = stored ->
        session = GameCharacter.Store.put_sheet(stored)
        turn_number = Store.next_turn_number(session_id)

        {result, steps} =
          Steps.collect(fn ->
            {session, turn_number}
            |> Turn.new({raw_action, PlayerAction.decode(player_action_map)}, opts)
            |> Turn.Premise.check()
            |> Turn.Mechanics.apply()
            |> Turn.Reactions.react()
            |> Turn.Place.settle()
            |> Turn.Notice.select()
            |> Turn.Prompt.build()
            |> Turn.Gm.narrate()
            |> Turn.Outcome.persist()
            |> Turn.result()
          end)

        Steps.record(steps, {session_id, turn_number}, Tags.for_world(session.world_state))
        finish(result, %{session_id: session_id, turn_number: turn_number, started: started})
    end
  end

  # `at` has the session id, the turn number and when the turn started.
  defp finish({:ok, payload}, %{
         session_id: session_id,
         turn_number: turn_number,
         started: started
       }) do
    elapsed = System.monotonic_time(:millisecond) - started

    Logger.info(
      "turn completed session=#{session_id} turn=#{turn_number} duration_ms=#{elapsed} llm_source=#{LLM.llm_source(LLM.provider())}"
    )

    SessionPubSub.broadcast(session_id, {:turn_completed, payload})
    {:ok, payload}
  end

  defp finish({:error, reason} = err, %{session_id: session_id}) do
    Logger.error("turn processor failed session=#{session_id} reason=#{inspect(reason)}")
    SessionPubSub.broadcast(session_id, {:turn_failed, SessionPubSub.failure_reason(reason)})
    err
  end

  defp finish({:crash, kind, reason, stacktrace}, %{
         session_id: session_id,
         turn_number: turn_number
       }) do
    Logger.error(
      "turn processor crashed session=#{session_id} turn=#{turn_number}\n" <>
        Exception.format(kind, reason, stacktrace)
    )

    SessionPubSub.broadcast(session_id, {:turn_failed, crash_reason(kind, reason)})
    :erlang.raise(kind, reason, stacktrace)
  end

  # What the player and the playtest run see: the kind of crash, no internals
  # (the log has the details).
  defp crash_reason(:error, reason) do
    "crashed: " <> inspect(Exception.normalize(:error, reason, []).__struct__)
  end

  defp crash_reason(kind, _reason), do: "crashed: #{kind}"

  @doc false
  @spec simulate!(Board.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def simulate!(
        %Board{session: session, handler: handler, mechanical: mechanical} = board,
        raw_action
      ) do
    gm_result = %GMStructuredResponse{narrative: "ok", context_summary: nil}

    character = Map.get(session.world_state || %{}, "character", %{})

    %{
      world: world_board,
      events: events,
      sim: sim,
      improvements: improvements,
      training: training,
      traders: traders
    } =
      Board.resolve(%{board | character: character})

    Store.persist(%Store{
      session: session,
      world: world_board,
      number: Store.next_turn_number(session.id),
      raw_action: raw_action,
      ctx: %{
        handler: handler,
        mechanical: %{mechanical | improvements: improvements, training: training},
        gm_result: gm_result,
        events: events,
        sim: sim,
        traders: traders,
        intention: Intention.human(character["id"], nil)
      }
    })
  end
end
