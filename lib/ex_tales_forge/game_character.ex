defmodule TalesForge.GameCharacter do
  @moduledoc """
  One character in a turn, player character or NPC alike (refactor plan step
  10). A player character is a GameCharacter whose intentions come from a
  human; an NPC is one whose intentions come from the GM or the system.
  Nothing else differs, so this struct has no controller.

  `from_schema/1` reads a `TalesForge.Schemas.GameCharacter` row and `to_sheet/1`
  gives the sheet map the turn plays on (`world_state["character"]`). Every
  sheet key has a column, so `to_sheet/1` of a mirrored row is the sheet
  that was mirrored. `class`, `creation`, `reflecting` and
  `improved_since_rest` are keys a sheet may lack: nil means it has none.
  Only a sheet the columns can't hold (an item without a name, a skill that
  is not a number) leaves anything in the row's `runtime["sheet"]`
  (`extra` and `missing`, written by `TalesForge.GameCharacter.Store`' mirror).

  `lifetime` is how long the character's row lives (`:persistent`, or
  `:scene` for a minor foe). Only the cleanup at the end of a scene reads
  it (`TalesForge.GameCharacter.Store.end_scene_multi/2`); the rules, the prompts and
  the play page treat every character alike.
  """

  alias TalesForge.Schemas
  @stat_keys ~w(STR DEX CON INT WIS CHA)

  # Row columns taken as they are, and map columns that may be nil.
  @plain ~w(id slug name race role location_id maslow_level wounds wound_max vitality mood
            class creation reflecting improved_since_rest lifetime)a

  # Sheet keys a sheet may lack: `to_sheet/1` gives them only when not nil.
  @optional ~w(class creation reflecting improved_since_rest)
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
            class: nil,
            creation: nil,
            reflecting: nil,
            improved_since_rest: nil,
            mood: nil,
            relationships: %{},
            runtime: %{},
            minor: false,
            lifetime: :persistent,
            extra: %{},
            missing: []

  @type t :: %__MODULE__{}

  # Sheet keys (a world_state sheet, an NPC fighter profile, a minor foe)
  # and the field each one sets in `from_sheet/1`.
  @sheet_fields [
    {"id", :slug},
    {"name", :name},
    {"race", :race},
    {"role", :role},
    {"location_id", :location_id},
    {"stats", :stats},
    {"skills", :skills},
    {"ocean", :ocean},
    {"maslow", :maslow_level},
    {"concerns", :concerns},
    {"inventory", :inventory},
    {"coins", :coins},
    {"wounds", :wounds},
    {"wound_max", :wound_max},
    {"vitality", :vitality},
    {"learning_points", :learning_points},
    {"learning_failures", :learning_failures},
    {"minor", :minor},
    {"class", :class},
    {"creation", :creation},
    {"reflecting", :reflecting},
    {"improved_since_rest", :improved_since_rest}
  ]

  @doc """
  The GameCharacter of a `characters` row. `runtime["sheet"]` becomes
  `extra` and `missing`; the rest of `runtime` stays in `runtime`. A minor
  foe's row keeps its sheet in `definition`, so `minor` comes from there.

      iex> row = %TalesForge.Schemas.GameCharacter{slug: "elara_voss", name: "Elara Voss",
      ...>   stats: %TalesForge.Schemas.GameCharacter.Stats{str: 12},
      ...>   class: "bard", runtime: %{"sheet" => %{"extra" => %{}, "missing" => []}}}
      iex> gc = TalesForge.GameCharacter.from_schema(row)
      iex> {gc.slug, gc.stats["STR"], gc.class, gc.extra, gc.runtime}
      {"elara_voss", 12, "bard", %{}, %{}}
  """
  @spec from_schema(Schemas.GameCharacter.t()) :: t()
  def from_schema(%Schemas.GameCharacter{} = row) do
    %__MODULE__{}
    |> struct(Map.take(row, @plain))
    |> struct(for k <- @maps, into: %{}, do: {k, Map.get(row, k) || %{}})
    |> struct(embeds(row))
    |> struct(sheet_runtime_fields(row.runtime || %{}))
    |> struct(minor: (row.definition || %{})["minor"] == true)
  end

  defp embeds(%Schemas.GameCharacter{} = row) do
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
  The GameCharacter of a sheet map: the player character's
  `world_state["character"]`, an NPC's fighter profile or a minor foe. Each known key sets its field as it is (no casting), a
  `current_concern` goes to `runtime`, and `extra` and `missing` keep the
  rest, so `to_sheet(from_sheet(sheet)) === sheet` for every sheet. A key
  the sheet lacks keeps the field's default.

      iex> gc = TalesForge.GameCharacter.from_sheet(%{"id" => "foe_thug", "name" => "a thug",
      ...>   "minor" => true, "role" => "minor foe", "stats" => %{"CON" => 9}})
      iex> {gc.slug, gc.minor, gc.wounds}
      {"foe_thug", true, 0}
      iex> TalesForge.GameCharacter.to_sheet(gc)
      %{"id" => "foe_thug", "name" => "a thug", "minor" => true, "role" => "minor foe",
        "stats" => %{"CON" => 9}}
  """
  @spec from_sheet(map()) :: t()
  def from_sheet(sheet) when is_map(sheet) do
    fields =
      for {key, field} <- @sheet_fields,
          Map.has_key?(sheet, key),
          into: %{},
          do: {field, sheet[key]}

    gc = struct(__MODULE__, Map.put(fields, :runtime, Map.take(sheet, ["current_concern"])))
    %{"extra" => extra, "missing" => missing} = sheet_runtime(gc, sheet)
    %{gc | extra: extra, missing: missing}
  end

  @doc """
  Sets fields and drops their sheet keys from `extra` and `missing`, so
  `to_sheet/1` gives the new values.

      iex> gc = TalesForge.GameCharacter.from_sheet(%{"id" => "ada"})
      iex> TalesForge.GameCharacter.to_sheet(TalesForge.GameCharacter.put(gc, wounds: 1))
      %{"id" => "ada", "wounds" => 1}
  """
  @spec put(t(), keyword()) :: t()
  def put(%__MODULE__{} = gc, fields) when is_list(fields) do
    keys = for {field, _} <- fields, {key, ^field} <- @sheet_fields, do: key
    gc = struct!(gc, fields)
    %{gc | extra: Map.drop(gc.extra, keys), missing: gc.missing -- keys}
  end

  @doc "The sheet value of `key` (a `sheet_keys/0` key), nil when the sheet lacks it."
  @spec sheet_value(t(), String.t()) :: term()
  def sheet_value(%__MODULE__{missing: missing} = gc, key) do
    if key in missing, do: nil, else: Map.get(to_sheet(gc), key)
  end

  @doc """
  The sheet map of a GameCharacter, as the turn reads it from
  `world_state["character"]`: the sheet columns, then `extra` on top,
  without the `missing` keys.

      iex> TalesForge.GameCharacter.to_sheet(%TalesForge.GameCharacter{slug: "pc_ada", name: "Ada",
      ...>   class: "thief", missing: ["learning_failures"]})["class"]
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
    |> Map.merge(optional(gc))
    |> Map.merge(gc.extra)
    |> Map.drop(gc.missing)
  end

  @doc "The sheet keys `to_sheet/1` always gives (a nil optional key it leaves out)."
  @spec sheet_keys() :: [String.t()]
  def sheet_keys,
    do: ~w(id name race location_id stats skills inventory coins wounds wound_max vitality
           learning_points learning_failures)

  @doc """
  What `runtime["sheet"]` must hold so that `to_sheet/1` of `gc` is `sheet`:
  each sheet key that `to_sheet/1` doesn't give back as it is (strictly, so
  `5` is not `5.0`, and a key with a nil value is kept) and the column keys
  the sheet does not have.
  """
  @spec sheet_runtime(t(), map()) :: map()
  def sheet_runtime(%__MODULE__{} = gc, sheet) when is_map(sheet) do
    built = to_sheet(%{gc | extra: %{}, missing: []})

    %{
      "extra" =>
        for({k, v} <- sheet, not Map.has_key?(built, k) or built[k] !== v, into: %{}, do: {k, v}),
      "missing" => Enum.reject(sheet_keys(), &Map.has_key?(sheet, &1))
    }
  end

  defp optional(%__MODULE__{} = gc) do
    @optional
    |> Map.new(&{&1, Map.fetch!(gc, String.to_existing_atom(&1))})
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp stats(nil), do: %{}

  defp stats(%Schemas.GameCharacter.Stats{} = s) do
    @stat_keys |> Enum.zip([s.str, s.dex, s.con, s.int, s.wis, s.cha]) |> Map.new()
  end

  # An item as the sheet has it: no nil price, copper value or equipped flag.
  defp item(%Schemas.GameCharacter.InventoryItem{} = i) do
    i
    |> embed_map()
    |> Map.reject(fn {k, v} -> k in ~w(price_copper copper_value equipped) and is_nil(v) end)
  end

  defp embed_map(nil), do: %{}

  defp embed_map(%_{} = embed) do
    embed |> Map.from_struct() |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
