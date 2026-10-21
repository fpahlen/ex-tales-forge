defmodule TalesForge.Locations.Exits do
  @moduledoc """
  Leaving a room with a grid (docs/design-locations.md, step 2). Pure.

  A move whose target is no place ("I flee out the door into the street",
  "I head out") leaves through the door: the destination comes from the
  place tree (`TalesForge.Game.Movement.way_out/2`: the place's `door`, its
  only exit, or its parent), so the system decides where the character goes
  and the GM narrates it. Any other move to no place stays a walk inside the
  room (`TalesForge.Locations.Walk`).
  """

  alias TalesForge.Game.Movement
  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Locations.NoMove

  @out ~r/\b(?:out|outside|flee|flees|fleeing|escape|escapes|leave|leaves|leaving|exit|exits|through (?:the |a )?(?:\w+ )?door)\b/iu

  @doc """
  A move whose target names no place, in a room with a grid: a move to the
  way out when its words (the target and the player's `"overall_intent"`)
  ask for one, else no move, with the target kept in `"walk_to"` for the
  walk inside the room (`TalesForge.Game.Turn.Walk`).
  """
  @spec no_place(SingleAction.t(), map()) :: SingleAction.t()
  def no_place(%SingleAction{} = action, context) do
    world = %{"locations" => context["places"] || %{}, "features" => context["features"]}
    words = "#{action.target} #{context["overall_intent"]}"

    case way_out(world, context["location_id"], words) do
      nil ->
        %SingleAction{
          action
          | action_type: :other,
            target: nil,
            parameters: walk_to(action, context)
        }

      place ->
        %SingleAction{action | target: place}
    end
  end

  defp walk_to(action, context) do
    params = Map.put(action.parameters || %{}, "walk_to", action.target)
    NoMove.spot(params, context, action.target || context["overall_intent"])
  end

  @doc """
  The place a move that names no place leaves for, or nil when the words
  ask for no way out.

      iex> world = %{"locations" => %{"inn" => %{"exits" => ["square"]}, "square" => %{"exits" => ["inn"]}}}
      iex> TalesForge.Locations.Exits.way_out(world, "inn", "I flee out the door into the street.")
      "square"
      iex> TalesForge.Locations.Exits.way_out(world, "inn", "I walk over to the hearth")
      nil
  """
  @spec way_out(map(), String.t() | nil, String.t()) :: String.t() | nil
  def way_out(world, from, words) do
    if Regex.match?(@out, words), do: through_door(world, from)
  end

  # The place's `door` when it names one, else its first hand-written exit
  # (the street, not the village it is in), else the place tree's way out.
  defp through_door(world, from) do
    place = Map.get(Movement.places(world), from, %{})

    if place["door"],
      do: Movement.way_out(world, from),
      else: List.first(List.wrap(place["exits"])) || Movement.way_out(world, from)
  end
end
