defmodule TalesForge.Game.Movement do
  @moduledoc """
  Where the player character can go from here, and which place a player's
  words or an intent target mean. Pure functions over `world_state["locations"]`
  (the pack's locations, copied into the session).

  Movement is the server's job (AGENTS.md: the server applies state, the LLM
  narrates). Before this module the intent heuristic only recognised a move
  when the text named an adjacent exit by its full name ("market square"), so
  "I step into the square" or "head up to the cut" stayed at the inn while
  the GM narrated the walk, and the next turn snapped back to Brenna's bar
  (`docs/analysis-jev-baseline-2026-10-07.md`, §4).

  A location in the pack can carry three optional frontmatter keys:

  - `aliases`: other words for the place ("square", "the cut").
  - `door`: the exit "leave", "go outside" or "out the door" means, when the
    place has more than one exit (with one exit, that exit is the way out).
  - `checkpoint: true`: travel that passes through stops here (a watched
    approach), so "go to the orc nest" from the village ends at the cut.

  Travel reaches places up to three exits away in one turn.

  **Hierarchical locations** (board card 7aba0394, session feature
  `"hierarchical_locations"`, flag HIERARCHICAL_LOCATIONS). A place can name
  the place it is in with `parent` (an inn is in a village, a village is in a
  region). With the feature on:

  - each place links to its parent and to its children (`exits/2`), in
    addition to the hand-written exits, so travel goes up the tree and back
    down (inn, village, region, mine) within the same #{3} steps and stops
    at checkpoints;
  - "leave" and "go out" use the `door`, then the only exit, then the parent
    (`way_out/2`);
  - "go in" selects a child by name or alias, or the only child (`way_in/3`).

  With the feature off, movement uses only the hand-written exits.
  """

  @max_hops 3

  # Words that put a place right after them in a sentence about going there.
  @lead_in ~r/\b(?:to|toward|towards|into|for|up|down|over|across|through|back|onto|reach|enter|visit)\s+(?:(?:the|that|this|a|old|its|their|his|her)\s+)*$/u
  @window 40

  @typedoc "A location map as stored in `world_state[\"locations\"]`."
  @type location :: %{optional(String.t()) => term()}

  @doc """
  The session's locations by id (`world_state["locations"]`), or an empty map.
  """
  @spec places(map() | nil) :: %{String.t() => location()}
  def places(%{"locations" => locations}) when is_map(locations), do: locations
  def places(_world), do: %{}

  @doc "True when the world (a world_state or a movement world) has hierarchical locations."
  @spec tree?(map() | nil) :: boolean()
  def tree?(world), do: TalesForge.Game.Features.on?(world, "hierarchical_locations")

  @doc """
  The ids a character can go to from `id` in one step: the hand-written
  exits, and with hierarchical locations also the parent and the children.
  Only known places.

      iex> world = %{"features" => ["hierarchical_locations"], "locations" => %{
      ...>   "region" => %{}, "village" => %{"parent" => "region"},
      ...>   "inn" => %{"parent" => "village", "exits" => ["yard"]}, "yard" => %{"exits" => ["inn"]}}}
      iex> TalesForge.Game.Movement.exits(world, "inn")
      ["yard", "village"]
      iex> TalesForge.Game.Movement.exits(world, "village")
      ["region", "inn"]
      iex> TalesForge.Game.Movement.exits(Map.delete(world, "features"), "village")
      []
  """
  @spec exits(map(), String.t() | nil) :: [String.t()]
  def exits(world, id) when is_binary(id) do
    locations = places(world)
    hand = locations |> Map.get(id, %{}) |> Map.get("exits", []) |> List.wrap()
    tree = if tree?(world), do: List.wrap(parent(world, id)) ++ children(world, id), else: []

    (hand ++ tree)
    |> Enum.filter(&Map.has_key?(locations, &1))
    |> Enum.reject(&(&1 == id))
    |> Enum.uniq()
  end

  def exits(_world, _id), do: []

  @doc "The parent of `id` (its `parent` key), when that place exists."
  @spec parent(map(), String.t() | nil) :: String.t() | nil
  def parent(world, id) when is_binary(id) do
    locations = places(world)

    case get_in(locations, [id, "parent"]) do
      p when is_binary(p) -> if Map.has_key?(locations, p), do: p
      _ -> nil
    end
  end

  def parent(_world, _id), do: nil

  @doc "The children of `id` (the places whose `parent` is `id`), sorted by id."
  @spec children(map(), String.t() | nil) :: [String.t()]
  def children(world, id) when is_binary(id) do
    for {child, %{"parent" => ^id}} <- places(world), into: [], do: child
  end

  def children(_world, _id), do: []

  @doc """
  Location ids reachable from `from` within #{@max_hops} exits, nearest first,
  as `{id, hops}`. `from` itself is not included.

      iex> world = %{"locations" => %{
      ...>   "inn" => %{"exits" => ["square"]},
      ...>   "square" => %{"exits" => ["inn", "mine"]},
      ...>   "mine" => %{"exits" => ["square"]}}}
      iex> TalesForge.Game.Movement.reachable(world, "inn")
      [{"square", 1}, {"mine", 2}]
  """
  @spec reachable(map(), String.t() | nil) :: [{String.t(), pos_integer()}]
  def reachable(world, from) when is_binary(from) do
    bfs(world, [{from, 0}], MapSet.new([from]), [])
  end

  def reachable(_world, _from), do: []

  defp bfs(_world, [], _seen, acc), do: Enum.reverse(acc)

  defp bfs(world, [{id, hops} | queue], seen, acc) when hops >= @max_hops do
    bfs(world, queue, seen, if(hops > 0, do: [{id, hops} | acc], else: acc))
  end

  defp bfs(world, [{id, hops} | queue], seen, acc) do
    next = world |> exits(id) |> Enum.reject(&MapSet.member?(seen, &1))

    seen = Enum.reduce(next, seen, &MapSet.put(&2, &1))
    acc = if hops > 0, do: [{id, hops} | acc], else: acc
    bfs(world, queue ++ Enum.map(next, &{&1, hops + 1}), seen, acc)
  end

  @doc """
  Where travel from `from` toward `to` ends this turn: `to` itself, or the
  first `checkpoint` location on the shortest way there. `:error` when `to` is
  not reachable within #{@max_hops} exits (or is where the character already is).

      iex> world = %{"locations" => %{
      ...>   "square" => %{"exits" => ["cut"]},
      ...>   "cut" => %{"exits" => ["square", "nest"], "checkpoint" => true},
      ...>   "nest" => %{"exits" => ["cut"]}}}
      iex> TalesForge.Game.Movement.route(world, "square", "nest")
      {:ok, "cut"}
      iex> TalesForge.Game.Movement.route(world, "square", "cut")
      {:ok, "cut"}
      iex> TalesForge.Game.Movement.route(world, "square", "square")
      :error
  """
  @spec route(map(), String.t() | nil, String.t() | nil) :: {:ok, String.t()} | :error
  def route(world, from, to) when is_binary(from) and is_binary(to) and from != to do
    locations = places(world)

    case path(world, from, to) do
      nil -> :error
      steps -> {:ok, first_stop(locations, steps, to)}
    end
  end

  def route(_world, _from, _to), do: :error

  defp first_stop(locations, steps, to) do
    Enum.find(steps, to, fn id -> checkpoint?(Map.get(locations, id, %{})) end)
  end

  defp checkpoint?(%{"checkpoint" => true}), do: true
  defp checkpoint?(_location), do: false

  # Shortest path (excluding `from`) within @max_hops, or nil. `world`
  # (not only the locations) so that `exits/2` sees the features.
  defp path(world, from, to) do
    do_path(world, [{from, []}], MapSet.new([from]), to)
  end

  defp do_path(_world, [], _seen, _to), do: nil

  defp do_path(world, [{id, trail} | queue], seen, to) do
    if length(trail) >= @max_hops do
      do_path(world, queue, seen, to)
    else
      exits = world |> exits(id) |> Enum.reject(&MapSet.member?(seen, &1))

      case Enum.find(exits, &(&1 == to)) do
        nil ->
          seen = Enum.reduce(exits, seen, &MapSet.put(&2, &1))
          do_path(world, queue ++ Enum.map(exits, &{&1, trail ++ [&1]}), seen, to)

        found ->
          trail ++ [found]
      end
    end
  end

  @doc """
  The exit "leave" or "go outside" means from `from`: the location's `door`,
  or its only exit, or (hierarchical locations) its parent. nil when the
  place has several exits, no door and no parent.

      iex> world = %{"locations" => %{"inn" => %{"exits" => ["square"]}, "square" => %{}}}
      iex> TalesForge.Game.Movement.way_out(world, "inn")
      "square"
      iex> tree = %{"features" => ["hierarchical_locations"], "locations" => %{
      ...>   "village" => %{}, "yard" => %{}, "cellar" => %{},
      ...>   "inn" => %{"parent" => "village", "exits" => ["yard", "cellar"]}}}
      iex> TalesForge.Game.Movement.way_out(tree, "inn")
      "village"
  """
  @spec way_out(map(), String.t() | nil) :: String.t() | nil
  def way_out(world, from) when is_binary(from) do
    locations = places(world)

    case Map.get(locations, from, %{}) do
      %{"door" => door} when is_binary(door) and door != "" ->
        if Map.has_key?(locations, door), do: door

      %{"exits" => [only]} ->
        only

      _ ->
        if tree?(world), do: parent(world, from)
    end
  end

  def way_out(_world, _from), do: nil

  @doc """
  The child place "go in" means from `from` (hierarchical locations only):
  the child that `text` names by name or alias, else the only child. nil
  with the feature off, or with several children and none named.

      iex> world = %{"features" => ["hierarchical_locations"], "locations" => %{
      ...>   "village" => %{},
      ...>   "inn" => %{"name" => "Valley Inn", "parent" => "village", "aliases" => ["the tavern"]},
      ...>   "smithy" => %{"name" => "Smithy", "parent" => "village"}}}
      iex> TalesForge.Game.Movement.way_in(world, "village", "I go into the tavern")
      "inn"
      iex> TalesForge.Game.Movement.way_in(world, "village", "I go inside")
      nil
      iex> TalesForge.Game.Movement.way_in(world, "inn", "I go inside")
      nil
  """
  @spec way_in(map(), String.t() | nil, String.t()) :: String.t() | nil
  def way_in(world, from, text) when is_binary(from) and is_binary(text) do
    if tree?(world) do
      lowered = normalize(text)
      locations = places(world)
      kids = children(world, from)

      named =
        Enum.find(kids, fn id ->
          id
          |> match_terms(Map.get(locations, id, %{}))
          |> Enum.any?(&Regex.match?(~r/(?<![\w])#{Regex.escape(&1)}(?![\w])/u, lowered))
        end)

      named || only(kids)
    end
  end

  def way_in(_world, _from, _text), do: nil

  defp only([one]), do: one
  defp only(_list), do: nil

  @doc """
  Resolves an intent target (a location id, a place name or alias, in any
  case, with spaces or underscores) to a reachable location id.

      iex> world = %{"locations" => %{
      ...>   "inn" => %{"exits" => ["market_square"]},
      ...>   "market_square" => %{"name" => "Market Square", "aliases" => ["square"], "exits" => ["inn"]}}}
      iex> TalesForge.Game.Movement.resolve_place(world, "inn", "Market Square")
      {:ok, "market_square"}
      iex> TalesForge.Game.Movement.resolve_place(world, "inn", "the square")
      {:ok, "market_square"}
      iex> TalesForge.Game.Movement.resolve_place(world, "inn", "the moon")
      :error
  """
  @spec resolve_place(map(), String.t() | nil, String.t() | nil) :: {:ok, String.t()} | :error
  def resolve_place(world, from, target) when is_binary(target) do
    wanted = target |> normalize() |> strip_article()
    locations = places(world)

    world
    |> reachable(from)
    |> Enum.find_value(:error, fn {id, _hops} ->
      if wanted in terms(id, Map.get(locations, id, %{})), do: {:ok, id}
    end)
  end

  def resolve_place(_world, _from, _target), do: :error

  @doc """
  The reachable place a sentence sends the character to: a place name or alias
  that follows a word like "to", "toward", "into" or "up" ("head up to the
  cut", "step out into the square"). Several candidates: the one nearest the
  lead-in word wins, then the nearest place. nil when none does.

      iex> world = %{"locations" => %{
      ...>   "inn" => %{"exits" => ["market_square"]},
      ...>   "market_square" => %{"name" => "Market Square", "aliases" => ["the square"],
      ...>     "exits" => ["inn", "orc_nest"]},
      ...>   "orc_nest" => %{"name" => "Orc nest", "exits" => ["market_square"]}}}
      iex> TalesForge.Game.Movement.mentioned_place(world, "inn",
      ...>   "I head out toward the market square to claim the orc nest job")
      "market_square"
      iex> TalesForge.Game.Movement.mentioned_place(world, "inn", "Tell me about the orc nest")
      nil
  """
  @spec mentioned_place(map(), String.t() | nil, String.t()) :: String.t() | nil
  def mentioned_place(world, from, text) do
    case mentioned_places(world, from, text) do
      [{id, _pos} | _] -> id
      [] -> nil
    end
  end

  @doc """
  Every reachable place named after a lead-in word in `text`, as `{id,
  position}` (byte offset in the lower-cased text), earliest first, then
  nearest. The intent step uses the position to check that a verb of motion
  comes just before.
  """
  @spec mentioned_places(map(), String.t() | nil, String.t()) :: [{String.t(), non_neg_integer()}]
  def mentioned_places(world, from, text) when is_binary(text) do
    lowered = normalize(text)
    locations = places(world)

    world
    |> reachable(from)
    |> Enum.flat_map(fn {id, hops} ->
      id
      |> match_terms(Map.get(locations, id, %{}))
      |> Enum.flat_map(&led_in_matches(lowered, &1))
      |> Enum.map(fn {pos, term} -> {id, hops, pos, term} end)
    end)
    |> Enum.sort_by(fn {_id, hops, pos, term} -> {pos, hops, -byte_size(term)} end)
    |> Enum.map(fn {id, _hops, pos, _term} -> {id, pos} end)
  end

  def mentioned_places(_world, _from, _text), do: []

  # Words to look for in running text: the id as words and the name without a
  # leading "the", and the aliases as written ("the cut" must say "the cut",
  # so "to cut off the chill" is no place).
  defp match_terms(id, location) do
    named =
      [String.replace(id, "_", " "), Map.get(location, "name")]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.map(&(&1 |> normalize() |> strip_article()))

    aliases =
      location
      |> Map.get("aliases")
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.map(&normalize/1)

    Enum.uniq(named ++ aliases)
  end

  # Positions of `term` (whole words) in `text` that a lead-in word precedes.
  defp led_in_matches(text, term) do
    ~r/(?<![\w])#{Regex.escape(term)}(?![\w])/u
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [{pos, _len}] ->
      start = max(pos - @window, 0)
      before = binary_part(text, start, pos - start)
      if Regex.match?(@lead_in, before), do: [{pos, term}], else: []
    end)
  end

  @doc """
  The words that name a location: its id (with underscores and as words), its
  name, its aliases, each lower-cased and without a leading "the".

      iex> TalesForge.Game.Movement.terms("orc_approach", %{"name" => "Cut above the nest", "aliases" => ["the cut"]})
      ["orc_approach", "orc approach", "cut above the nest", "cut"]
  """
  @spec terms(String.t(), location()) :: [String.t()]
  def terms(id, location) do
    [id, String.replace(id, "_", " "), Map.get(location, "name") | List.wrap(location["aliases"])]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(&(&1 |> normalize() |> strip_article()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  Display name of a location id (its `name`, else the id).

      iex> TalesForge.Game.Movement.name(%{"locations" => %{"inn" => %{"name" => "Valley Inn"}}}, "inn")
      "Valley Inn"
  """
  @spec name(map(), String.t() | nil) :: String.t() | nil
  def name(_world, nil), do: nil

  def name(world, id) do
    world |> places() |> Map.get(id, %{}) |> Map.get("name", id)
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[’']/u, "'")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp strip_article("the " <> rest), do: rest
  defp strip_article(text), do: text
end
