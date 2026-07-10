defmodule TalesForge.Authoring.Importer do
  @moduledoc """
  Imports "game packs" from a *generic but conventional* folder of linked Markdown files
  into Ash Authoring resources (Adventure, Location, NpcDefinition).

  The top-level folder name **is the name of the game** (e.g. "Drakar och Demoner",
  "Gothic London").

  ## Design Principles
  1. Rather strict structure for "convention over configuration" links.
  2. Lightweight (minimal YAML frontmatter + rich bodies).
  3. Back-and-forth between system and developer ("Do you mean to create a Character called ...?").
  4. See 1.
  5. `rules/` is mandatory in every game pack (hierarchical content is fine). Rules are easily copied.
  6. Explicit "import this pack" with confirmations.

  ## Recommended "In-Between" Generic Structure

      "Gothic London"/                 # or "Drakar och Demoner" — the GAME name
      ├── README.md or SUMMARY.md
      ├── rules/                       # REQUIRED (deep hierarchy supported)
      │   ├── 00-introduction/
      │   ├── 02-character-creation/
      │   ├── bestiary/
      │   └── ...
      ├── adventures/ or scenarios/
      │   └── the-ripper-case/
      │       └── adventure.md
      ├── places/ or locations/ or sites/ or world/   # → Location records
      ├── characters/ or cast/ or npcs/ or bestiary/   # → NpcDefinition
      ├── roster/ or pregens/
      ├── examples/
      ├── templates/
      ├── assets/
      └── prompts/

  Conventional container names are recognized automatically. You can also use
  frontmatter `type: place | character | adventure | ...` to guide classification.

  ## Markdown File Example

      ---
      id: the-lantern
      name: The Leaky Lantern
      exits: [docks, square]
      type: place
      ---
      # The Leaky Lantern

      A smoky tavern...

      See [[Jack]] or go to the [[Docks]].

  - `[[links]]` resolve by convention across the tree (prefer same container).
  - The importer + interactive confirmer + final confirmation step are unchanged in spirit.

  After a confirmed import the Ash records are the working copy. Session creation
  performs the further mutable copy into the live game state.
  """

  require Logger

  import Ash.Query

  alias TalesForge.Authoring.{Adventure, Location, NpcDefinition}

  # Example rule files shown in error messages for user guidance.
  # (Not used for enforcement.)

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Validates that the given directory follows the (now more generic) pack structure.

  Returns :ok or {:error, reasons}.
  Enforces point 5: a `rules/` directory must exist and contain at least one .md file.
  Other content (places, characters, adventures...) is discovered flexibly.
  """
  def validate_structure(pack_dir) when is_binary(pack_dir) do
    with :ok <- check_exists(pack_dir),
         :ok <- check_rules_mandated(pack_dir),
         :ok <- check_has_content(pack_dir) do
      :ok
    end
  end

  @doc """
  Pure parse of the pack directory into proposed structured data.

  Does **not** write to Ash. Returns {:ok, pack} where pack contains:
    - :adventure_id, :name, :synopsis, :starting_location_id, :initial_present_npc_ids
    - :rules (map of relative_path => content — supports deep trees)
    - :locations (list of parsed place/location maps — discovered from places/locations/sites/world/ etc.)
    - :npcs (list of parsed character/npc/cast/bestiary maps)
    - :roster
    - :discovered_links
    - :source_dir

  Discovery uses conventional directory names + optional frontmatter `type:`.
  This is the "lightweight" parse step. Interactive confirmation happens after.
  """
  def parse_pack(pack_dir) do
    with :ok <- validate_structure(pack_dir),
         {:ok, adventure_meta} <- parse_adventure_meta(pack_dir),
         {:ok, rules} <- load_rules_pack(pack_dir),
         {:ok, places} <- parse_places_section(pack_dir),
         {:ok, characters} <- parse_characters_section(pack_dir),
         {:ok, roster} <- parse_section(pack_dir, "player_characters", :roster, optional: true) do
      # For downstream compatibility we still expose :locations and :npcs
      # (populated from any of the recognized generic containers).
      pack = %{
        source_dir: pack_dir,
        adventure_id: adventure_meta.adventure_id || Path.basename(pack_dir),
        name: adventure_meta.name,
        synopsis: adventure_meta.synopsis,
        starting_location_id: adventure_meta.starting_location_id,
        initial_present_npc_ids: adventure_meta.initial_present_npc_ids || [],
        rules: rules,
        locations: places,
        npcs: characters,
        roster: roster,
        discovered_links:
          (Enum.flat_map(places, & &1.links) ++ Enum.flat_map(characters, & &1.links))
          |> Enum.uniq()
      }

      {:ok, pack}
    end
  end

  # Generic discovery for "location-like" content.
  # Recognizes many conventional names so packs can be "Drakar och Demoner" style or "Gothic London".
  defp parse_places_section(pack_dir) do
    candidates = ["places", "place", "locations", "location", "sites", "site", "world"]
    parse_first_matching_section(pack_dir, candidates, :location, optional: true)
  end

  # Generic discovery for character/NPC/cast/bestiary content.
  defp parse_characters_section(pack_dir) do
    candidates = [
      "characters",
      "character",
      "cast",
      "npcs",
      "npc",
      "bestiary",
      "monsters",
      "creatures"
    ]

    parse_first_matching_section(pack_dir, candidates, :npc, optional: true)
  end

  defp parse_first_matching_section(pack_dir, candidates, entity_type, opts) do
    case Enum.find(candidates, fn c -> File.dir?(Path.join(pack_dir, c)) end) do
      nil ->
        if Keyword.get(opts || [], :optional, false) do
          {:ok, []}
        else
          {:error,
           "No recognized #{entity_type} container found (tried: #{Enum.join(candidates, ", ")})"}
        end

      dir_name ->
        parse_section(pack_dir, dir_name, entity_type, opts || [])
    end
  end

  @doc """
  Interactive import of a pack.

  - Parses the pack.
  - For each significant entity, calls the `confirmer` with a proposal.
    The confirmer receives maps like:

        %{
          type: :npc,
          question: "Do you mean to create a Character called Jack The Ripper?",
          proposed: %{npc_id: "jack_the_ripper", name: "Jack The Ripper", ...},
          source_file: "characters/jack-the-ripper.md"
        }

    Confirmer should return:
      - true / {:ok, confirmed_attrs}  → accept (optionally with edits)
      - false / {:skip, reason}        → skip this entity
      - {:error, reason}               → abort

  - After all confirmations, performs a final confirmation step.
  - On full success, writes to Ash (Adventure + child Locations + NpcDefinitions).

  `opts`:
    - `:confirmer` - function of arity 1 (default uses non-interactive auto-accept)
    - `:adventure_id` - override
    - `:dry_run` - parse + confirm but do not write Ash records
  """
  def import_pack(pack_dir, opts \\ []) do
    confirmer = Keyword.get(opts, :confirmer, &auto_accept_confirmer/1)
    dry_run? = Keyword.get(opts, :dry_run, false)

    with {:ok, pack} <- parse_pack(pack_dir),
         {:ok, confirmed} <- confirm_pack(pack, confirmer),
         {:ok, final} <- final_confirmation(confirmed, confirmer),
         {:ok, result} <- maybe_write_to_ash(final, dry_run?) do
      Logger.info("Importer: pack #{final.adventure_id} imported from #{pack_dir}")
      {:ok, result}
    end
  end

  @doc "Non-interactive convenience: accept everything and import."
  def import_pack!(pack_dir, opts \\ []) do
    opts = Keyword.put(opts, :confirmer, &auto_accept_confirmer/1)

    case import_pack(pack_dir, opts) do
      {:ok, res} -> res
      {:error, reason} -> raise "Import failed: #{inspect(reason)}"
    end
  end

  @doc """
  Helper to copy the entire rules/ tree from one game pack into another.
  Supports the requirement that rules are easily copyable between games.
  """
  def copy_rules(source_pack_dir, target_pack_dir) do
    src_rules = Path.join(source_pack_dir, "rules")
    tgt_rules = Path.join(target_pack_dir, "rules")

    if File.dir?(src_rules) do
      File.mkdir_p!(tgt_rules)
      # Recursively copy everything under rules/
      Path.wildcard(Path.join(src_rules, "**/*"))
      |> Enum.each(fn src ->
        rel = Path.relative_to(src, src_rules)
        dst = Path.join(tgt_rules, rel)

        if File.dir?(src) do
          File.mkdir_p!(dst)
        else
          File.mkdir_p!(Path.dirname(dst))
          File.cp!(src, dst)
        end
      end)
    end

    :ok
  end

  # ------------------------------------------------------------------
  # Internal: validation
  # ------------------------------------------------------------------

  defp check_exists(dir) do
    if File.dir?(dir), do: :ok, else: {:error, "Pack directory not found: #{dir}"}
  end

  defp check_rules_mandated(dir) do
    rules_dir = Path.join(dir, "rules")

    if not File.dir?(rules_dir) do
      {:error,
       "Mandatory rules/ directory is missing (point 5). Every game pack must contain a rules/ directory. The contents can be a deep hierarchy (e.g. 00-*/ bestiary/ appendices/)."}
    else
      has_md = Path.wildcard(Path.join(rules_dir, "**/*.md")) |> Enum.any?()

      if has_md do
        :ok
      else
        {:error,
         "rules/ exists but contains no .md files in #{rules_dir}. " <>
           "Provide at least core rules content (you can copy from another pack). Example files: core_mechanics.md, skills.md, races.md, ..."}
      end
    end
  end

  defp check_has_content(dir) do
    # Lightweight generic check: rules/ (already validated) + something useful (places/characters/adventure root / README)
    has_places =
      ["places", "locations", "sites", "world"]
      |> Enum.any?(fn c -> File.dir?(Path.join(dir, c)) end)

    has_chars =
      ["characters", "cast", "npcs", "bestiary"]
      |> Enum.any?(fn c -> File.dir?(Path.join(dir, c)) end)

    has_root =
      File.exists?(Path.join(dir, "adventure.md")) or File.exists?(Path.join(dir, "README.md")) or
        File.exists?(Path.join(dir, "SUMMARY.md"))

    if has_places or has_chars or has_root do
      :ok
    else
      {:error,
       "Pack appears empty. Expected places/locations/, characters/cast/, or root README/SUMMARY/adventure.md under #{dir}"}
    end
  end

  # ------------------------------------------------------------------
  # Parsing
  # ------------------------------------------------------------------

  defp parse_adventure_meta(pack_dir) do
    root_md = Path.join(pack_dir, "adventure.md")

    base = %{
      adventure_id: Path.basename(pack_dir),
      name: Path.basename(pack_dir) |> String.replace("_", " ") |> String.capitalize(),
      synopsis: "Imported adventure pack.",
      starting_location_id: nil,
      initial_present_npc_ids: []
    }

    if File.exists?(root_md) do
      {:ok, fm, body} = parse_md_file(root_md)
      body_str = to_string(body || "")

      synopsis =
        case fm["synopsis"] || fm["summary"] do
          s when is_binary(s) and s != "" ->
            s

          _ ->
            bp = extract_first_paragraph(body_str)
            if bp == "", do: base.synopsis, else: bp
        end

      meta =
        base
        |> Map.merge(string_keys_to_atoms(fm))
        |> Map.put(:synopsis, synopsis)
        |> Map.put(:name, fm["name"] || fm["title"] || base.name)
        |> Map.put(
          :starting_location_id,
          fm["starting_location_id"] || fm["start"] || base.starting_location_id
        )

      initial = parse_list(fm["initial_present_npc_ids"] || fm["present_npcs"])
      {:ok, Map.put(meta, :initial_present_npc_ids, initial)}
    else
      {:ok, base}
    end
  end

  defp load_rules_pack(pack_dir) do
    rules_dir = Path.join(pack_dir, "rules")

    # Generic: recursively collect all .md under rules/. Keyed by relative path for structure preservation.
    # Order is by full relative path (numeric prefixes like 00-, 01- will sort naturally).
    contents =
      Path.wildcard(Path.join(rules_dir, "**/*.md"))
      |> Enum.sort()
      |> Enum.reduce(%{}, fn abs_path, acc ->
        rel = Path.relative_to(abs_path, rules_dir)
        Map.put(acc, rel, File.read!(abs_path))
      end)

    {:ok, contents}
  end

  defp parse_section(pack_dir, section, entity_type, opts) do
    optional = Keyword.get(opts || [], :optional, false)
    dir = Path.join(pack_dir, section)

    cond do
      not File.dir?(dir) and optional ->
        {:ok, []}

      not File.dir?(dir) ->
        {:error, "Required section missing: #{section}/"}

      true ->
        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reduce_while({:ok, []}, fn file, {:ok, acc} ->
          path = Path.join(dir, file)

          {:ok, fm, body} = parse_md_file(path)
          parsed = build_entity(entity_type, pack_dir, section, file, fm, body)
          {:cont, {:ok, acc ++ [parsed]}}
        end)
    end
  end

  defp build_entity(kind, _pack, section, file, fm, body) do
    # Allow frontmatter "type" to override the kind inferred from directory
    fm_type = to_string(fm["type"] || fm["kind"] || "")

    effective_kind =
      cond do
        fm_type in ["place", "location", "site"] -> :location
        fm_type in ["npc", "character", "monster", "creature"] -> :npc
        true -> kind
      end

    slug = fm["id"] || Path.rootname(file)
    source_hint = "#{section}/#{file}"

    case effective_kind do
      :location ->
        %{
          type: :location,
          location_id: slug,
          name: fm["name"] || extract_title(body) || slug,
          exits: parse_list(fm["exits"]),
          blurb: fm["blurb"] || first_paragraph_or_body(body),
          fixtures: parse_list(fm["fixtures"]),
          ground_items: [],
          scene_image_url: fm["scene_image_url"],
          body: body,
          links: extract_wiki_links(body),
          source: source_hint
        }

      :npc ->
        %{
          type: :npc,
          npc_id: slug,
          name: fm["name"] || extract_title(body) || slug,
          race: fm["race"] || "human",
          role: fm["role"],
          default_location_id: fm["default_location_id"],
          appearance: fm["appearance"] || extract_section(body, "Appearance"),
          personality: fm["personality"] || extract_section(body, "Personality"),
          backstory:
            fm["backstory"] || extract_section(body, "Backstory") || first_paragraph_or_body(body),
          motivations:
            parse_motivations(fm["motivations"] || extract_section(body, "Motivations")),
          stock: parse_stock(fm["stock"]),
          portrait_url: fm["portrait_url"],
          body: body,
          links: extract_wiki_links(body),
          source: source_hint
        }

      _ ->
        %{
          type: effective_kind,
          id: slug,
          name: fm["name"] || extract_title(body) || slug,
          body: body,
          links: extract_wiki_links(body),
          source: source_hint
        }
    end
  end

  # ------------------------------------------------------------------
  # Lightweight Markdown + Frontmatter + Links
  # ------------------------------------------------------------------

  defp parse_md_file(path) do
    content = File.read!(path)
    {fm, body} = split_frontmatter(content)
    {:ok, fm, String.trim(body)}
  end

  defp split_frontmatter(content) do
    case Regex.run(~r/\A\s*---\s*\n(.*?)\n---\s*\n(.*)/s, content, capture: :all_but_first) do
      [yaml, body] -> {parse_simple_yaml(yaml), body}
      _ -> {%{}, content}
    end
  end

  # Very lightweight YAML: key: value or key: [a, b] (simple, no deep nesting needed for lightweight spec)
  defp parse_simple_yaml(yaml_str) do
    yaml_str
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{}, fn line, acc ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" or String.starts_with?(trimmed, "#") ->
          acc

        match = Regex.run(~r/^([a-zA-Z0-9_]+):\s*(.*)$/, trimmed) ->
          [_, key, val] = match
          Map.put(acc, key, parse_yaml_value(String.trim(val)))

        true ->
          acc
      end
    end)
  end

  defp parse_yaml_value(val) do
    cond do
      String.match?(val, ~r/^\[.*\]$/) ->
        val
        |> String.trim_leading("[")
        |> String.trim_trailing("]")
        |> String.split(~r/\s*,\s*/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      String.match?(val, ~r/^true$/i) ->
        true

      String.match?(val, ~r/^false$/i) ->
        false

      String.match?(val, ~r/^\d+$/) ->
        String.to_integer(val)

      true ->
        String.trim(val, "\"'")
    end
  end

  defp parse_list(nil), do: []
  defp parse_list(list) when is_list(list), do: list

  defp parse_list(str) when is_binary(str),
    do: String.split(str, ~r/\s*,\s*/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp parse_list(_), do: []

  defp parse_motivations(nil), do: %{}
  defp parse_motivations(map) when is_map(map), do: map

  defp parse_motivations(str) when is_binary(str) do
    # Accept "openness: 12, conscientiousness: 8" style or JSON-ish
    str
    |> String.split(~r/[,\n]/)
    |> Enum.reduce(%{}, fn part, acc ->
      case Regex.run(~r/([a-z_]+)\s*[:=]\s*(\d+)/i, String.trim(part)) do
        [_, k, v] -> Map.put(acc, String.downcase(k), String.to_integer(v))
        _ -> acc
      end
    end)
  end

  defp parse_motivations(_), do: %{}

  defp parse_stock(nil), do: []
  defp parse_stock(list) when is_list(list), do: list
  # very lightweight fallback
  defp parse_stock(str) when is_binary(str), do: [%{"name" => str}]
  defp parse_stock(_), do: []

  defp extract_wiki_links(body) do
    ~r/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.map(fn
      [slug] -> String.trim(slug)
      [slug, _] -> String.trim(slug)
    end)
    |> Enum.uniq()
  end

  defp extract_title(body) do
    case Regex.run(~r/^#\s+(.+)$/m, body) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  defp first_paragraph_or_body(body) do
    s =
      body
      |> String.split(~r/\n\s*\n/, parts: 2)
      |> List.first()
      |> to_string()
      |> String.trim()
      # drop leading title heading line for synopsis extraction
      |> String.replace(~r/^#+\s*.+(\n|$)/, "")
      |> String.trim()

    String.slice(s, 0, 600)
  end

  defp extract_first_paragraph(body) do
    body
    |> first_paragraph_or_body()
    |> to_string()
    |> String.trim()
  end

  defp extract_section(body, header) do
    regex = ~r/^##?\s*#{Regex.escape(header)}\s*\n(.*?)(?=\n##?|\z)/sim

    case Regex.run(regex, body, capture: :all_but_first) do
      [section] -> String.trim(section)
      _ -> nil
    end
  end

  defp string_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(to_string(k)), v} end)
  end

  # ------------------------------------------------------------------
  # Interactive confirmation flow (points 3 + 6)
  # ------------------------------------------------------------------

  defp confirm_pack(pack, confirmer) do
    # Build proposals for adventure + each entity.
    adventure_proposal = %{
      type: :adventure,
      question: "Import adventure \"#{pack.name}\" (id: #{pack.adventure_id})?",
      proposed: %{
        adventure_id: pack.adventure_id,
        name: pack.name,
        synopsis: pack.synopsis,
        starting_location_id: pack.starting_location_id,
        initial_present_npc_ids: pack.initial_present_npc_ids
      },
      source_file: "adventure.md or folder name"
    }

    with {:ok, adv_conf} <- call_confirmer(confirmer, adventure_proposal),
         {:ok, locs} <- confirm_list(pack.locations, confirmer, :location),
         {:ok, npcs} <- confirm_list(pack.npcs, confirmer, :npc) do
      adv_map = if is_map(adv_conf), do: adv_conf, else: %{}

      confirmed = %{
        pack
        | adventure_id:
            Map.get(adv_map, :adventure_id) || Map.get(adv_map, "adventure_id") ||
              pack.adventure_id,
          name: Map.get(adv_map, :name) || Map.get(adv_map, "name") || pack.name,
          synopsis: Map.get(adv_map, :synopsis) || Map.get(adv_map, "synopsis") || pack.synopsis,
          starting_location_id:
            Map.get(adv_map, :starting_location_id) || Map.get(adv_map, "starting_location_id") ||
              pack.starting_location_id,
          initial_present_npc_ids:
            Map.get(adv_map, :initial_present_npc_ids) ||
              Map.get(adv_map, "initial_present_npc_ids") || pack.initial_present_npc_ids,
          locations: locs,
          npcs: npcs
      }

      {:ok, confirmed}
    end
  end

  defp confirm_list(entities, confirmer, type) do
    Enum.reduce_while(entities, {:ok, []}, fn entity, {:ok, acc} ->
      proposal = build_entity_proposal(entity, type)

      case call_confirmer(confirmer, proposal) do
        {:ok, nil} ->
          # skip
          {:cont, {:ok, acc}}

        {:ok, confirmed_attrs} when is_map(confirmed_attrs) ->
          updated = Map.merge(entity, confirmed_attrs)
          {:cont, {:ok, acc ++ [updated]}}

        {:ok, true} ->
          {:cont, {:ok, acc ++ [entity]}}

        {:ok, {:skip, _}} ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp build_entity_proposal(%{type: :npc} = e, :npc) do
    %{
      type: :npc,
      question: "Do you mean to create a Character called #{e.name}?",
      proposed:
        Map.take(e, [:npc_id, :name, :race, :role, :default_location_id, :motivations, :stock]),
      source_file: e.source
    }
  end

  defp build_entity_proposal(%{type: :location} = e, :location) do
    %{
      type: :location,
      question: "Creating Place/Location '#{e.name}' from #{e.source}?",
      proposed: Map.take(e, [:location_id, :name, :exits, :blurb]),
      source_file: e.source
    }
  end

  defp build_entity_proposal(e, type) do
    %{
      type: type,
      question: "Accept #{type} #{Map.get(e, :name, e[:id])}?",
      proposed: e,
      source_file: Map.get(e, :source)
    }
  end

  defp call_confirmer(confirmer, proposal) do
    case confirmer.(proposal) do
      true -> {:ok, true}
      false -> {:ok, nil}
      {:ok, val} -> {:ok, val}
      {:skip, _} = s -> {:ok, s}
      {:error, _} = e -> e
      other -> {:ok, other}
    end
  end

  defp final_confirmation(confirmed_pack, confirmer) do
    final_q = %{
      type: :final,
      question:
        "Confirm that the pack '#{confirmed_pack.adventure_id}' (#{length(confirmed_pack.locations)} locations, #{length(confirmed_pack.npcs)} NPCs) is correctly imported?",
      proposed: %{
        adventure_id: confirmed_pack.adventure_id,
        rules_present: map_size(confirmed_pack.rules) > 0
      },
      source_file: confirmed_pack.source_dir
    }

    case call_confirmer(confirmer, final_q) do
      {:ok, false} -> {:error, :import_cancelled_by_user}
      {:ok, _} -> {:ok, confirmed_pack}
      other -> other
    end
  end

  # Default non-interactive confirmer: accept everything.
  defp auto_accept_confirmer(_proposal), do: true

  # ------------------------------------------------------------------
  # Write to Ash (after all confirmations)
  # ------------------------------------------------------------------

  defp maybe_write_to_ash(pack, true), do: {:ok, %{dry_run: true, pack: sanitize_for_log(pack)}}

  defp maybe_write_to_ash(pack, false) do
    # Create / upsert Adventure
    adv_attrs = %{
      adventure_id: pack.adventure_id,
      name: pack.name,
      synopsis: pack.synopsis,
      starting_location_id: pack.starting_location_id,
      initial_present_npc_ids: pack.initial_present_npc_ids
    }

    adventure =
      case Ash.read(Adventure |> filter(adventure_id == ^pack.adventure_id), load: []) do
        {:ok, [existing | _]} ->
          update_attrs = Map.drop(adv_attrs, [:adventure_id, "adventure_id"])
          Adventure.update!(existing, update_attrs)

        _ ->
          case Adventure.create(adv_attrs) do
            {:ok, adv} ->
              adv

            {:error, _constraint_error} ->
              # Unique violation or race - read and update instead (robust upsert)
              case Ash.read(Adventure |> filter(adventure_id == ^pack.adventure_id), load: []) do
                {:ok, [ex | _]} ->
                  update_attrs = Map.drop(adv_attrs, [:adventure_id, "adventure_id"])
                  Adventure.update!(ex, update_attrs)

                _ ->
                  raise "Could not upsert Adventure #{pack.adventure_id}"
              end
          end
      end

    # Locations
    Enum.each(pack.locations, fn loc ->
      attrs = %{
        adventure_id: pack.adventure_id,
        location_id: loc.location_id,
        name: loc.name,
        exits: loc.exits || [],
        blurb: loc.blurb,
        fixtures: loc.fixtures || [],
        ground_items: loc.ground_items || [],
        scene_image_url: loc.scene_image_url
      }

      # upsert by identity
      case Ash.read(
             Location
             |> filter(adventure_id == ^pack.adventure_id and location_id == ^loc.location_id),
             load: []
           ) do
        {:ok, [ex | _]} ->
          Location.update!(ex, Map.drop(attrs, [:adventure_id, :location_id]))

        _ ->
          case Location.create(attrs) do
            {:ok, l} ->
              l

            _ ->
              ex =
                Ash.read!(
                  Location
                  |> filter(
                    adventure_id == ^pack.adventure_id and location_id == ^loc.location_id
                  ), load: [])

              Location.update!(ex, Map.drop(attrs, [:adventure_id, :location_id]))
          end
      end
    end)

    # NPCs
    Enum.each(pack.npcs, fn npc ->
      attrs = %{
        npc_id: npc.npc_id,
        name: npc.name,
        race: npc.race,
        role: npc.role,
        default_location_id: npc.default_location_id,
        appearance: npc.appearance,
        personality: npc.personality,
        backstory: npc.backstory,
        motivations: npc.motivations || %{},
        stock: npc.stock || [],
        portrait_url: npc.portrait_url
      }

      case Ash.read(NpcDefinition |> filter(npc_id == ^npc.npc_id), load: []) do
        {:ok, [ex | _]} ->
          update_attrs = Map.drop(attrs, [:npc_id, :race])
          NpcDefinition.update!(ex, update_attrs)

        _ ->
          case NpcDefinition.create(attrs) do
            {:ok, n} ->
              n

            _ ->
              ex = Ash.read!(NpcDefinition |> filter(npc_id == ^npc.npc_id), load: [])
              update_attrs = Map.drop(attrs, [:npc_id, :race])
              NpcDefinition.update!(ex, update_attrs)
          end
      end
    end)

    {:ok,
     %{
       adventure: adventure,
       locations: length(pack.locations),
       npcs: length(pack.npcs),
       rules_files: Map.keys(pack.rules)
     }}
  end

  defp sanitize_for_log(pack) do
    Map.drop(pack, [:rules]) |> Map.put(:rules_count, map_size(pack.rules))
  end

  # ------------------------------------------------------------------
  # Convenience for future: resolving links (convention over config)
  # ------------------------------------------------------------------

  @doc """
  Resolve a wiki link (e.g. "The Inn" or "jack") to a probable file path
  using generic conventions. Searches common containers + the whole tree as fallback.
  """
  def resolve_link(link_text, pack_dir, opts \\ []) do
    context = Keyword.get(opts, :context, "places")
    slug = slugify(link_text)

    base_containers = [
      context,
      "places",
      "locations",
      "sites",
      "world",
      "characters",
      "cast",
      "npcs",
      "bestiary",
      "player_characters",
      "roster",
      "pregens",
      "adventures",
      "scenarios"
    ]

    candidates =
      (base_containers
       |> Enum.map(fn c -> Path.join([pack_dir, c, "#{slug}.md"]) end)) ++
        [
          Path.join(pack_dir, "#{slug}.md")
          # last resort: any .md with matching slug anywhere
        ]

    found = Enum.find(candidates, &File.exists?/1)
    found || find_by_slug_anywhere(pack_dir, slug)
  end

  defp find_by_slug_anywhere(pack_dir, slug) do
    case Path.wildcard(Path.join(pack_dir, "**/#{slug}.md")) do
      [first | _] -> first
      _ -> nil
    end
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
