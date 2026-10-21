defmodule TalesForge.Game.WalkThenTrade do
  @moduledoc """
  A trade that walks first: "I walk to the smithy and sell my knife to
  Hilde" (Gentry, playtest v392, session 63094001 T8). The intent step
  (`TalesForge.Game.Intent`) gives the trade a `"move_to"` when the words name
  a place the character can reach in one walk (no checkpoint on the way);
  the board step (`TalesForge.Game.Turn.Board`) walks there, then trades
  there. The turn costs the walk, then the trade. Pure.
  """

  alias TalesForge.Game.{Movement, Travel}
  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Locations.Destination

  @doc """
  A trade `action` with `"move_to"` when the words (`"overall_intent"` of the intent
  `context`) name a place reachable from `"location_id"` in one walk; else
  `action` as it is.

      iex> places = %{
      ...>   "inn" => %{"name" => "The Inn", "exits" => ["smithy"]},
      ...>   "smithy" => %{"name" => "Smithy", "exits" => ["inn"]}}
      iex> at = %{"location_id" => "inn", "places" => places}
      iex> sell = %TalesForge.Game.Schemas.SingleAction{action_type: :sell, target: "smith", parameters: %{}}
      iex> TalesForge.Game.WalkThenTrade.walk(sell, Map.put(at, "overall_intent", "I walk to the smithy and sell my knife.")).parameters
      %{"move_to" => "smithy"}
      iex> TalesForge.Game.WalkThenTrade.walk(sell, Map.put(at, "overall_intent", "I sell my knife.")) == sell
      true
  """
  @spec walk(SingleAction.t(), map()) :: SingleAction.t()
  def walk(%SingleAction{action_type: type} = action, context)
      when type in [:buy, :sell, :trade] do
    world = %{"locations" => context["places"] || %{}}

    with {:place, id} <- Destination.of(world, context, context["overall_intent"]),
         {:ok, ^id} <- Movement.route(world, context["location_id"], id),
         do: %{action | parameters: Map.put(action.parameters || %{}, "move_to", id)},
         else: (_ -> action)
  end

  def walk(action, _context), do: action

  @doc """
  The ticks of the walk from `from` to where the character is now: the walk
  time of the place tree (`TalesForge.Game.Travel`), else 1; nil when it did
  not walk.
  """
  @spec ticks(map(), String.t() | nil) :: non_neg_integer() | nil
  def ticks(world, from) do
    to = get_in(world, ["character", "location_id"])
    if is_binary(from) and from != to, do: Travel.ticks(world, from, to) || 1
  end
end
