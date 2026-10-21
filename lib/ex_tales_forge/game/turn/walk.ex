defmodule TalesForge.Game.Turn.Walk do
  @moduledoc """
  The walk inside the room, with `LOCATION_GRID` on (docs/design-locations.md,
  step 2). The intent step marks a move to something that is no place as a
  walk (`parameters["walk_to"]`, `TalesForge.Game.Intent`); here the player
  character walks next to that spot and faces it
  (`TalesForge.Locations.Walk`), and the new position goes to the board's
  world. Words for nothing in the room move nothing: the GM is told "You
  can't see a X here." as a premise finding.
  """

  alias TalesForge.Game.Turn
  alias TalesForge.Locations.Positions
  alias TalesForge.Locations.View
  alias TalesForge.Locations.Walk

  @doc "Walks the player character, or notes that there is no such spot."
  @spec walk(Turn.t()) :: Turn.t()
  def walk(%Turn{outcome: %{board: %{world: world}}} = turn) do
    id = get_in(world, ["character", "id"])

    with %{"walk_to" => words} <- walk_to(turn),
         {grid, pos} <- View.of(world, id) do
      grid |> Walk.resolve(pos, words(words, turn.raw_action)) |> apply_to(turn, id)
    else
      _none -> turn
    end
  end

  def walk(%Turn{} = turn), do: turn

  defp apply_to({:moved, to}, %Turn{outcome: outcome} = turn, id),
    do: put_world(turn, Positions.put(outcome.board.world, id, to))

  defp apply_to({:no_move, what}, turn, _id), do: note(turn, what)

  defp walk_to(%Turn{intent: %{action: %{parameters: %{} = params}}}), do: params
  defp walk_to(_turn), do: nil

  # The intent's target, or the player's words when it has none.
  defp words(words, raw) when words in [nil, ""], do: raw || ""
  defp words(words, _raw), do: words

  defp put_world(%Turn{outcome: outcome} = turn, world),
    do: %{turn | outcome: %{outcome | board: %{outcome.board | world: world}}}

  defp note(%Turn{premise: premise} = turn, what) do
    finding = %{kind: :place, claim: what, correction: "You can't see a #{what} here."}
    %{turn | premise: %{premise | findings: List.wrap(premise.findings) ++ [finding]}}
  end
end
