defmodule TalesForge.Canon.Seed do
  @moduledoc """
  Canon: the world seed of one adventure, read from the pack files in
  `priv/adventures/<id>/`.

  This module is the only canon reader of the session review
  (`TalesForge.Canon`). It reads the places and NPCs of the pack through
  `TalesForge.Game.Pack` and the typed facts of `world_agents.json` through
  `TalesForge.World.definitions/1`. A later seed format can replace this
  module and keep the struct.
  """

  alias TalesForge.Game.Pack
  alias TalesForge.Game.World, as: GameWorld
  alias TalesForge.World

  @typedoc "A place of the seed: its name and its sorted exits."
  @type place :: %{name: String.t() | nil, exits: [String.t()]}

  @typedoc "An entity of the seed that holds facts."
  @type entity :: %{
          kind: :location | :person | :item | :npc,
          name: String.t() | nil,
          facts: [String.t()]
        }

  @type t :: %__MODULE__{
          adventure_id: String.t() | nil,
          places: %{String.t() => place()},
          entities: %{String.t() => entity()}
        }

  defstruct adventure_id: nil, places: %{}, entities: %{}

  @doc """
  Reads the seed that a session started from. The adventure, the variant and
  the features come from the session's `world_state`.
  """
  @spec load(map()) :: t()
  def load(world_state) when is_map(world_state) do
    adventure_id = world_state["adventure_id"]
    {locations, npcs} = pack(adventure_id, world_state)

    places = Map.new(locations, fn {id, loc} -> {id, place(loc)} end)

    npc_entities =
      Map.new(npcs, fn npc ->
        {npc["id"], %{kind: :npc, name: npc["name"], facts: []}}
      end)

    defs = World.definitions(adventure_id)

    agent_entities =
      [locations: defs.locations, persons: defs.persons, items: defs.items]
      |> Enum.flat_map(fn {group, by_id} ->
        Enum.map(by_id, fn {id, d} -> {id, entity(group, d)} end)
      end)
      |> Map.new()

    %__MODULE__{
      adventure_id: adventure_id,
      places: places,
      entities: Map.merge(npc_entities, agent_entities, &merge_entity/3)
    }
  end

  @doc "Returns a place in the shape that `load/1` uses (name and sorted exits)."
  @spec place(map()) :: place()
  def place(loc) when is_map(loc) do
    %{name: loc["name"], exits: loc |> Map.get("exits", []) |> List.wrap() |> Enum.sort()}
  end

  defp pack(adventure_id, world_state) when is_binary(adventure_id) do
    pack =
      Pack.load(adventure_id, List.wrap(world_state["features"]))

    {pack.locations, pack.npcs}
  rescue
    ArgumentError -> fallback(adventure_id)
  end

  defp pack(_adventure_id, _world_state), do: {%{}, []}

  defp fallback("crossroads_ledger"), do: {GameWorld.locations(), Map.values(GameWorld.npcs())}
  defp fallback(_adventure_id), do: {%{}, []}

  defp entity(group, d) do
    kind =
      case group do
        :locations -> :location
        :persons -> :person
        :items -> :item
      end

    %{kind: kind, name: d["name"], facts: Enum.map(d["facts"] || [], &normalize(&1["text"]))}
  end

  defp merge_entity(_id, npc, agent), do: %{agent | name: agent.name || npc.name}

  @doc """
  Normalises a fact text for comparison: trimmed, lower case, one space.

      iex> TalesForge.Canon.Seed.normalize("  The Inn  is OLD. ")
      "the inn is old."
  """
  @spec normalize(term()) :: String.t()
  def normalize(text) do
    text |> to_string() |> String.downcase() |> String.split() |> Enum.join(" ")
  end
end
