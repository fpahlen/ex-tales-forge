defmodule TalesForge.Game.Fronts.Rules do
  @moduledoc """
  Tiny predicate table for PR-3. Pack JSON documents the rules;
  this module matches `on_event` (and optional location) against events.
  """

  def match(front, events) when is_list(events) do
    defn = front_def(front)

    defn
    |> Map.get("rules", [])
    |> List.wrap()
    |> Enum.flat_map(fn rule ->
      events
      |> Enum.filter(&event_matches?(rule, &1))
      |> Enum.map(&%{rule: rule, event: &1})
    end)
  end

  defp event_matches?(rule, event) do
    on = rule["on_event"]
    loc = rule["location_id"]

    on == event["kind"] and (is_nil(loc) or loc == event["location_id"])
  end

  defp front_def(%{definition: defn}), do: defn
  defp front_def(%{"definition" => defn}), do: defn
  defp front_def(front) when is_map(front), do: front
end
