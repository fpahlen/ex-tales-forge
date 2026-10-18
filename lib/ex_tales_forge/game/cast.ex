defmodule TalesForge.Game.Cast do
  @moduledoc """
  The session's GM characters as one map, slug to `%TalesForge.GameCharacter{}`:
  the NPCs and the minor foes (refactor step 10f PR 4). It replaces
  `world_state["npc_state"]` and `"npc_moods"`, which are no longer read or
  written. `TalesForge.Characters.cast/1` loads it from the `characters`
  rows (an NPC's name, place, mood and concern from its NPC instance until
  step 10f PR 5); the turn changes it (a wound, a new minor foe, a gut
  reaction) and `TalesForge.Characters.write_multi/2` saves it on the rows.

  A leaf module of pure helpers: a minor foe is a character like any other
  here, and nothing reads its `lifetime`.
  """

  alias TalesForge.GameCharacter

  @typedoc "The GM characters of a session by slug."
  @type t :: %{String.t() => GameCharacter.t()}

  @doc """
  True when the character `id` is dead.

      iex> cast = %{"marta_kellen" => %TalesForge.GameCharacter{slug: "marta_kellen", vitality: "dead"}}
      iex> {TalesForge.Game.Cast.dead?(cast, "marta_kellen"), TalesForge.Game.Cast.dead?(cast, "osric")}
      {true, false}
  """
  @spec dead?(t(), String.t()) :: boolean()
  def dead?(cast, id) when is_map(cast), do: match?(%GameCharacter{vitality: "dead"}, cast[id])

  @doc "The name of `id`, or `id` when the cast has no name for it."
  @spec name(t(), String.t()) :: String.t()
  def name(cast, id) do
    case cast[id] do
      %GameCharacter{name: name} when is_binary(name) -> name
      _ -> id
    end
  end

  @doc "The characters, ordered by slug."
  @spec sorted(t()) :: [GameCharacter.t()]
  def sorted(cast), do: cast |> Map.values() |> Enum.sort_by(& &1.slug)

  @doc """
  The slugs of the living characters at `location_id` that are not in
  `except` (the present NPCs), ordered: the people of a scene whom
  `present_npcs` does not list, such as a minor foe.

      iex> cast = %{
      ...>   "foe_thug" => %TalesForge.GameCharacter{slug: "foe_thug", location_id: "yard"},
      ...>   "foe_guard" => %TalesForge.GameCharacter{slug: "foe_guard", location_id: "yard", vitality: "dead"},
      ...>   "innkeep" => %TalesForge.GameCharacter{slug: "innkeep", location_id: "yard"}}
      iex> TalesForge.Game.Cast.others_here(cast, "yard", ["innkeep"])
      ["foe_thug"]
  """
  @spec others_here(t(), String.t() | nil, [String.t()]) :: [String.t()]
  def others_here(cast, location_id, except) do
    for %GameCharacter{slug: slug, location_id: ^location_id, vitality: vitality} <- sorted(cast),
        vitality != "dead",
        slug not in except,
        do: slug
  end

  @doc """
  The gut reaction (the latest `{:feel, mood}` Intention) of each character
  that has one.

      iex> cast = %{"innkeep" => %TalesForge.GameCharacter{runtime: %{"reaction" => %{"emotion" => "wary"}}},
      ...>   "smith" => %TalesForge.GameCharacter{}}
      iex> TalesForge.Game.Cast.reactions(cast)
      %{"innkeep" => %{"emotion" => "wary"}}
  """
  @spec reactions(t()) :: %{String.t() => map()}
  def reactions(cast) do
    for {id, %GameCharacter{runtime: %{"reaction" => %{} = reaction}}} <- cast,
        into: %{},
        do: {id, reaction}
  end

  @doc "The gut reaction of `id`, or nil."
  @spec reaction(t(), String.t()) :: map() | nil
  def reaction(cast, id), do: Map.get(reactions(Map.take(cast, [id])), id)

  @doc """
  The character as the intent context and the play page show it: id, name,
  role, disposition (its mood), concern priority, portrait and place.

      iex> TalesForge.Game.Cast.details(%TalesForge.GameCharacter{slug: "innkeep", name: "Brenna Holt",
      ...>   role: "innkeeper", mood: "warm", location_id: "valley_inn",
      ...>   runtime: %{"current_concern" => %{"priority" => 6}}})
      %{"id" => "innkeep", "name" => "Brenna Holt", "role" => "innkeeper", "disposition" => "warm",
        "concern_priority" => 6, "portrait_url" => nil, "location_id" => "valley_inn"}
  """
  @spec details(GameCharacter.t()) :: map()
  def details(%GameCharacter{} = gc) do
    %{
      "id" => gc.slug,
      "name" => gc.name || gc.slug,
      "role" => gc.role || "present",
      "disposition" => gc.mood || "neutral",
      "concern_priority" => concern_priority(gc.runtime["current_concern"]),
      "portrait_url" => gc.extra["portrait_url"],
      "location_id" => gc.location_id
    }
  end

  defp concern_priority(%{} = concern), do: Map.get(concern, "priority", 0)
  defp concern_priority(_concern), do: 0
end
