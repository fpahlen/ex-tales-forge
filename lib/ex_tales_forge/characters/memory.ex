defmodule TalesForge.Characters.Memory do
  @moduledoc """
  Character memory, PR 1 of board card fc3c9371.

  Each character has three tiers: working (the current scene), short-term and
  long-term. At scene end Elixir moves the working memory of every character
  in the scene to short-term: one row per shared event, with the ids the
  event is about and a weight from the character's interests. The GM prompt
  recalls short- and long-term rows by association. No LLM call is made here.

  Interests come from OCEAN, role and concerns. A pack sets its own with
  `interests:` in the NPC file; the player character gets defaults from its
  own OCEAN.

      iex> TalesForge.Characters.Memory.default_interests(%{"extraversion" => 8, "neuroticism" => 7}, "smith", [])
      ["people", "threats", "smith"]

      iex> TalesForge.Characters.Memory.weight(["people"], ["people"], ["mara"])
      1.5
  """

  import Ecto.Query
  require Logger

  alias TalesForge.Characters
  alias TalesForge.Game.Progression
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, CharacterMemory, SessionEvent}

  # OCEAN trait at or above this level gives its interests.
  @high 7
  @trait_interests %{
    "openness" => ["places", "items"],
    "conscientiousness" => ["work", "promises"],
    "extraversion" => ["people"],
    "agreeableness" => ["people", "favours"],
    "neuroticism" => ["threats"]
  }
  @kind_topics [
    {"player.travel", "places"},
    {"npc.", "people"},
    {"player.noticed", "places"},
    {"combat", "threats"},
    {"attack", "threats"},
    {"trade", "items"},
    {"buy", "items"},
    {"sell", "items"},
    {"promise", "promises"},
    {"train", "work"}
  ]
  @recall_cap 5
  @scene_cap 20

  @doc "Interests from OCEAN (a map or struct), role and concerns, deduplicated."
  @spec default_interests(map() | struct() | nil, String.t() | nil, list()) :: [String.t()]
  def default_interests(ocean, role, concerns) do
    ocean = ocean_map(ocean)

    traits =
      ~w(openness conscientiousness extraversion agreeableness neuroticism)
      |> Enum.filter(&((ocean[&1] || 5) >= @high))
      |> Enum.flat_map(&@trait_interests[&1])

    focus = for c <- concerns || [], f = field(c, :focus), is_binary(f) and f != "", do: f
    role = if is_binary(role) and role != "", do: [String.downcase(role)], else: []

    Enum.uniq(traits ++ role ++ focus)
  end

  @doc "A character's interests: the pack's `interests` list, else the defaults."
  @spec interests(Character.t()) :: [String.t()]
  def interests(%Character{} = c) do
    case (c.definition || %{})["interests"] do
      list when is_list(list) and list != [] -> Enum.map(list, &to_string/1)
      _ -> default_interests(c.ocean, c.role, c.concerns)
    end
  end

  @doc "The topics of an event kind (people, places, items, threats, …)."
  @spec topics(String.t()) :: [String.t()]
  def topics(kind) when is_binary(kind) do
    for {prefix, topic} <- @kind_topics, String.contains?(kind, prefix), uniq: true, do: topic
  end

  def topics(_), do: []

  @doc "1.0 plus 0.5 per interest the topics or `about` ids match."
  @spec weight([String.t()], [String.t()], [String.t()]) :: float()
  def weight(interests, topics, about) do
    hits = Enum.count(interests, &(&1 in topics or &1 in about))
    1.0 + 0.5 * hits
  end

  @doc "The ids an event is about: actor, location and string payload values."
  @spec about(map()) :: [String.t()]
  def about(event) do
    payload = get(event, :payload) || %{}

    values =
      for {_k, v} <- payload, is_binary(v), v != "", do: v

    [get(event, :actor), get(event, :location_id) | values]
    |> Enum.filter(&(is_binary(&1) and &1 not in ["", "world"]))
    |> Enum.uniq()
  end

  @doc """
  The location of the scene that ends this turn, or nil: the place the player
  left (`player.travel`), or the place of a long rest.
  """
  @spec scene_end([map()]) :: String.t() | nil
  def scene_end(events) do
    Enum.find_value(events, &scene_end_of/1)
  end

  defp scene_end_of(e) do
    case get(e, :kind) do
      "player.travel" -> get_in(get(e, :payload) || %{}, ["from"])
      "time.passed" -> rest_location(e)
      _ -> nil
    end
  end

  defp rest_location(e), do: if(long_rest?(e), do: get(e, :location_id))

  @doc "True when the events of a turn hold a long rest."
  @spec long_rest_in?([map()]) :: boolean()
  def long_rest_in?(events),
    do: Enum.any?(events, &(get(&1, :kind) == "time.passed" and long_rest?(&1)))

  defp long_rest?(e) do
    delta = (get(e, :payload) || %{})["delta_ticks"]
    is_integer(delta) and Progression.long_rest?(delta)
  end

  @doc """
  Scene end, called after the turn is saved. Does nothing when the flag is
  off or no scene ends. Never fails the turn: returns `:ok`.
  """
  @spec on_turn(Ecto.UUID.t(), [map()], :off | :shadow | :on) :: :ok
  def on_turn(_session_id, _events, :off), do: :ok

  def on_turn(session_id, events, _mode) do
    case scene_end(events) do
      nil -> :ok
      location -> end_scene(session_id, location)
    end
  rescue
    e ->
      Logger.warning("character memory failed session=#{session_id} #{Exception.message(e)}")
      :ok
  end

  @doc """
  Moves the working memory of the scene at `location` to short-term for the
  player character and every character at that place: one row per shared
  event there (not `time.passed`) that the character has no row for yet.
  Returns `:ok`.
  """
  @spec end_scene(Ecto.UUID.t(), String.t()) :: :ok
  def end_scene(session_id, location) do
    events = scene_events(session_id, location)

    session_id
    |> Characters.list_for_session()
    |> Enum.filter(&(&1.controller != "gm" or &1.location_id == location))
    |> Enum.each(&remember(&1, events))

    :ok
  end

  defp scene_events(session_id, location) do
    SessionEvent
    |> where([e], e.game_session_id == ^session_id and e.location_id == ^location)
    |> where([e], e.kind != "time.passed")
    |> order_by([e], desc: e.tick, desc: e.inserted_at)
    |> limit(@scene_cap)
    |> Repo.all()
  end

  defp remember(character, events) do
    known =
      CharacterMemory
      |> where([m], m.character_id == ^character.id and not is_nil(m.session_event_id))
      |> select([m], m.session_event_id)
      |> Repo.all()
      |> MapSet.new()

    interests = interests(character)

    events
    |> Enum.reject(&MapSet.member?(known, &1.id))
    |> Enum.filter(&(&1.player_aware or character.controller == "gm"))
    |> Enum.each(fn e -> {:ok, _} = Characters.add_memory(character, row(e, interests)) end)
  end

  @doc "The short-term row for one event and a character's interests."
  @spec row(map(), [String.t()]) :: map()
  def row(event, interests) do
    about = about(event)
    kind = get(event, :kind)

    %{
      kind: "memory",
      tier: "short",
      text: text(kind, get(event, :payload) || %{}),
      tick: get(event, :tick),
      session_event_id: get(event, :id),
      about: about,
      weight: weight(interests, topics(kind), about)
    }
  end

  defp text(kind, payload) when map_size(payload) == 0, do: kind

  defp text(kind, payload) do
    detail = Enum.map_join(Enum.sort(payload), ", ", fn {k, v} -> "#{k}: #{inspect_value(v)}" end)
    "#{kind} (#{detail})"
  end

  defp inspect_value(v) when is_binary(v), do: v
  defp inspect_value(v), do: inspect(v)

  @doc """
  Recall: a character's short- and long-term memories about any of `ids`,
  heaviest and newest first, at most #{@recall_cap}.
  """
  @spec recall(Character.t(), [String.t()], pos_integer()) :: [CharacterMemory.t()]
  def recall(%Character{id: id}, ids, cap \\ @recall_cap) do
    CharacterMemory
    |> where([m], m.character_id == ^id and m.tier in ["short", "long"])
    |> where([m], fragment("? && ?", m.about, ^ids))
    |> order_by([m], desc: m.weight, desc: m.tick)
    |> limit(^cap)
    |> Repo.all()
  end

  @doc """
  The recall of the present NPCs about the place, each other and the player
  character: `[{slug, [memory]}]`, NPCs without recall left out.
  """
  @spec recall_for_scene(Ecto.UUID.t(), [String.t()], String.t() | nil) :: [{String.t(), list()}]
  def recall_for_scene(session_id, present, location) do
    chars = Characters.list_for_session(session_id)
    pc = Enum.find(chars, &(&1.controller != "gm"))
    ids = Enum.reject([location, pc && pc.slug | present], &is_nil/1)

    for c <- chars, c.slug in present, (mems = recall(c, ids)) != [], do: {c.slug, mems}
  end

  @doc "The prompt section for a scene recall, or nil when it is empty."
  @spec section([{String.t(), list()}]) :: String.t() | nil
  def section([]), do: nil

  def section(recall) do
    lines =
      for {slug, mems} <- recall, m <- mems, do: "- #{slug} remembers: #{m.text}"

    Enum.join(["## What the NPCs remember (from earlier scenes)" | lines], "\n")
  end

  @doc "Per character: interests and row count per tier, for the playtest view."
  @spec overview(Ecto.UUID.t()) :: [map()]
  def overview(session_id) do
    counts =
      CharacterMemory
      |> join(:inner, [m], c in Character, on: c.id == m.character_id)
      |> where([_m, c], c.game_session_id == ^session_id)
      |> group_by([m], [m.character_id, m.tier])
      |> select([m], {m.character_id, m.tier, count(m.id)})
      |> Repo.all()

    for c <- Characters.list_for_session(session_id) do
      tiers = for {id, t, n} <- counts, id == c.id, into: %{}, do: {t, n}

      %{
        slug: c.slug,
        interests: interests(c),
        working: Map.get(tiers, "working", 0),
        short: Map.get(tiers, "short", 0),
        long: Map.get(tiers, "long", 0),
        recent: recent(c)
      }
    end
  end

  defp recent(c) do
    CharacterMemory
    |> where([m], m.character_id == ^c.id and m.tier in ["short", "long"])
    |> order_by([m], desc: m.tick, desc: m.weight)
    |> limit(3)
    |> Repo.all()
  end

  defp ocean_map(nil), do: %{}

  defp ocean_map(%_{} = s),
    do: s |> Map.from_struct() |> Map.new(fn {k, v} -> {to_string(k), v} end)

  defp ocean_map(m) when is_map(m), do: Map.new(m, fn {k, v} -> {to_string(k), v} end)

  defp field(%_{} = s, k), do: Map.get(s, k)
  defp field(m, k) when is_map(m), do: m[k] || m[to_string(k)]
  defp field(_, _), do: nil

  defp get(m, k), do: Map.get(m, k) || Map.get(m, to_string(k))
end
