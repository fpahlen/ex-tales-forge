defmodule TalesForge.Game.TurnRules do
  @moduledoc """
  Provisional turn rules (tales-forge-docs `docs/decisions.md`, 2026-10-12,
  "Turn pipeline: provisional rules"). Each rule settles a gap in the turn
  pipeline design until a full decision replaces it.

    * `minutes/1` — the game minutes of one action: the existing clock costs
      plus a placeholder for each new catalogue action. A `none_fits` turn
      does not move the clock.
    * `cap_actions/1` — at most 3 ordered actions. A 4th action is dropped,
      and the GM gets a note.
    * `same_line?/2` — an NPC repeat is an exact match after the server
      lowers the case and collapses the whitespace.
    * `lodging_seller?/2` — "pay for a room" needs someone here who rents
      rooms. Without one, stage 3 rejects the payment with the reason
      `nobody_rents_rooms/0`.

  The catalogue (design §8 step 5) and NPC memory (step 4) wire in the rules
  for the new actions and the repeat guard. This module holds the values now.
  """

  alias TalesForge.Game.Rest
  alias TalesForge.Game.WorldClock

  # Existing clock costs: one tick for a plain action; wait and train use
  # their own ticks. Placeholders for the catalogue v2 actions (provisional).
  @placeholder_minutes %{
    "rest" => 60,
    "work" => 60,
    "equip" => 15,
    "give" => 15,
    "none_fits" => 0
  }

  @max_actions 3

  @nobody_rents "nobody here rents rooms"

  @doc """
  The game minutes of one action type.

      iex> TalesForge.Game.TurnRules.minutes("speak")
      15
      iex> TalesForge.Game.TurnRules.minutes("none_fits")
      0
      iex> TalesForge.Game.TurnRules.minutes("work")
      60
  """
  @spec minutes(String.t()) :: non_neg_integer()
  def minutes(action),
    do: Map.get(@placeholder_minutes, action, WorldClock.minutes_per_tick())

  @doc """
  Keeps the first 3 actions. Returns the kept actions and a GM note, or nil
  when nothing was dropped.

      iex> TalesForge.Game.TurnRules.cap_actions([:a, :b, :c, :d])
      {[:a, :b, :c], "The player asked for more than 3 actions. Play the first 3. Do not narrate the others as done."}
      iex> TalesForge.Game.TurnRules.cap_actions([:a])
      {[:a], nil}
  """
  @spec cap_actions(list()) :: {list(), String.t() | nil}
  def cap_actions(actions) when length(actions) > @max_actions do
    {Enum.take(actions, @max_actions),
     "The player asked for more than #{@max_actions} actions. Play the first #{@max_actions}. Do not narrate the others as done."}
  end

  def cap_actions(actions), do: {actions, nil}

  @doc """
  True when two NPC lines are the same after the server lowers the case and
  collapses the whitespace.

      iex> TalesForge.Game.TurnRules.same_line?("Bring the  LEDGER back.", "bring the ledger back.")
      true
      iex> TalesForge.Game.TurnRules.same_line?("Bring the ledger.", "Bring the ledger back.")
      false
  """
  @spec same_line?(String.t(), String.t()) :: boolean()
  def same_line?(a, b) when is_binary(a) and is_binary(b), do: normalise(a) == normalise(b)

  defp normalise(line), do: line |> String.downcase() |> String.split() |> Enum.join(" ")

  @doc "The reason for a room payment with nobody here who rents rooms."
  @spec nobody_rents_rooms() :: String.t()
  def nobody_rents_rooms, do: @nobody_rents

  @doc """
  True when someone here rents rooms: the place is a lodging place
  (`TalesForge.Game.Rest.rest_place?/2`) and a person is present.
  """
  @spec lodging_seller?(map(), String.t() | nil) :: boolean()
  def lodging_seller?(world, location_id) do
    Rest.rest_place?(world, location_id) and Map.get(world, "present_npcs", []) != []
  end
end
