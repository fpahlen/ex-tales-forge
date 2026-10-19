defmodule TalesForge.Game.Pack do
  @moduledoc """
  File loader for complete adventure packs under `priv/adventures/<id>/`.

  Fail-fast on missing start, dangling exits, portent spawn targets, or bad
  character levers (Maslow, concerns, OCEAN; see `TalesForge.Characters.Levers`).
  Crossroads is **not** loaded through this module at session create, but its
  player character file is (`player_character!/1`).

  The player character lives in `characters/<id>.json`: the sheet that goes
  into `world_state["character"]`, plus the levers `ocean`, `maslow` and
  `concerns`, which `sheet/1` strips.


  A world feature (`TalesForge.Game.Features`) adds a pack extension,
  `extensions/<feature>/` with optional `world/`, `npcs/`, `fronts/` and
  `extension.json`. Its places, people and fronts are added to the base pack
  (an id may not repeat); an exit from a new place to a base place is added
  back on the base place too, so the graph stays two-way; `extension.json`
  `"npc_hooks"` appends hooks to NPCs already loaded.

  A location's blurb is the first paragraph of its body under the heading.
  """

  alias TalesForge.Characters.{Defaults, Levers}
  alias TalesForge.Game.Fronts
  alias TalesForge.Game.WorldClock

  @sheet_keys ~w(id name race stats skills)

  @doc """
  Loads and validates a pack with the extensions of `features`. Raises
  `ArgumentError` on a broken pack.
  """
  @spec load(String.t(), [String.t()]) :: map()
  def load(adventure_id, features \\ [])

  def load(adventure_id, features) when is_binary(adventure_id) and adventure_id != "" do
    dir = Path.join(adventures_dir(), adventure_id)

    unless File.dir?(dir) do
      raise ArgumentError, "adventure pack missing: #{adventure_id}"
    end

    adventure = load_adventure!(dir)
    extensions = load_extensions!(dir, features)
    locations = dir |> load_locations!() |> merge_locations!(extensions)
    npcs = dir |> Path.join("npcs") |> load_npc_dir!() |> merge_npcs!(extensions)
    defaults = Defaults.rules(adventure_id)
    Enum.each(npcs, &validate_npc!(&1, defaults, "#{adventure_id} NPC #{&1["id"]}"))
    player_character = player_character!(adventure_id)
    fronts_dir = Path.join(dir, "fronts")

    fronts =
      fronts_dir
      |> Fronts.parse_dir!()
      |> Enum.map(&attach_identity(&1, fronts_dir))
      |> Kernel.++(Enum.flat_map(extensions, & &1.fronts))
      |> unique_ids!("front")

    validate_graph!(adventure["starting_location_id"], locations)
    validate_tree!(locations)
    validate_positions!(locations)
    Fronts.validate!(fronts)

    %{
      adventure_id: adventure["adventure_id"] || adventure_id,
      name: adventure["name"] || adventure_id,
      starting_location_id: adventure["starting_location_id"],
      initial_present_npc_ids: List.wrap(adventure["initial_present_npc_ids"]),
      situation_lines: List.wrap(adventure["situation_lines"]),
      economy: economy(adventure),
      locations: areas_for(locations, features),
      npcs: npcs,
      player_character: player_character,
      fronts: fronts
    }
  end

  def load(_, _, _), do: raise(ArgumentError, "adventure_id required")

  @doc """
  The starting world_state of a new session of the pack: location, places,
  present NPCs, clock, character and live fronts, plus `"features"` when any.
  """
  @spec materialize(String.t(), [String.t()]) :: map()
  def materialize(adventure_id, features \\ [])
      when is_binary(adventure_id) do
    features = TalesForge.Game.Features.normalize(features)
    pack = load(adventure_id, features)
    start_id = pack.starting_location_id
    start = Map.fetch!(pack.locations, start_id)
    elara = sheet(pack.player_character)
    tick = WorldClock.default_start_tick()

    live_fronts =
      pack.fronts
      |> Enum.filter(&(&1["status"] == "live"))
      |> Enum.map(& &1["id"])
      |> Enum.sort()

    %{
      "adventure_id" => pack.adventure_id,
      "location_id" => start_id,
      "location_name" => start["name"],
      "present_npcs" => pack.initial_present_npc_ids,
      "world_tick" => tick,
      "world_clock" => WorldClock.format(tick),
      "last_scene_location" => nil,
      "situation_lines" => pack.situation_lines,
      "economy" => Map.get(pack, :economy, %{}),
      "character" => Map.put(elara, "location_id", start_id),
      "locations" => pack.locations,
      "live_fronts" => live_fronts,
      "public_facts" => []
    }
    |> put_features(features)
  end

  defp put_features(world, []), do: world
  defp put_features(world, features), do: Map.put(world, "features", features)

  @doc """
  The adventure's player character file (`characters/*.json`), levers included.
  Raises `ArgumentError` if there is not exactly one file, or if the sheet or
  the levers are invalid.
  """
  def player_character!(adventure_id) when is_binary(adventure_id) do
    dir = Path.join([adventures_dir(), adventure_id, "characters"])

    case Path.wildcard(Path.join(dir, "*.json")) do
      [path] ->
        path |> File.read!() |> Jason.decode!() |> validate_player_character!(path)

      [] ->
        raise ArgumentError, "no player character in #{dir}"

      paths ->
        raise ArgumentError, "expected one player character in #{dir}, got #{length(paths)}"
    end
  end

  @doc "A character file without its levers: the map stored as `world_state[\"character\"]`."
  def sheet(character) when is_map(character), do: Map.drop(character, Levers.lever_keys())

  @doc false
  def validate_player_character!(character, source) when is_map(character) do
    Enum.each(@sheet_keys, fn key ->
      unless Map.has_key?(character, key) do
        raise ArgumentError, "#{source}: player character needs #{inspect(key)}"
      end
    end)

    Levers.validate!(character, source)
    character
  end

  defp validate_npc!(npc, defaults, source) do
    Levers.validate!(npc, source)

    case npc["derive"] do
      nil -> :ok
      inputs when is_map(inputs) -> Defaults.validate_inputs!(inputs, defaults, source)
      other -> raise ArgumentError, "#{source}: derive must be a map, got #{inspect(other)}"
    end
  end

  @doc false
  def validate_graph!(start, locations) do
    unless is_binary(start) and Map.has_key?(locations, start) do
      raise ArgumentError, "starting_location_id #{inspect(start)} missing from locations"
    end

    locations
    |> Enum.flat_map(fn {id, loc} -> Enum.map(List.wrap(loc["exits"]), &{id, &1}) end)
    |> Enum.each(fn {id, exit_id} ->
      unless Map.has_key?(locations, exit_id) do
        raise ArgumentError, "location #{id} exit #{inspect(exit_id)} missing from locations"
      end
    end)

    Enum.each(locations, fn {id, loc} ->
      door = loc["door"]

      if is_binary(door) and door not in List.wrap(loc["exits"]) do
        raise ArgumentError, "location #{id} door #{inspect(door)} is not one of its exits"
      end
    end)

    :ok
  end

  @max_depth 5

  @doc """
  Checks the place tree (`parent`, board card 7aba0394): each parent is a
  place, there is no loop, and a chain has at most #{@max_depth} places.
  Raises `ArgumentError` on a broken tree, so a bad pack fails at load.

      iex> TalesForge.Game.Pack.validate_tree!(%{"region" => %{}, "inn" => %{"parent" => "region"}})
      :ok
      iex> TalesForge.Game.Pack.validate_tree!(%{"a" => %{"parent" => "b"}, "b" => %{"parent" => "a"}})
      ** (ArgumentError) location a: the parent chain has a loop (a, b, a)
  """
  @spec validate_tree!(map()) :: :ok
  def validate_tree!(locations) do
    Enum.each(locations, fn {id, _loc} -> chain!(locations, id, [id]) end)
  end

  defp chain!(locations, id, [current | _] = trail) do
    case get_in(locations, [current, "parent"]) do
      nil ->
        if length(trail) > @max_depth do
          raise ArgumentError,
                "location #{id}: the parent chain has #{length(trail)} places, more than #{@max_depth}"
        end

        :ok

      parent when not is_binary(parent) ->
        raise ArgumentError,
              "location #{current}: parent must be a place id, got #{inspect(parent)}"

      parent ->
        cond do
          not Map.has_key?(locations, parent) ->
            raise ArgumentError,
                  "location #{current} parent #{inspect(parent)} missing from locations"

          parent in trail ->
            loop = trail |> Enum.reverse() |> Kernel.++([parent]) |> Enum.join(", ")
            raise ArgumentError, "location #{id}: the parent chain has a loop (#{loop})"

          true ->
            chain!(locations, id, [parent | trail])
        end
    end
  end

  @doc """
  Checks the travel keys of each place (board card 7aba0394, PR 2): `at` is
  `[x, y]` (numbers) on a place with a parent, `scale` is building,
  settlement or region, and `cell_m` is a positive number.

      iex> TalesForge.Game.Pack.validate_positions!(%{"v" => %{"scale" => "settlement"}, "inn" => %{"parent" => "v", "at" => [1, 2]}})
      :ok
      iex> TalesForge.Game.Pack.validate_positions!(%{"inn" => %{"at" => [1, 2]}})
      ** (ArgumentError) location inn: at needs a parent
  """
  @spec validate_positions!(map()) :: :ok
  def validate_positions!(locations) do
    Enum.each(locations, fn {id, loc} -> position!(id, loc) end)
  end

  defp position!(id, loc) do
    case loc["at"] do
      nil ->
        :ok

      [x, y] when is_number(x) and is_number(y) ->
        loc["parent"] || at_error!(id, "at needs a parent")

      other ->
        at_error!(id, "at must be [x, y], got #{inspect(other)}")
    end

    unless loc["scale"] in [nil, "building", "settlement", "region"],
      do:
        at_error!(
          id,
          "scale must be building, settlement or region, got #{inspect(loc["scale"])}"
        )

    unless is_nil(loc["cell_m"]) or (is_number(loc["cell_m"]) and loc["cell_m"] > 0),
      do: at_error!(id, "cell_m must be a positive number, got #{inspect(loc["cell_m"])}")

    :ok
  end

  defp at_error!(id, message), do: raise(ArgumentError, "location #{id}: #{message}")

  # Areas (a village, a region) are places that only the tree reaches: no
  # exits of their own and no exit to them. Without the feature
  # "hierarchical_locations" the session does not get them, so movement and
  # the prompts stay as before.
  defp areas_for(locations, features) do
    if "hierarchical_locations" in TalesForge.Game.Features.normalize(features),
      do: locations,
      else: Map.reject(locations, &area?(&1, locations))
  end

  defp area?({id, loc}, locations) do
    List.wrap(loc["exits"]) == [] and
      not Enum.any?(locations, fn {_other, o} -> id in List.wrap(o["exits"]) end) and
      Enum.any?(locations, fn {_other, o} -> o["parent"] == id end)
  end

  @doc """
  The parent of each place of the pack (`parent` in the place files), by
  place id, with every area. `TalesForge.World` reads it: the place files
  are the one source of the tree.
  """
  @spec parents(String.t()) :: %{String.t() => String.t() | nil}
  def parents(adventure_id) do
    adventure_id
    |> load(TalesForge.Game.Features.all())
    |> Map.fetch!(:locations)
    |> Map.new(fn {id, loc} -> {id, loc["parent"]} end)
  end

  # The world config of the economy (TalesForge.Game.Economy).
  defp economy(adventure) do
    case adventure["unskilled_wage_copper_per_hour"] do
      wage when is_integer(wage) -> %{"unskilled_wage_copper_per_hour" => wage}
      _ -> %{}
    end
  end

  defp load_adventure!(dir) do
    path = Path.join(dir, "adventure.md")

    unless File.exists?(path) do
      raise ArgumentError, "adventure.md missing in #{dir}"
    end

    {fm, _body} = parse_md!(path)
    stringify_keys(fm)
  end

  defp attach_identity(front, fronts_dir) do
    path = Path.join(fronts_dir, front["id"] <> ".md")

    if File.exists?(path) do
      {_fm, body} = parse_md!(path)
      Map.put(front, "identity", String.trim(body))
    else
      front
    end
  end

  defp load_locations!(dir) do
    world_dir = Path.join(dir, "world")

    unless File.dir?(world_dir) do
      raise ArgumentError, "world/ missing in #{dir}"
    end

    load_location_dir(world_dir)
  end

  defp load_location_dir(world_dir) do
    world_dir
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.map(&parse_location!/1)
    |> Map.new(fn loc -> {loc["id"], loc} end)
  end

  # --- extensions (world features) -------------------------------------------

  defp load_extensions!(dir, features) do
    features
    |> TalesForge.Game.Features.normalize()
    |> Enum.map(&{&1, Path.join([dir, "extensions", &1])})
    |> Enum.filter(fn {_feature, ext_dir} -> File.dir?(ext_dir) end)
    |> Enum.map(fn {feature, ext_dir} -> load_extension!(feature, ext_dir) end)
  end

  defp load_extension!(feature, ext_dir) do
    world_dir = Path.join(ext_dir, "world")
    fronts_dir = Path.join(ext_dir, "fronts")
    meta_path = Path.join(ext_dir, "extension.json")

    %{
      feature: feature,
      locations: if(File.dir?(world_dir), do: load_location_dir(world_dir), else: %{}),
      npcs: load_npc_dir!(Path.join(ext_dir, "npcs")),
      fronts:
        if(File.dir?(fronts_dir),
          do: fronts_dir |> Fronts.parse_dir!() |> Enum.map(&attach_identity(&1, fronts_dir)),
          else: []
        ),
      meta:
        if(File.exists?(meta_path), do: meta_path |> File.read!() |> Jason.decode!(), else: %{})
    }
  end

  defp merge_locations!(base, extensions) do
    Enum.reduce(extensions, base, fn ext, acc ->
      Enum.reduce(ext.locations, acc, &add_location!(&2, &1, ext.feature))
    end)
  end

  defp add_location!(places, {id, _loc}, feature) when is_map_key(places, id) do
    raise ArgumentError, "extension #{feature}: location #{id} already exists"
  end

  defp add_location!(places, {id, loc}, _feature) do
    places
    |> Map.put(id, loc)
    |> add_return_exits(id, loc["exits"])
  end

  # An exit from a new place back to a known place gets its way back.
  defp add_return_exits(places, id, exits) do
    Enum.reduce(List.wrap(exits), places, &add_return_exit(&2, &1, id))
  end

  defp add_return_exit(places, exit_id, id) do
    case Map.get(places, exit_id) do
      %{"exits" => back} = other when is_list(back) ->
        if id in back,
          do: places,
          else: Map.put(places, exit_id, %{other | "exits" => back ++ [id]})

      _ ->
        places
    end
  end

  defp merge_npcs!(base, extensions) do
    extensions
    |> Enum.reduce(base, fn ext, acc ->
      (acc ++ ext.npcs)
      |> unique_ids!("NPC")
      |> append_hooks(Map.get(ext.meta, "npc_hooks", %{}))
    end)
  end

  defp append_hooks(npcs, hooks) when map_size(hooks) == 0, do: npcs

  defp append_hooks(npcs, hooks) do
    Enum.map(npcs, fn npc ->
      case Map.get(hooks, npc["id"]) do
        extra when is_list(extra) -> Map.put(npc, "hooks", List.wrap(npc["hooks"]) ++ extra)
        _ -> npc
      end
    end)
  end

  defp unique_ids!(items, what) do
    items
    |> Enum.frequencies_by(& &1["id"])
    |> Enum.each(fn {id, n} ->
      if n > 1, do: raise(ArgumentError, "#{what} #{inspect(id)} defined more than once")
    end)

    items
  end

  defp parse_location!(path) do
    {raw_fm, body} = parse_md!(path)
    attrs = stringify_keys(raw_fm)
    id = attrs["id"] || Path.rootname(Path.basename(path))

    %{
      "id" => id,
      "name" => attrs["name"] || id,
      "exits" => List.wrap(attrs["exits"]),
      "blurb" => attrs["blurb"] || location_blurb(body),
      "fixtures" => List.wrap(attrs["fixtures"]),
      "ground_items" => List.wrap(attrs["ground_items"])
    }
    |> put_movement_keys(attrs)
  end

  # Optional movement keys (`TalesForge.Game.Movement`): other names for the
  # place, the exit "leave" means, whether travel through it stops here, and
  # the place it is in (`parent`), with its position there (`at`) and the
  # size of its own cells (`scale`, `cell_m`), see TalesForge.Game.Travel.
  defp put_movement_keys(location, attrs) do
    location
    |> maybe_put_location("aliases", attrs["aliases"] && List.wrap(attrs["aliases"]))
    |> maybe_put_location("door", attrs["door"])
    |> maybe_put_location("checkpoint", if(attrs["checkpoint"] == true, do: true))
    |> maybe_put_location("parent", attrs["parent"])
    |> maybe_put_location("at", attrs["at"] && attrs["at"] |> List.wrap() |> Enum.map(&number/1))
    |> maybe_put_location("scale", attrs["scale"])
    |> maybe_put_location("cell_m", attrs["cell_m"] && number(attrs["cell_m"]))
  end

  # The frontmatter parser gives strings: "-4" and "2.5" become numbers; any
  # other value stays, so validate_positions!/1 names it.
  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} ->
        n

      _ ->
        case Float.parse(String.trim(value)) do
          {f, ""} -> f
          _ -> value
        end
    end
  end

  defp number(value), do: value

  defp maybe_put_location(location, _key, nil), do: location
  defp maybe_put_location(location, key, value), do: Map.put(location, key, value)

  defp load_npc_dir!(npc_dir) do
    if File.dir?(npc_dir) do
      markdown =
        npc_dir
        |> Path.join("*.md")
        |> Path.wildcard()
        |> Enum.map(&parse_npc!/1)

      json_by_id =
        npc_dir
        |> Path.join("*.json")
        |> Path.wildcard()
        |> Enum.map(&parse_npc_json!/1)
        |> Map.new(&{&1["id"], &1})

      merge_npc_json(markdown, json_by_id)
    else
      []
    end
  end

  defp parse_npc!(path) do
    {raw_fm, body} = parse_md!(path)
    attrs = stringify_keys(raw_fm)
    id = attrs["id"] || Path.rootname(Path.basename(path))

    %{
      "id" => id,
      "name" => attrs["name"] || id,
      "race" => attrs["race"] || "human",
      "role" => attrs["role"],
      "default_location_id" => attrs["default_location_id"],
      "appearance" => attrs["appearance"] || extract_section(body, "Appearance"),
      "personality" => attrs["personality"] || extract_section(body, "Personality"),
      "backstory" => attrs["backstory"] || extract_section(body, "Backstory"),
      "motivations" => npc_motivations(attrs["motivations"], body)
    }
  end

  defp parse_npc_json!(path) do
    attrs = path |> File.read!() |> Jason.decode!() |> stringify_keys()

    Map.update(attrs, "motivations", %{}, &normalize_motivations/1)
  end

  defp merge_npc_json(markdown, json_by_id) do
    merged =
      Enum.map(markdown, fn npc ->
        case Map.get(json_by_id, npc["id"]) do
          nil -> npc
          extra -> deep_merge_npc(npc, extra)
        end
      end)

    md_ids = MapSet.new(merged, & &1["id"])

    json_only =
      json_by_id
      |> Map.values()
      |> Enum.reject(&MapSet.member?(md_ids, &1["id"]))

    merged ++ json_only
  end

  defp deep_merge_npc(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _k, l, r ->
      if is_map(l) and is_map(r), do: deep_merge_npc(l, r), else: r
    end)
  end

  defp npc_motivations(from_frontmatter, body) do
    from_body = body |> extract_section("Motivations") |> normalize_motivations()
    Map.merge(from_body, normalize_motivations(from_frontmatter))
  end

  defp normalize_motivations(nil), do: %{}
  defp normalize_motivations(""), do: %{}

  defp normalize_motivations(map) when is_map(map) do
    map
    |> stringify_keys()
    |> Map.update("current_concern", nil, &normalize_concern/1)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_motivations(text) when is_binary(text) do
    %{}
    |> maybe_put_motivation("primary_need", capture_need(text))
    |> maybe_put_motivation("current_concern", normalize_concern(capture_concern(text)))
  end

  defp normalize_motivations(_), do: %{}

  defp normalize_concern(%{} = concern), do: stringify_keys(concern)

  defp normalize_concern(focus) when is_binary(focus) and focus != "" do
    %{
      "focus" => focus |> String.trim() |> String.trim_trailing("."),
      "priority" => 8,
      "blocked_by" => nil
    }
  end

  defp normalize_concern(_), do: nil

  defp capture_need(text) do
    case Regex.run(~r/Primary need:\s*(.+?)(?:\.?\s*Current concern:|$)/is, text) do
      [_, need] -> need |> String.trim() |> String.trim_trailing(".")
      _ -> nil
    end
  end

  defp capture_concern(text) do
    case Regex.run(~r/Current concern:\s*(.+)/is, text) do
      [_, focus] -> String.trim(focus)
      _ -> nil
    end
  end

  defp maybe_put_motivation(map, _key, nil), do: map
  defp maybe_put_motivation(map, key, value), do: Map.put(map, key, value)

  defp parse_md!(path) do
    content = File.read!(path)

    case Regex.run(~r/\A\s*---\s*\n(.*?)\n---\s*\n(.*)/s, content, capture: :all_but_first) do
      [yaml, body] -> {parse_yaml(yaml), String.trim(body)}
      _ -> {%{}, String.trim(content)}
    end
  end

  defp parse_yaml(yaml) do
    yaml
    |> String.split(~r/\r?\n/)
    |> Enum.reduce({%{}, nil}, fn line, {acc, list_key} ->
      trimmed = String.trim(line)
      parse_yaml_line(trimmed, acc, list_key)
    end)
    |> elem(0)
  end

  defp parse_yaml_line("", acc, list_key), do: {acc, list_key}

  defp parse_yaml_line("#" <> _, acc, list_key), do: {acc, list_key}

  defp parse_yaml_line("- " <> rest, acc, list_key) when is_binary(list_key) do
    {Map.update!(acc, list_key, &(&1 ++ [scalar(rest)])), list_key}
  end

  defp parse_yaml_line(trimmed, acc, list_key) do
    cond do
      match = Regex.run(~r/^([A-Za-z0-9_]+):\s*$/, trimmed) ->
        key = Enum.at(match, 1)
        {Map.put(acc, key, []), key}

      match = Regex.run(~r/^([A-Za-z0-9_]+):\s*(.+)$/, trimmed) ->
        key = Enum.at(match, 1)
        {Map.put(acc, key, scalar(String.trim(Enum.at(match, 2)))), nil}

      true ->
        {acc, list_key}
    end
  end

  defp scalar(val) do
    cond do
      String.match?(val, ~r/^\[.*\]$/) -> inline_list(val)
      String.match?(val, ~r/^true$/i) -> true
      String.match?(val, ~r/^false$/i) -> false
      String.match?(val, ~r/^-?\d+$/) -> String.to_integer(val)
      true -> String.trim(val, "\"'")
    end
  end

  # `[a, "b"]` as a list of strings.
  defp inline_list(val) do
    val
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(~r/\s*,\s*/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.trim(&1, "\"'"))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {to_string(k), stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  defp location_blurb(body) do
    body
    |> String.replace(~r/\A\s*#[^\n]*\n+/, "")
    |> first_paragraph()
  end

  defp first_paragraph(body) do
    body
    |> String.split(~r/\n\s*\n/, parts: 2)
    |> List.first()
    |> to_string()
    |> String.replace(~r/^#+\s+.*\n+/, "")
    |> String.trim()
  end

  defp extract_section(body, heading) do
    pattern = ~r/^##\s+#{Regex.escape(heading)}\s*\n+([^#]*)/m

    case Regex.run(pattern, body, capture: :all_but_first) do
      [text] -> String.trim(text)
      _ -> nil
    end
  end

  # Resolved at runtime (not a module attribute): in a release priv is not at its build path.
  defp adventures_dir, do: Path.join(:code.priv_dir(:ex_tales_forge), "adventures")
end
