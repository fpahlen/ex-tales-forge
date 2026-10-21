defmodule TalesForge.Locations.NoMove do
  @moduledoc """
  A move the intent step refuses (Fredrik's rule, 2026-10-21): a character
  travels only to a place the world has and that has a route from where it
  is, and walks only to a spot in its room. A refused move becomes `:other`
  with `parameters["no_move"]`, so nothing happens and the turn costs no
  game time (the action handler, TalesForge.Game.ActionHandler); the GM gets the note
  (`TalesForge.Game.Turn.NoPlace`, `TalesForge.Game.Turn.Walk`). Pure.
  """

  alias TalesForge.Game.Movement
  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Locations.Target

  @doc """
  No move to a place: a move that named a target carries it in
  `parameters["no_place"]` (a place's name for a place id).

      iex> alias TalesForge.Game.Schemas.SingleAction
      iex> move = %SingleAction{action_type: :move, target: "castle", parameters: %{}}
      iex> TalesForge.Locations.NoMove.place(move, %{}).parameters
      %{"no_move" => true, "no_place" => "castle"}
  """
  @spec place(SingleAction.t(), map()) :: SingleAction.t()
  def place(%SingleAction{target: target} = action, world) when is_binary(target) do
    what = if Map.has_key?(Movement.places(world), target), do: Movement.name(world, target)
    refuse(action, %{"no_place" => what || String.replace(target, "_", " ")})
  end

  def place(action, _world), do: refuse(action, %{})

  @doc """
  The walk's parameters, with `"no_move"` when `words` name no spot of the
  room (`context["spot_names"]`, `TalesForge.Locations.Spots`).

      iex> TalesForge.Locations.NoMove.spot(%{}, %{"spot_names" => %{"hearth" => "open hearth"}}, "the dragon")
      %{"no_move" => true}
      iex> TalesForge.Locations.NoMove.spot(%{}, %{"spot_names" => %{"hearth" => "open hearth"}}, "the hearth")
      %{}
  """
  @spec spot(map(), map(), String.t() | nil) :: map()
  def spot(params, context, words) do
    case Target.among(context["spot_names"] || %{}, words || "") do
      {:ok, _item} -> params
      :unknown -> Map.put(params, "no_move", true)
    end
  end

  defp refuse(action, params) do
    params = Map.merge(action.parameters || %{}, Map.put(params, "no_move", true))
    %SingleAction{action | action_type: :other, target: nil, parameters: params}
  end
end
