defmodule TalesForge.Game.Turn.Premise do
  @moduledoc """
  Stage 2 of a turn: the premise check (`TalesForge.Game.PremiseCheck`).
  The claims in the player's words that the session state contradicts go to
  the GM prompt and to the turn as `player.false_premise` events.

  `check/1` runs first only with `TURN_PREMISE_FIRST=on`: its findings block
  the action. Otherwise `TalesForge.Game.Turn.Reactions.react/1` runs the check on
  the board.
  """

  require Logger
  import Ecto.Query

  alias TalesForge.AICalls.Steps
  alias TalesForge.Fronts
  alias TalesForge.Game.PremiseCheck
  alias TalesForge.Game.PremiseCheck.Input
  alias TalesForge.Game.Turn
  alias TalesForge.Repo
  alias TalesForge.Schemas.Turn, as: TurnRow

  @doc "Writes `premise.first`: the findings against the state before the turn, or nil."
  @spec check(Turn.t()) :: Turn.t()
  def check(%Turn{injected: true} = turn), do: put_first(turn, [])

  def check(%Turn{} = turn) do
    world = Turn.world_before(turn)

    if Turn.flag?(turn, :turn_premise_first) do
      put_first(
        turn,
        run(
          turn,
          %Input{
            world_before: world,
            world_after: world,
            fronts: Fronts.sim_fronts(turn.session.id),
            won_fights: fights(turn)
          }
          |> PremiseCheck.state()
          |> Map.put(:people, PremiseCheck.people(turn.cast))
        )
      )
    else
      turn
    end
  end

  @doc "The findings against `board` (after the mechanics)."
  @spec findings(Turn.t(), map()) :: [PremiseCheck.finding()]
  def findings(%Turn{} = turn, board) do
    world = Turn.world_before(turn)

    run(
      turn,
      %Input{
        world_before: world,
        world_after: board.world,
        fronts: Map.get(board.sim, :fronts, []),
        won_fights: fights(turn)
      }
      |> PremiseCheck.state()
      |> Map.put(:people, PremiseCheck.people(Map.get(board, :cast, turn.cast)))
    )
  end

  @doc "The session events for `findings`."
  @spec events([PremiseCheck.finding()], map()) :: [map()]
  def events(findings, world) do
    findings
    |> PremiseCheck.event(world["world_tick"], world["location_id"])
    |> List.wrap()
  end

  defp put_first(turn, first), do: %{turn | premise: %{turn.premise | first: first}}

  defp run(turn, state) do
    Steps.time(:premise_check, fn ->
      turn.raw_action
      |> PremiseCheck.check(state)
      |> tap(&log(&1, turn))
    end)
  end

  defp log([], _turn), do: :ok

  defp log(findings, turn) do
    Logger.info(
      "premise check session=#{turn.session.id} turn=#{turn.number} " <>
        "false_claims=#{inspect(Enum.map(findings, & &1.claim))}"
    )
  end

  # The player text and narration of each fight the character has won this
  # session, so a kill claim is checked against what was actually fought.
  defp fights(turn) do
    TurnRow
    |> where([t], t.game_session_id == ^turn.session.id)
    |> select([t], {t.mechanical_resolution, t.player_action, t.narrative})
    |> Repo.all()
    |> Enum.filter(fn {resolution, _action, _narrative} ->
      PremiseCheck.combat_win?(resolution)
    end)
    |> Enum.map(fn {_resolution, action, narrative} ->
      Enum.join([action || "", narrative || ""], "\n")
    end)
  end
end
