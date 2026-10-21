defmodule TalesForge.Game.Turn.NoPlace do
  @moduledoc """
  The note for a move that gives no move (`parameters["no_place"]`,
  `TalesForge.Locations.NoMove.place/2`): a character travels only
  to a place the world has and that has a route from where it is, so the GM
  is told "There's no X you know of." as a premise finding, as for a spot
  that is not in the room (`TalesForge.Game.Turn.Walk`).
  """

  alias TalesForge.Game.Turn

  @doc "Adds the note when the intent asked for a place it has none of."
  @spec note(Turn.t()) :: Turn.t()
  def note(
        %Turn{intent: %{action: %{parameters: %{"no_place" => what}}}, premise: premise} = turn
      ) do
    finding = %{kind: :place, claim: what, correction: "There's no #{what} you know of."}
    %{turn | premise: %{premise | findings: List.wrap(premise.findings) ++ [finding]}}
  end

  def note(%Turn{} = turn), do: turn
end
