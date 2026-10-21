defmodule TalesForge.Locations.Named do
  @moduledoc """
  Whether the player's words name a place or a spot of the room exactly, from
  the intent context (`"places"`, `"features"`, `"spot_names"`). Playtest
  session 39fcbc9d (2026-10-21): "I go to the bar" and "back to the inn" were
  asked about and did not move, and the bar was offered twice, as the bar desk
  and as the bar counter.

      iex> context = %{"spot_names" => %{"bar" => "bar desk", "bar desk" => "bar desk"}}
      iex> TalesForge.Locations.Named.spot?(context, "bar counter")
      true
      iex> TalesForge.Locations.Named.spot?(context, "hearth")
      false
  """

  alias TalesForge.Locations.{Destination, Target}

  @doc "True when `text` names a place (`Destination.of/3`) or a spot of the room."
  @spec place_or_spot?(map(), String.t()) :: boolean()
  def place_or_spot?(context, text) do
    world = %{"locations" => context["places"] || %{}, "features" => context["features"]}
    match?({:place, _id}, Destination.of(world, context, text)) or spot?(context, text)
  end

  @doc "True when `words` name a spot of the room."
  @spec spot?(map(), String.t()) :: boolean()
  def spot?(context, words),
    do: match?({:ok, _item}, Target.among(context["spot_names"] || %{}, words))
end
