defmodule TalesForge.Game.Turn.Place do
  @moduledoc """
  The turn stage after the mechanics with `LOCATION_GRID` on: every
  character in the turn's world gets its grid position
  (`TalesForge.Locations.Positions.settle/3`), so a new session starts on
  the main door, facing in, and the position persists across turns. With the
  flag off only the note for a move to no known place runs
  (`TalesForge.Game.Turn.NoPlace`). Then the player character walks inside
  the room when the intent asks for it (`TalesForge.Game.Turn.Walk`). Runs
  after the NPC step, so a "no such spot" note joins the premise findings.
  """

  alias TalesForge.Game.Context
  alias TalesForge.Game.Turn
  alias TalesForge.GameCharacter
  alias TalesForge.Locations.Pack
  alias TalesForge.Locations.Positions

  @doc "Settles the positions on `outcome.board.world`."
  @spec settle(Turn.t()) :: Turn.t()
  def settle(%Turn{} = turn), do: turn |> on_grid() |> Turn.NoPlace.note()

  defp on_grid(%Turn{outcome: %{board: board} = outcome} = turn) do
    if Turn.flag?(turn, :location_grid) do
      world = board.world
      grids = world |> Context.adventure_id() |> Pack.grids()
      world = Enum.reduce(placed(world, board), world, &Positions.settle(&2, grids, &1))
      Turn.Walk.walk(%{turn | outcome: %{outcome | board: %{board | world: world}}})
    else
      turn
    end
  end

  # Each character's id and place: the player character and the GM characters.
  defp placed(world, board) do
    pc = for %{"id" => id} <- [world["character"]], do: {id, world["location_id"]}

    npcs =
      for {_slug, %GameCharacter{slug: id, location_id: loc}} <- Map.get(board, :cast, %{}),
          do: {id, loc}

    pc ++ npcs
  end
end
