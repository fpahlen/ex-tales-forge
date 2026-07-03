defmodule TalesForge.Actions.NPC.OnOverheard do
  @moduledoc false

  use Jido.Action,
    name: "npc_on_overheard",
    description: "Record overheard conversation snippets",
    schema: []

  alias TalesForge.Actions.NPC.UpdateMemory

  @impl true
  def run(_params, context) do
    data = normalize_keys(context.signal.data)
    speaker = Map.get(data, "speaker", "someone")
    message = Map.get(data, "message", "")
    world_tick = Map.get(data, "world_tick", 0)

    if String.trim(message) == "" do
      {:ok, %{}}
    else
      summary = "Overheard #{speaker}: #{String.slice(message, 0, 100)}"

      UpdateMemory.run(%{summary: summary, world_tick: world_tick}, context)
    end
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
