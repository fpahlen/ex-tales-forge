defmodule TalesForge.Game.Turn.NarratedArrival do
  @moduledoc """
  A turn that moves the character narrates the way and the arrival itself
  (the "Just now: the character left …" line of the GM prompt), so the place
  it reached counts as described: `"last_scene_location"` is that place, and
  `TalesForge.Game.SceneProcessor.needs_scene?/1` asks for no second arrival
  scene. Playtest session 39fcbc9d (2026-10-21): every move was narrated
  twice, once by the turn and once by the scene step.

      iex> alias TalesForge.Game.Turn.NarratedArrival
      iex> NarratedArrival.mark(%{"location_id" => "smithy"}, %{"location_id" => "valley_inn"})
      %{"location_id" => "smithy", "last_scene_location" => "smithy"}
      iex> NarratedArrival.mark(%{"location_id" => "smithy"}, %{"location_id" => "smithy"})
      %{"location_id" => "smithy"}
  """

  alias TalesForge.Game.Movement

  @doc "`world_after` with its place described when the turn moved there from `world_before`'s."
  @spec mark(map(), map() | nil) :: map()
  def mark(%{"location_id" => here} = world_after, %{"location_id" => from})
      when is_binary(here) and here != from,
      do: Map.put(world_after, "last_scene_location", here)

  def mark(world_after, _world_before), do: world_after

  @doc """
  The place the character left this turn (`before` to `after_turn`), or nil;
  the scene block of the GM prompt narrates the way from it (`line/3`).
  """
  @spec from(map() | nil, map()) :: String.t() | nil
  def from(before, after_turn) do
    left = Map.get(before || %{}, "location_id")
    if left != Map.get(after_turn, "location_id"), do: left
  end

  @doc "The GM line for the way from `from` to `here`, or nil when the turn did not move."
  @spec line(map(), String.t() | nil, String.t()) :: String.t() | nil
  def line(_world, nil, _here), do: nil

  def line(world, from, here) do
    "Just now: the character left #{Movement.name(world, from)} for #{here}. " <>
      "Narrate the way and the arrival here; whoever was at #{Movement.name(world, from)} stays there."
  end
end
