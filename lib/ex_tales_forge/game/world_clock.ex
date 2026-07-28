defmodule TalesForge.Game.WorldClock do
  @moduledoc """
  In-world time via discrete ticks.

  - 1 tick ≈ 15 minutes
  - 4 ticks ≈ 1 hour
  - 96 ticks ≈ 1 day (~100 is a fair round-number approximation)
  """

  alias TalesForge.Game.Context

  @minutes_per_tick 15
  @ticks_per_hour 4
  @ticks_per_day 96

  def minutes_per_tick, do: @minutes_per_tick
  def ticks_per_hour, do: @ticks_per_hour
  def ticks_per_day, do: @ticks_per_day

  @default_start_tick 36

  def default_start_tick, do: @default_start_tick

  def advance(world_state, delta \\ 1) when is_map(world_state) and is_integer(delta) do
    tick = Context.world_tick(world_state) + delta

    world_state
    |> Map.put("world_tick", tick)
    |> Map.put("world_clock", format(tick))
  end

  def format(tick) when is_integer(tick) and tick >= 0 do
    day = div(tick, @ticks_per_day) + 1
    "Day #{day} · #{time_of_day(rem(tick, @ticks_per_day))}"
  end

  defp time_of_day(slot) when slot in 0..3, do: "deep night"
  defp time_of_day(slot) when slot in 4..7, do: "dawn"
  defp time_of_day(slot) when slot in 8..15, do: "morning"
  defp time_of_day(slot) when slot in 16..23, do: "midday"
  defp time_of_day(slot) when slot in 24..31, do: "afternoon"
  defp time_of_day(slot) when slot in 32..39, do: "late afternoon"
  defp time_of_day(slot) when slot in 40..47, do: "dusk"
  defp time_of_day(slot) when slot in 48..55, do: "evening"
  defp time_of_day(slot) when slot in 56..63, do: "night"
  defp time_of_day(slot) when slot in 64..71, do: "late night"
  defp time_of_day(slot) when slot in 72..79, do: "witching hour"
  defp time_of_day(slot) when slot in 80..87, do: "pre-dawn"
  defp time_of_day(_), do: "deep night"
end
