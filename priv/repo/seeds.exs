# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Phase 2+: Seeds also populate Ash authoring tables from priv/npcs (and future adventures).
# Run after migrations. Safe to re-run (uses upsert-like behavior via identities).

import Ash.Expr

alias TalesForge.Authoring.NpcDefinition

npc_dir = Path.join(:code.priv_dir(:ex_tales_forge), "npcs")

if File.exists?(npc_dir) do
  npc_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".json"))
  |> Enum.each(fn file ->
    path = Path.join(npc_dir, file)
    {:ok, defn} = path |> File.read!() |> Jason.decode()

    npc_id = Map.get(defn, "id") || Path.rootname(file)

    attrs = %{
      npc_id: npc_id,
      name: Map.get(defn, "name", npc_id),
      race: Map.get(defn, "race", "human"),
      role: Map.get(defn, "role"),
      default_location_id: Map.get(defn, "default_location_id"),
      appearance: Map.get(defn, "appearance"),
      personality: Map.get(defn, "personality"),
      backstory: Map.get(defn, "backstory"),
      motivations: Map.get(defn, "motivations", %{}),
      stock: Map.get(defn, "stock", []),
      portrait_url: Map.get(defn, "portrait_url")
    }

    # Upsert-style for seeds: try create, fallback to update by npc_id query if duplicate.
    case NpcDefinition.create(attrs) do
      {:ok, _} ->
        :ok

      {:error, %{errors: [%Ash.Error.Changes.InvalidChanges{fields: [:npc_id]} | _]}} ->
        # Already exists — update it
        case Ash.read!(NpcDefinition, filter: expr(npc_id == ^npc_id), load: []) do
          [existing | _] -> NpcDefinition.update!(existing, attrs)
          _ -> :ok
        end

      other ->
        IO.inspect(other, label: "Seed NPC #{npc_id} result")
    end

    IO.puts("Seeded/updated authoring NPC: #{npc_id}")
  end)
end

# Seed a basic Adventure record (Crossroads Ledger) using known data.
# This enables future "create session from adventure" flows.
adventure_attrs = %{
  adventure_id: "crossroads_ledger",
  name: "Crossroads Ledger",
  synopsis:
    "A missing merchant ledger draws suspicious attention to Crossroads Hamlet. Begin at The Weary Pilgrim tavern and follow whispers of theft and pointed questions.",
  starting_location_id: "weary_pilgrim",
  initial_present_npc_ids: ["marta_kellen"]
}

case TalesForge.Authoring.Adventure.create(adventure_attrs) do
  {:ok, _} ->
    IO.puts("Seeded Adventure: crossroads_ledger")

  {:error, _} ->
    # Likely already exists (identity)
    IO.puts("Adventure crossroads_ledger already present (or creation skipped)")
end

# Seed Locations for the adventure (from the legacy World data during transition).
# In future this will come from authored files or full adventure editor.
locations_data = [
  %{
    location_id: "weary_pilgrim",
    adventure_id: "crossroads_ledger",
    name: "The Weary Pilgrim",
    exits: ["crossroads_square", "pilgrim_cellar"],
    blurb:
      "A low-ceilinged tavern smelling of woodsmoke and spilled ale. Chalk marks score the slate behind the bar.",
    fixtures: ["chalked slate", "bar counter", "hearth"],
    ground_items: [],
    scene_image_url: nil
  },
  %{
    location_id: "crossroads_square",
    adventure_id: "crossroads_ledger",
    name: "Crossroads Square",
    exits: ["weary_pilgrim", "kings_road"],
    blurb:
      "Mud and cobbles churned by cart wheels. Merchants hawk wares beneath a weathered signpost.",
    fixtures: ["signpost", "merchant stalls"],
    ground_items: [],
    scene_image_url: nil
  },
  %{
    location_id: "pilgrim_cellar",
    adventure_id: "crossroads_ledger",
    name: "Pilgrim Cellar",
    exits: ["weary_pilgrim"],
    blurb:
      "Cool stone steps descend to casks and shadows. The air tastes of wine and damp mortar.",
    fixtures: ["wine casks", "mortar seam"],
    ground_items: [],
    scene_image_url: nil
  }
]

Enum.each(locations_data, fn loc_attrs ->
  case TalesForge.Authoring.Location.create(loc_attrs) do
    {:ok, _} -> IO.puts("Seeded Location: #{loc_attrs.location_id}")
    {:error, _} -> IO.puts("Location #{loc_attrs.location_id} already present or skipped")
  end
end)

# Existing runtime seeds or other data can be added below.
# (Game world seeds happen at session create time via Game.World / NPC.)
