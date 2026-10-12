defmodule TalesForge.Game.Notice do
  @moduledoc """
  How much the character notices (decision 2026-10-12, "high vs low skills
  storytelling"; `SKILL_DETAIL_LEVEL=on`). All functions are pure.

    * `level/1` — the detail level from the server's resolution;
    * `passive_level/1` — the level on a turn with no roll;
    * `details/3` — 0 to 2 true details from the world state.

  The thresholds are in `priv/rules/detail_levels.json`. The server selects
  the details; the GM only narrates them.
  """

  alias TalesForge.Game.Schemas.MechanicalResolution

  @path Path.expand("../../../priv/rules/detail_levels.json", __DIR__)
  @external_resource @path
  @rules @path |> File.read!() |> Jason.decode!()
  @order [:low, :medium, :high]

  @type level :: :low | :medium | :high

  @trait_words %{
    {"neuroticism", :high} => "is on edge",
    {"neuroticism", :low} => "stays calm under pressure",
    {"agreeableness", :high} => "is eager to please",
    {"agreeableness", :low} => "is guarded and hard to win over",
    {"extraversion", :high} => "loves to talk",
    {"extraversion", :low} => "keeps to themselves",
    {"conscientiousness", :high} => "is careful and exact",
    {"conscientiousness", :low} => "is careless with details",
    {"openness", :high} => "is open to new ideas",
    {"openness", :low} => "is set in their ways"
  }

  @doc """
  The detail level of a rolled action. The effective skill sets the base
  level. A success with a margin of 5 or more, or a natural 1, adds one level.
  A failure keeps the base level. With no roll: the effective skill one level
  lower (see `passive_level/1`), or `:low` when there is no skill.

      iex> alias TalesForge.Game.Schemas.MechanicalResolution, as: M
      iex> TalesForge.Game.Notice.level(%M{skill: "insight", roll: 4, effective_skill: 3, outcome: "failure"})
      :low
      iex> TalesForge.Game.Notice.level(%M{skill: "insight", roll: 9, effective_skill: 8, outcome: "partial_success"})
      :medium
      iex> TalesForge.Game.Notice.level(%M{skill: "insight", roll: 2, effective_skill: 8, outcome: "success"})
      :high
      iex> TalesForge.Game.Notice.level(%M{skill: "insight", roll: 1, effective_skill: 4, outcome: "success"})
      :medium
      iex> TalesForge.Game.Notice.level(%M{skill: "insight", roll: 18, effective_skill: 14, outcome: "failure"})
      :high
      iex> TalesForge.Game.Notice.level(%M{skill: nil, roll: nil, effective_skill: nil})
      :low
  """
  @spec level(MechanicalResolution.t() | map()) :: level()
  def level(%{roll: roll, effective_skill: skill} = mechanical)
      when is_integer(roll) and is_number(skill) do
    base = base_level(skill)
    if bonus?(mechanical), do: up(base), else: base
  end

  def level(%{effective_skill: skill}) when is_number(skill), do: down(base_level(skill))
  def level(_mechanical), do: :low

  @doc """
  The level on a turn with no roll: the character's perception skill (or
  insight, the same sense today) sets the base level, one level lower.

      iex> TalesForge.Game.Notice.passive_level(%{"character" => %{"skills" => %{"insight" => 13}}})
      :medium
      iex> TalesForge.Game.Notice.passive_level(%{})
      :low
  """
  @spec passive_level(map()) :: level()
  def passive_level(world) do
    skills = get_in(world, ["character", "skills"]) || %{}

    @rules["passive_skills"]
    |> Enum.find_value(0, &number(skills[&1]))
    |> base_level()
    |> down()
  end

  @doc """
  The details the character notices at `level`, true in `world`: 0 at low,
  1 at medium, 2 at high. The sources, in order:

    1. a front fact with a `notice` field (`skill`, `min_level`) for this
       skill (or `"any"`), at that level or higher;
    2. for each present NPC: the mood under the surface (the NPC reaction),
       the concern on their mind, and one strong personality trait.

  `world` is the turn's world state plus `"npc_profiles"` (the present NPCs:
  `name`, `personality_traits`, `concern_focus`) and `"front_facts"`. Each
  detail is hidden from the player today; none is made up.

      iex> world = %{
      ...>   "present_npcs" => ["innkeep"],
      ...>   "npc_moods" => %{"innkeep" => %{"emotion" => "wary"}},
      ...>   "npc_profiles" => [%{"id" => "innkeep", "name" => "Brenna Holt",
      ...>     "concern_focus" => "the restless hills",
      ...>     "personality_traits" => %{"neuroticism" => 3, "extraversion" => 8}}]
      ...> }
      iex> TalesForge.Game.Notice.details(world, "insight", :low)
      []
      iex> TalesForge.Game.Notice.details(world, "insight", :medium)
      ["Under the surface, Brenna Holt is wary."]
      iex> TalesForge.Game.Notice.details(world, "insight", :high)
      ["Under the surface, Brenna Holt is wary.", "Brenna Holt's mind is on the restless hills."]
  """
  @spec details(map(), String.t() | nil, level()) :: [String.t()]
  def details(world, skill, level) do
    count = @rules["details"][Atom.to_string(level)] || 0

    (front_details(world, skill, level) ++ npc_details(world))
    |> Enum.uniq()
    |> Enum.take(count)
  end

  @doc "The number of details at `level`."
  @spec count(level()) :: non_neg_integer()
  def count(level), do: @rules["details"][Atom.to_string(level)] || 0

  defp front_details(world, skill, level) do
    world
    |> Map.get("front_facts", [])
    |> Enum.filter(fn fact ->
      notice = fact["notice"] || %{}

      is_binary(fact["text"]) and notice["skill"] in [skill, "any"] and
        rank(level) >= rank(to_level(notice["min_level"]))
    end)
    |> Enum.map(& &1["text"])
  end

  defp npc_details(world) do
    present = List.wrap(world["present_npcs"])
    moods = world["npc_moods"] || %{}

    world
    |> Map.get("npc_profiles", [])
    |> Enum.filter(&(&1["id"] in present))
    |> Enum.flat_map(fn npc ->
      name = npc["name"] || npc["id"]

      [
        mood_detail(name, moods[npc["id"]]),
        concern_detail(name, npc["concern_focus"]),
        trait_detail(name, npc["personality_traits"])
      ]
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp mood_detail(name, %{"emotion" => emotion}) when is_binary(emotion) and emotion != "",
    do: "Under the surface, #{name} is #{emotion}."

  defp mood_detail(_name, _mood), do: nil

  defp concern_detail(name, focus) when is_binary(focus) and focus != "",
    do: "#{name}'s mind is on #{focus}."

  defp concern_detail(_name, _focus), do: nil

  defp trait_detail(name, traits) when is_map(traits) do
    traits
    |> Enum.flat_map(fn {trait, value} -> trait_end(trait, number(value)) end)
    |> Enum.sort()
    |> case do
      [{_strength, words} | _] -> "#{name} #{words}."
      [] -> nil
    end
  end

  defp trait_detail(_name, _traits), do: nil

  # A strong trait (8+ or 2-), strongest first.
  defp trait_end(trait, value) when is_number(value) and value >= 8,
    do: words(trait, :high, -value)

  defp trait_end(trait, value) when is_number(value) and value <= 2,
    do: words(trait, :low, value - 10)

  defp trait_end(_trait, _value), do: []

  defp words(trait, side, strength) do
    case Map.get(@trait_words, {trait, side}) do
      nil -> []
      words -> [{strength, words}]
    end
  end

  defp bonus?(%{roll: 1}), do: true

  defp bonus?(%{roll: roll, effective_skill: skill, outcome: "success"}),
    do: skill - roll >= @rules["success_margin"]

  defp bonus?(_mechanical), do: false

  defp base_level(skill) do
    Enum.find_value(@rules["levels"], :low, fn band ->
      if skill >= band["min"] and skill <= Map.get(band, "max", skill),
        do: String.to_existing_atom(band["level"])
    end)
  end

  defp up(level), do: Enum.at(@order, min(rank(level) + 1, 2))
  defp down(level), do: Enum.at(@order, max(rank(level) - 1, 0))
  defp rank(level), do: Enum.find_index(@order, &(&1 == level)) || 0

  defp to_level(level) when level in @order, do: level
  defp to_level(level) when level in ~w(low medium high), do: String.to_existing_atom(level)
  defp to_level(_level), do: :high

  defp number(n) when is_number(n), do: n
  defp number(_n), do: nil
end
