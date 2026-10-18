defmodule TalesForge.NPC.Seed do
  @moduledoc """
  The `characters` row of a pack NPC when a session is seeded
  (`TalesForge.NPC.seed_session/1`): its definition and first runtime
  state as columns.
  """

  alias TalesForge.Characters.{Attrs, Levers}
  alias TalesForge.NPC.Person
  alias TalesForge.Schemas.Character

  @maslow_by_need %{
    "survival" => "physiological",
    "physiological" => "physiological",
    "safety" => "safety",
    "belonging" => "belonging",
    "love" => "belonging",
    "esteem" => "esteem",
    "self_actualisation" => "self_actualisation",
    "self_actualization" => "self_actualisation"
  }

  @doc """
  Character attrs for a pack NPC (controller `gm`) seeded with its
  definition and first runtime state (`TalesForge.NPC.seed_session/1`).
  Stats default to 10 and OCEAN to 5 when the definition has none; without
  `maslow` the Maslow level is read from `motivations.primary_need`, else
  `"safety"`. The relationship to the player character is set when its row
  is written (`TalesForge.Characters.seed_session/2`).
  """
  @spec attrs(Person.t(), integer()) :: map()
  def attrs(%Person{} = inst, tick) do
    definition = inst.personality || %{}
    runtime = inst.runtime_state || %{}

    inst
    |> npc_identity(definition)
    |> Map.merge(%{
      location_id: runtime["location_id"] || definition["default_location_id"],
      stats: Character.Stats.from_sheet(definition["stats"]),
      skills: Attrs.int_map(definition["skills"]),
      ocean: Levers.ocean_source(definition),
      maslow_level: maslow_level(definition),
      maslow_since_tick: tick,
      concerns: npc_concerns(definition, runtime, tick),
      inventory: Attrs.inventory(runtime["stock"]),
      coins: definition["coins"] || %{},
      mood: runtime["mood"],
      relationships: %{},
      runtime: Map.drop(runtime, Person.columns())
    })
  end

  # Who the NPC is: the columns set from its definition.
  defp npc_identity(%Person{npc_id: npc_id}, definition) do
    %{
      slug: npc_id,
      controller: "gm",
      controller_ref: nil,
      owner_player_id: nil,
      origin: %{"source" => "pack", "definition_id" => npc_id},
      definition: definition,
      name: definition["name"] || npc_id,
      race: definition["race"],
      role: definition["role"]
    }
  end

  defp maslow_level(definition) do
    definition["maslow"] ||
      Map.get(@maslow_by_need, get_in(definition, ["motivations", "primary_need"])) ||
      "safety"
  end

  # Sessions from before the pack levers have no `concerns`: use the
  # current_concern so the row still says what the NPC is after.
  defp npc_concerns(%{"concerns" => list}, _runtime, tick) when is_list(list),
    do: Attrs.concerns(list, tick)

  defp npc_concerns(_definition, runtime, tick) do
    case runtime["current_concern"] do
      %{"focus" => focus} = c when is_binary(focus) and focus != "" ->
        [
          %{
            "text" => focus,
            "focus" => focus,
            "priority" => clamp_priority(c["priority"]),
            "since_tick" => c["since_tick"] || tick
          }
        ]

      _ ->
        []
    end
  end

  defp clamp_priority(p) when is_integer(p), do: p |> max(1) |> min(10)
  defp clamp_priority(_), do: 5
end
