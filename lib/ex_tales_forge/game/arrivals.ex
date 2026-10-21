defmodule TalesForge.Game.Arrivals do
  @moduledoc """
  People the world tick moved to the player's place (a front's
  `move_people` with `"@player"`, e.g. the Tinjacks coming for their share):
  one `npc.arrived` session event each, and `"arrived_npcs"` in the world so
  that the GM prompt of the next turn says who walked in (playtest session
  39fcbc9d, 2026-10-21: Rusk and Cobb appeared at the player's side and the
  GM was told nothing).

      iex> before = [%{npc_id: "rusk", runtime_state: %{"location_id" => "valley_inn"}}]
      iex> after_tick = [%{npc_id: "rusk", runtime_state: %{"location_id" => "smithy"}}]
      iex> TalesForge.Game.Arrivals.of(before, after_tick, "smithy")
      ["rusk"]
      iex> TalesForge.Game.Arrivals.of(after_tick, after_tick, "smithy")
      []
  """

  @doc "The ids of the people at `here` after the tick who were elsewhere before it."
  @spec of([map()], [map()], String.t() | nil) :: [String.t()]
  def of(people_before, people_after, here) do
    was = Map.new(people_before, &{&1.npc_id, place(&1)})

    for person <- people_after,
        place(person) == here and was[person.npc_id] != here,
        do: person.npc_id
  end

  @doc """
  The turn's events and the sim after the tick, with one `npc.arrived` event
  per person who came to the player's place (`world`) and the ids in the sim
  (`:arrived`).
  """
  @spec after_tick({[map()], map()}, [map()], map()) :: {[map()], map()}
  def after_tick({events, sim}, people_before, %{"location_id" => here} = world) do
    arrived = of(people_before, sim.people, here)
    {events ++ events(arrived, world), Map.put(sim, :arrived, arrived)}
  end

  defp events(arrived, %{"location_id" => here} = world) do
    for id <- arrived do
      %{
        "kind" => "npc.arrived",
        "actor" => id,
        "player_aware" => true,
        "tick" => world["world_tick"],
        "location_id" => here,
        "payload" => %{"npc_id" => id, "location_id" => here}
      }
    end
  end

  @doc "The world with the sim's arrivals of this tick (none: the key goes)."
  @spec put(map(), map()) :: map()
  def put(world, %{arrived: [_ | _] = arrived}), do: Map.put(world, "arrived_npcs", arrived)
  def put(world, _sim), do: Map.delete(world, "arrived_npcs")

  @doc """
  People a front moved this tick (e.g. the Tinjacks walking into the inn) are
  present this turn, not only from the next one.
  """
  @spec present(map(), [map()]) :: map()
  def present(world, []), do: world

  def present(world, people) do
    here = world["location_id"]

    present =
      for person <- people, place(person) == here, do: person.npc_id

    Map.put(world, "present_npcs", Enum.sort(present))
  end

  @doc """
  The GM line for the people who walked in on the last tick (the
  `"arrived_npcs"` of the world before this turn), or nil.

      iex> TalesForge.Game.Arrivals.line(["rusk"], %{"rusk" => %{"name" => "Rusk"}})
      "Just arrived: Rusk walked in here since the last turn. Narrate them as newly here."
      iex> TalesForge.Game.Arrivals.line(nil, %{})
      nil
  """
  @spec line([String.t()] | nil, map()) :: String.t() | nil
  def line([_ | _] = ids, details) do
    names = Enum.map_join(ids, " and ", &(get_in(details, [&1, "name"]) || &1))
    "Just arrived: #{names} walked in here since the last turn. Narrate them as newly here."
  end

  def line(_ids, _details), do: nil

  defp place(person), do: get_in(person, [Access.key(:runtime_state), "location_id"])
end
