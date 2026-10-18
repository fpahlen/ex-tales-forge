defmodule TalesForge.NPC.Person do
  @moduledoc """
  A pack NPC as the NPC runtime reads and writes it, from its `characters`
  row (refactor step 10f PR 5; before it, the `npc_instances` row):

    * `personality` is the authored definition (`characters.definition`)
      with the skills from the `skills` column, the only up-to-date copy
      (the definition keeps the scale it was first written with);
    * `runtime_state` is one map of the NPC's state: the row's `runtime`
      plus `"location_id"`, `"mood"`, `"stock"` (the `inventory`) and
      `"relationship_score"` (its relationship to the player character),
      which have columns of their own.

  `attrs/2` turns a changed `runtime_state` back into the row's columns.
  """

  alias TalesForge.Schemas.Character

  @columns ~w(location_id mood stock relationship_score)

  defstruct [:npc_id, :row, personality: %{}, runtime_state: %{}]

  @typedoc "One pack NPC of a session, read from its character row."
  @type t :: %__MODULE__{
          npc_id: String.t(),
          row: Character.t() | nil,
          personality: map(),
          runtime_state: map()
        }

  @doc """
  The NPC of a character `row`. `memories` is the NPC's memory list for a
  row written before this step, which has none in its `runtime`.

      iex> row = %TalesForge.Schemas.Character{slug: "smith", definition: %{"name" => "Hilde", "skills" => %{"smithing" => 8}},
      ...>   skills: %{"smithing" => 40}, location_id: "smithy", mood: "busy", relationships: %{"pc" => 0.5},
      ...>   inventory: [%TalesForge.Schemas.Character.InventoryItem{id: "nail", name: "Nail", quantity: 3, price_copper: 1}],
      ...>   runtime: %{"since_tick" => 7, "memories" => [], "reaction" => %{"emotion" => "calm"}}}
      iex> person = TalesForge.NPC.Person.from_row(row)
      iex> {person.npc_id, person.personality["skills"], person.runtime_state}
      {"smith", %{"smithing" => 40},
       %{"location_id" => "smithy", "mood" => "busy", "relationship_score" => 0.5, "since_tick" => 7, "memories" => [],
         "stock" => [%{"id" => "nail", "name" => "Nail", "quantity" => 3, "price_copper" => 1}]}}
  """
  @spec from_row(Character.t(), [map()]) :: t()
  def from_row(%Character{} = row, memories \\ []) do
    runtime = Map.delete(row.runtime || %{}, "reaction")

    %__MODULE__{
      npc_id: row.slug,
      row: row,
      personality: personality(row),
      runtime_state:
        runtime
        |> Map.put_new("memories", memories)
        |> Map.merge(%{
          "location_id" => row.location_id,
          "mood" => row.mood,
          "stock" => Enum.map(row.inventory || [], &item/1),
          "relationship_score" => relationship_score(row.relationships)
        })
    }
  end

  @doc """
  The row columns for the NPC's `runtime_state`: place, mood, stock,
  relationship (to `pc_slug`, or the one the row already has) and the rest
  as `runtime`, which keeps the row's gut reaction.

      iex> row = %TalesForge.Schemas.Character{relationships: %{"pc" => 0.0}, runtime: %{"reaction" => %{"emotion" => "calm"}}}
      iex> TalesForge.NPC.Person.attrs(row, %{"location_id" => "inn", "mood" => "glad", "stock" => [],
      ...>   "relationship_score" => 0.1, "memories" => []})
      %{location_id: "inn", mood: "glad", inventory: [], relationships: %{"pc" => 0.1},
        runtime: %{"memories" => [], "reaction" => %{"emotion" => "calm"}}}
  """
  @spec attrs(Character.t(), map(), String.t() | nil) :: map()
  def attrs(%Character{} = row, runtime_state, pc_slug \\ nil) do
    %{
      location_id: runtime_state["location_id"],
      mood: runtime_state["mood"],
      inventory: TalesForge.Characters.Attrs.inventory(runtime_state["stock"]),
      relationships:
        relationships(row.relationships, pc_slug, runtime_state["relationship_score"]),
      runtime:
        runtime_state
        |> Map.drop(@columns)
        |> put_reaction((row.runtime || %{})["reaction"])
    }
  end

  @doc "The runtime keys that are columns of the row, not in its `runtime`."
  @spec columns() :: [String.t()]
  def columns, do: @columns

  defp personality(%Character{definition: definition, skills: skills}) do
    definition = definition || %{}

    if skills in [nil, %{}] and not Map.has_key?(definition, "skills"),
      do: definition,
      else: Map.put(definition, "skills", skills || %{})
  end

  @doc """
  The NPC's relationship score to the player character (the one entry of
  its `relationships`), 0.0 when it has none.

      iex> TalesForge.NPC.Person.relationship_score(%{"pc" => 0.25})
      0.25
      iex> TalesForge.NPC.Person.relationship_score(%{})
      0.0
  """
  @spec relationship_score(map() | nil) :: number()
  def relationship_score(relationships)
      when is_map(relationships) and map_size(relationships) > 0,
      do: relationships |> Enum.min_by(&elem(&1, 0)) |> elem(1)

  def relationship_score(_relationships), do: 0.0

  defp relationships(_current, _pc_slug, nil), do: %{}
  defp relationships(_current, pc_slug, score) when is_binary(pc_slug), do: %{pc_slug => score}

  defp relationships(current, nil, score) when is_map(current) and map_size(current) > 0,
    do: %{(current |> Map.keys() |> Enum.min()) => score}

  defp relationships(_current, nil, _score), do: %{}

  defp put_reaction(runtime, reaction) when is_map(reaction),
    do: Map.put(runtime, "reaction", reaction)

  defp put_reaction(runtime, _reaction), do: runtime

  # A stock item as the NPC runtime has it: string keys, no unset fields.
  defp item(%{__struct__: _} = item), do: item |> Map.from_struct() |> item()

  defp item(item) when is_map(item),
    do: for({k, v} <- item, not is_nil(v), into: %{}, do: {to_string(k), v})
end
