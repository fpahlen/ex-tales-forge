defmodule TalesForge.GameCharacter do
  @moduledoc """
  One character in a turn, player character or NPC alike (refactor plan step
  10). A player character is a GameCharacter whose intentions come from a
  human; an NPC is one whose intentions come from the GM or the system.
  Nothing else differs, so this struct has no controller.

  `from_schema/1` reads a `TalesForge.Schemas.Character` row and `to_sheet/1`
  gives the sheet map the turn plays on (`world_state["character"]`). The
  row keeps what its columns cannot hold in `runtime["sheet"]` (written by
  `TalesForge.Characters`' mirror): `extra`, the sheet keys whose value the
  columns don't round-trip (`class`, `reflecting`, `improved_since_rest`,
  …), and `missing`, the column keys the sheet did not have. So `to_sheet/1`
  of a mirrored row is the sheet that was mirrored.
  """

  alias TalesForge.Schemas.Character

  @stat_keys ~w(STR DEX CON INT WIS CHA)

  # Row columns taken as they are, and map columns that may be nil.
  @plain ~w(id slug name race role location_id maslow_level wounds wound_max vitality mood)a
  @maps ~w(skills coins learning_points learning_failures relationships)a

  defstruct id: nil,
            slug: nil,
            name: nil,
            race: nil,
            role: nil,
            location_id: nil,
            stats: %{},
            skills: %{},
            ocean: %{},
            maslow_level: nil,
            concerns: [],
            inventory: [],
            coins: %{},
            wounds: 0,
            wound_max: 3,
            vitality: "ok",
            learning_points: %{},
            learning_failures: %{},
            mood: nil,
            relationships: %{},
            runtime: %{},
            extra: %{},
            missing: []

  @type t :: %__MODULE__{}

  @doc """
  The GameCharacter of a `characters` row. `runtime["sheet"]` becomes
  `extra` and `missing`; the rest of `runtime` stays in `runtime`.

      iex> row = %TalesForge.Schemas.Character{slug: "elara_voss", name: "Elara Voss",
      ...>   stats: %TalesForge.Schemas.Character.Stats{str: 12},
      ...>   runtime: %{"sheet" => %{"extra" => %{"class" => "bard"}, "missing" => []}}}
      iex> gc = TalesForge.GameCharacter.from_schema(row)
      iex> {gc.slug, gc.stats["STR"], gc.extra, gc.runtime}
      {"elara_voss", 12, %{"class" => "bard"}, %{}}
  """
  @spec from_schema(Character.t()) :: t()
  def from_schema(%Character{} = row) do
    %__MODULE__{}
    |> struct(Map.take(row, @plain))
    |> struct(for k <- @maps, into: %{}, do: {k, Map.get(row, k) || %{}})
    |> struct(embeds(row))
    |> struct(sheet_runtime_fields(row.runtime || %{}))
  end

  defp embeds(%Character{} = row) do
    %{
      stats: stats(row.stats),
      ocean: embed_map(row.ocean),
      concerns: Enum.map(row.concerns || [], &embed_map/1),
      inventory: Enum.map(row.inventory || [], &item/1)
    }
  end

  defp sheet_runtime_fields(runtime) do
    sheet = runtime["sheet"] || %{}

    %{
      runtime: Map.delete(runtime, "sheet"),
      extra: sheet["extra"] || %{},
      missing: sheet["missing"] || []
    }
  end

  @doc """
  The sheet map of a GameCharacter, as the turn reads it from
  `world_state["character"]`: the sheet columns, then `extra` on top,
  without the `missing` keys.

      iex> TalesForge.GameCharacter.to_sheet(%TalesForge.GameCharacter{slug: "pc_ada", name: "Ada",
      ...>   extra: %{"class" => "thief"}, missing: ["learning_failures"]})["class"]
      "thief"
  """
  @spec to_sheet(t()) :: map()
  def to_sheet(%__MODULE__{} = gc) do
    %{
      "id" => gc.slug,
      "name" => gc.name,
      "race" => gc.race,
      "location_id" => gc.location_id,
      "stats" => gc.stats,
      "skills" => gc.skills,
      "inventory" => gc.inventory,
      "coins" => gc.coins,
      "wounds" => gc.wounds,
      "wound_max" => gc.wound_max,
      "vitality" => gc.vitality,
      "learning_points" => gc.learning_points,
      "learning_failures" => gc.learning_failures
    }
    |> Map.merge(gc.extra)
    |> Map.drop(gc.missing)
  end

  @doc "The sheet keys `to_sheet/1` builds from columns."
  @spec sheet_keys() :: [String.t()]
  def sheet_keys,
    do: ~w(id name race location_id stats skills inventory coins wounds wound_max vitality
           learning_points learning_failures)

  @doc """
  What `runtime["sheet"]` must hold so that `to_sheet/1` of `gc` is `sheet`:
  each sheet key whose value differs (strictly, so `5` is not `5.0`) and the
  column keys the sheet does not have.
  """
  @spec sheet_runtime(t(), map()) :: map()
  def sheet_runtime(%__MODULE__{} = gc, sheet) when is_map(sheet) do
    built = to_sheet(%{gc | extra: %{}, missing: []})

    %{
      "extra" => for({k, v} <- sheet, Map.get(built, k) !== v, into: %{}, do: {k, v}),
      "missing" => Enum.reject(sheet_keys(), &Map.has_key?(sheet, &1))
    }
  end

  defp stats(nil), do: %{}

  defp stats(%Character.Stats{} = s) do
    @stat_keys |> Enum.zip([s.str, s.dex, s.con, s.int, s.wis, s.cha]) |> Map.new()
  end

  # An item as the sheet has it: no nil price, copper value or equipped flag.
  defp item(%Character.InventoryItem{} = i) do
    i
    |> embed_map()
    |> Map.reject(fn {k, v} -> k in ~w(price_copper copper_value equipped) and is_nil(v) end)
  end

  defp embed_map(nil), do: %{}

  defp embed_map(%_{} = embed) do
    embed |> Map.from_struct() |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
