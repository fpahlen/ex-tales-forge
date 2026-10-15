defmodule TalesForge.Game.Progression do
  @moduledoc """
  Skill growth: you learn from failure, only in the
  skill you failed, and it sinks in while you sleep (decisions 2026-10-09,
  tales-forge-docs `docs/decisions.md`, superseding the 2026-10-07 "LP spent
  every turn" rule).

  - **Earning:** a failed or partial roll banks one improvement chance (1 LP)
    for that exact skill (`TalesForge.Game.Mechanics`). A success banks
    nothing, and nothing spills to other skills. The linked stat adds no LP.
  - **When:** banked LP are resolved on a long rest, a wait of
    `long_rest_hours` (6) hours or more such as sleep (`long_rest?/1`), not at
    the end of each turn (`resolve_rest/3`, called by
    `TalesForge.Game.TurnProcessor`).
  - **Higher levels need more failures:** one improvement roll costs
    `lp_per_roll/1` banked LP, `ceil(level / 3)` (at least 1): 1 LP up to
    level 15, 2 up to 30, 3 up to 45, 4 up to 60 and so on.
  - **The roll:** 1d100; the skill gains 1d6+1 when the roll is **at least 51 and
    at least the skill's level** (`improves?/3`), a chance of
    `(101 − max(level, 51)) / 100`: at most 50%, 1% at 100, nothing past 100
    without a trainer.
  - **At most one success per skill per night, and nothing carries over:** the rolls
    stop at the first success, and every banked LP of that skill is then gone,
    whether a roll succeeded, all failed, or the LP were too few for one roll.
  - **Reflection from level 50 (`reflection_level`):** a skill at that level or
    higher is only resolved on a rest where the character reflected on it,
    practised or studied it, or trained it with a trainer since the last long
    rest (`TalesForge.Game.Reflection`). Otherwise its LP **stay banked** (the
    one case where LP carry over) and the skill is reported as needing
    reflection, for the GM's note.
  - **Physical skills improve right away (decision 2026-10-09, ~16:04):** the
    skills in `immediate_skills/0` (melee, ranged and unarmed combat, dodge,
    climbing, lockpicking) are resolved at the end of the turn of the failure
    (`resolve_turn/3`) with the same LP-per-roll cost, roll and reflection
    gate. They too gain **at most once per long-rest cycle**: once one improves,
    it is listed in the character's `"improved_since_rest"` and any LP it banks
    are dropped until the next long rest, so it cannot be spammed. LP too few
    for a roll wait for more failures within the cycle; the long rest then
    clears them like any other skill's.
  - **Trainers:** a training session is one **free** attempt (no LP) with
    **+25** on the roll (`train/3`), paid for in coin and days
    (`TalesForge.Game.Train`).

  The numbers (`attempt_floor`, `lp_per_roll_divisor`, `reflection_level`,
  `long_rest_hours`) are in `config/config.exs` under
  `config :ex_tales_forge, TalesForge.Game.Progression`.

  Every roll is one entry in the turn's `mechanical_resolution["improvements"]`
  (`skill`, `roll`, `raw_skill`, `improved`, `lp_spent`, plus `lp_cleared` on
  the last roll of a skill and `bonus` for a trainer), which
  `TalesForge.Playtest.Growth` counts per run.
  """

  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.WorldClock

  @trainer_bonus 25
  @defaults [
    attempt_floor: 51,
    lp_per_roll_divisor: 15,
    reflection_level: 50,
    long_rest_hours: 6,
    gain_die: 6,
    gain_flat: 1,
    skill_cap: 100
  ]

  # Skills resolved at the end of the turn of the failure instead of waiting
  # for sleep: the physical ones (decision 2026-10-09, ~16:04).
  @immediate_skills ~w(climbing dodge lockpicking melee_combat ranged_combat unarmed_combat)

  @typedoc "A character sheet map (string keys, as in `world_state[\"character\"]`)."
  @type character :: map()

  @typedoc "One improvement attempt, as stored in the turn's `improvements`."
  @type attempt :: %{required(String.t()) => term()}

  @typedoc """
  Injected d100 results for tests, per skill: one integer for every attempt, or
  a list used in order (then random once it runs out).
  """
  @type rolls :: %{optional(String.t()) => roll() | [roll()]}

  @typedoc "A d100 result, or `{roll, gain}` to fix the improvement gain in tests."
  @type roll :: 1..100 | {1..100, pos_integer() | nil}

  @typedoc "What a rest did: the updated sheet, its rolls, and skills that need reflection."
  @type rest_result :: {character(), [attempt()], [String.t()]}

  @doc """
  A growth setting from `config :ex_tales_forge, TalesForge.Game.Progression`
  (`:attempt_floor`, `:lp_per_roll_divisor`, `:reflection_level`,
  `:long_rest_hours`).

      iex> TalesForge.Game.Progression.setting(:reflection_level)
      50
  """
  @spec setting(atom()) :: pos_integer()
  def setting(key) when is_atom(key) do
    :ex_tales_forge
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, Keyword.fetch!(@defaults, key))
  end

  @doc """
  The chance that one roll raises a skill at `level`:
  `(101 − max(level, 51)) / 100`, between 0 and 0.5.

      iex> Enum.map([0, 50, 51, 55, 95, 100, 101], &TalesForge.Game.Progression.success_chance/1)
      [0.5, 0.5, 0.5, 0.46, 0.06, 0.01, 0.0]
  """
  @spec success_chance(integer()) :: float()
  def success_chance(level) when is_integer(level),
    do:
      ((101 - max(level, setting(:attempt_floor))) / 100)
      |> max(0.0)
      |> min(1.0)
      |> Float.round(4)

  @doc """
  Whether a roll raises the skill: `roll + bonus` must reach both the floor of
  51 and the skill's level, so no roll is a sure thing.

      iex> TalesForge.Game.Progression.improves?(51, 0)
      true
      iex> TalesForge.Game.Progression.improves?(50, 0)
      false
      iex> TalesForge.Game.Progression.improves?(60, 65)
      false
      iex> TalesForge.Game.Progression.improves?(75, 100, 25)
      true
  """
  @spec improves?(integer(), integer(), integer()) :: boolean()
  def improves?(roll, level, bonus \\ 0)
      when is_integer(roll) and is_integer(level) and is_integer(bonus),
      do: roll + bonus >= max(level, setting(:attempt_floor))

  @doc """
  The lowest roll (with any trainer bonus) that can raise a skill.

      iex> TalesForge.Game.Progression.attempt_floor()
      51
  """
  @spec attempt_floor() :: pos_integer()
  def attempt_floor, do: setting(:attempt_floor)

  @doc """
  Banked LP one improvement roll costs at `level`: `ceil(level / 15)`, at least 1.

      iex> Enum.map([0, 15, 16, 30, 31, 50, 65, 80, 95], &TalesForge.Game.Progression.lp_per_roll/1)
      [1, 1, 2, 2, 3, 4, 5, 6, 7]
  """
  @spec lp_per_roll(integer()) :: pos_integer()
  def lp_per_roll(level) when is_integer(level) do
    divisor = setting(:lp_per_roll_divisor)
    max(1, div(level + divisor - 1, divisor))
  end

  @doc """
  Whether a skill at `level` needs reflection before it can grow.

      iex> {TalesForge.Game.Progression.needs_reflection?(49), TalesForge.Game.Progression.needs_reflection?(50)}
      {false, true}
  """
  @spec needs_reflection?(integer()) :: boolean()
  def needs_reflection?(level) when is_integer(level), do: level >= setting(:reflection_level)

  @doc """
  Whether a pause of `ticks` world ticks is a long rest (sleep, or a wait of
  six hours or more), the moment banked LP are resolved.

      iex> TalesForge.Game.Progression.long_rest?(32)
      true
      iex> TalesForge.Game.Progression.long_rest?(4)
      false
  """
  @spec long_rest?(integer()) :: boolean()
  def long_rest?(ticks) when is_integer(ticks),
    do: ticks >= setting(:long_rest_hours) * WorldClock.ticks_per_hour()

  @doc """
  The skills resolved at the end of the turn of the failure instead of on a
  long rest: the physical ones. Every other skill waits for sleep.

      iex> TalesForge.Game.Progression.immediate_skills()
      ["climbing", "dodge", "lockpicking", "melee_combat", "ranged_combat", "unarmed_combat"]
  """
  @spec immediate_skills() :: [String.t()]
  def immediate_skills, do: @immediate_skills

  @doc """
  The bonus a trainer adds to the attempt roll.

      iex> TalesForge.Game.Progression.trainer_bonus()
      25
  """
  @spec trainer_bonus() :: pos_integer()
  def trainer_bonus, do: @trainer_bonus

  @doc """
  Resolves the banked LP of every skill on a long rest, skill by skill
  (alphabetical). Per skill: `div(lp, lp_per_roll(level))` rolls, stopping at
  the first success (+1); then all of the skill's LP are cleared, success or
  not. A skill at `reflection_level` or above that is not in
  `opts[:reflected]` keeps its LP and is returned in the third element.
  `opts[:only]` limits the rest to those skills.

      iex> character = %{"skills" => %{"climbing" => 25}, "learning_points" => %{"climbing" => 5.0}}
      iex> {rested, attempts, []} =
      ...>   TalesForge.Game.Progression.resolve_rest(character, %{"climbing" => [3, {55, 5}]})
      iex> {rested["skills"]["climbing"], rested["learning_points"]["climbing"]}
      {30, 0.0}
      iex> Enum.map(attempts, &{&1["roll"], &1["improved"], &1["lp_spent"]})
      [{3, false, 2}, {55, true, 2}]
      iex> List.last(attempts)["lp_cleared"]
      1
  """
  @spec resolve_rest(character(), rolls(), keyword()) :: rest_result()
  def resolve_rest(character, rolls \\ %{}, opts \\ [])
      when is_map(character) and is_map(rolls) and is_list(opts) do
    only = Keyword.get(opts, :only)
    reflected = Keyword.get(opts, :reflected, [])

    character
    |> Map.get("learning_points", %{})
    |> Enum.filter(fn {skill, lp} -> to_float(lp) > 0.0 and (is_nil(only) or skill in only) end)
    |> Enum.map(fn {skill, _lp} -> skill end)
    |> Enum.sort()
    |> Enum.reduce({character, [], [], rolls}, fn skill, {char, acc, pending, rolls} ->
      level = char |> get_in(["skills", skill]) |> to_int()

      if needs_reflection?(level) and skill not in reflected do
        {char, acc, pending ++ [skill], rolls}
      else
        {char, attempts, rolls} = resolve_skill(char, skill, level, rolls)
        {char, acc ++ attempts, pending, rolls}
      end
    end)
    |> then(fn {char, attempts, pending, _rolls} -> {char, attempts, pending} end)
  end

  @doc """
  End of an ordinary turn (not a long rest): resolves the banked LP of the
  immediate (physical) skills right away. Per skill, in alphabetical order:

  - already improved since the last long rest (`"improved_since_rest"`): its
    LP are dropped, no roll (at most one success per skill per long-rest cycle);
  - at `reflection_level` or above and not in `opts[:reflected]`: nothing
    happens, its LP stay banked for the rest;
  - otherwise `div(lp, lp_per_roll(level))` rolls, stopping at the first
    success. On a success the skill gains +1, all its LP are cleared and it
    joins `"improved_since_rest"`. If no roll succeeds, the spent LP are gone
    and the remainder (too few for a roll) stays banked for later this cycle.

      iex> character = %{"skills" => %{"climbing" => 25}, "learning_points" => %{"climbing" => 3.0}}
      iex> {now, attempts} = TalesForge.Game.Progression.resolve_turn(character, %{"climbing" => [{60, 4}]})
      iex> {now["skills"]["climbing"], now["learning_points"]["climbing"], now["improved_since_rest"]}
      {29, 0.0, ["climbing"]}
      iex> Enum.map(attempts, &{&1["roll"], &1["improved"], &1["lp_spent"], &1["lp_cleared"]})
      [{60, true, 2, 1}]
      iex> {again, []} = TalesForge.Game.Progression.resolve_turn(put_in(now, ["learning_points", "climbing"], 4.0))
      iex> {again["skills"]["climbing"], again["learning_points"]["climbing"]}
      {29, 0.0}
  """
  @spec resolve_turn(character(), rolls(), keyword()) :: {character(), [attempt()]}
  def resolve_turn(character, rolls \\ %{}, opts \\ [])
      when is_map(character) and is_map(rolls) and is_list(opts) do
    reflected = Keyword.get(opts, :reflected, [])

    character
    |> Map.get("learning_points", %{})
    |> Enum.filter(fn {skill, lp} -> skill in @immediate_skills and to_float(lp) > 0.0 end)
    |> Enum.map(fn {skill, _lp} -> skill end)
    |> Enum.sort()
    |> Enum.reduce({character, [], rolls}, fn skill, {char, acc, rolls} ->
      {char, attempts, rolls} = resolve_now(char, skill, reflected, rolls)
      {char, acc ++ attempts, rolls}
    end)
    |> then(fn {char, attempts, _rolls} -> {char, attempts} end)
  end

  @doc """
  The banked LP a character holds, per skill (whole LP only).

      iex> TalesForge.Game.Progression.banked(%{"learning_points" => %{"stealth" => 2.5, "climbing" => 0.5}})
      %{"stealth" => 2}
  """
  @spec banked(character()) :: %{String.t() => pos_integer()}
  def banked(character) when is_map(character) do
    character
    |> Map.get("learning_points", %{})
    |> Enum.map(fn {skill, lp} -> {skill, lp |> to_float() |> trunc()} end)
    |> Enum.filter(fn {_skill, n} -> n > 0 end)
    |> Map.new()
  end

  @doc """
  One training session: a free attempt (no LP spent) with the trainer bonus on
  the roll. Whether the session may happen at all (trainer present, skill gap,
  fee, vitality) is `TalesForge.Game.Train.qualify/5`.

      iex> character = %{"skills" => %{"persuasion" => 60}, "learning_points" => %{}}
      iex> {trained, attempt} = TalesForge.Game.Progression.train(character, "persuasion", %{"persuasion" => {35, 3}})
      iex> {trained["skills"]["persuasion"], attempt["bonus"], attempt["lp_spent"]}
      {63, 25, 0}
  """
  @spec train(character(), String.t(), rolls()) :: {character(), attempt()}
  def train(character, skill, rolls \\ %{})
      when is_map(character) and is_binary(skill) and is_map(rolls) do
    {roll, _rolls} = next_roll(rolls, skill)
    {updated, entry} = attempt(character, skill, roll, @trainer_bonus)
    {updated, entry |> Map.put("bonus", @trainer_bonus) |> Map.put("lp_spent", 0)}
  end

  # Rolls until the first success or until the LP run out, then clears every
  # LP of the skill: nothing carries over to the next night.
  defp resolve_skill(character, skill, level, rolls) do
    lp = character |> get_in(["learning_points", skill]) |> to_float() |> trunc()
    cost = lp_per_roll(level)

    {character, rolled, rolls} =
      roll_until_success(character, skill, div(lp, cost), cost, rolls)

    {put_in(character, ["learning_points", skill], 0.0), mark_cleared(rolled, lp, cost), rolls}
  end

  # One immediate skill at the end of a turn (resolve_turn/3).
  defp resolve_now(character, skill, reflected, rolls) do
    level = character |> get_in(["skills", skill]) |> to_int()

    cond do
      skill in Map.get(character, "improved_since_rest", []) ->
        {put_in(character, ["learning_points", skill], 0.0), [], rolls}

      needs_reflection?(level) and skill not in reflected ->
        {character, [], rolls}

      true ->
        roll_now(character, skill, level, rolls)
    end
  end

  defp roll_now(character, skill, level, rolls) do
    lp = character |> get_in(["learning_points", skill]) |> to_float()
    cost = lp_per_roll(level)

    {character, rolled, rolls} =
      roll_until_success(character, skill, div(trunc(lp), cost), cost, rolls)

    if Enum.any?(rolled, & &1["improved"]) do
      {character |> put_in(["learning_points", skill], 0.0) |> mark_improved(skill),
       mark_cleared(rolled, trunc(lp), cost), rolls}
    else
      {put_in(character, ["learning_points", skill], lp - cost * length(rolled)), rolled, rolls}
    end
  end

  defp mark_improved(character, skill) do
    already = Map.get(character, "improved_since_rest", [])
    Map.put(character, "improved_since_rest", Enum.sort(Enum.uniq([skill | already])))
  end

  # The last roll of a skill records the LP left over and cleared with it.
  defp mark_cleared([], _lp, _cost), do: []

  defp mark_cleared(rolled, lp, cost),
    do: List.update_at(rolled, -1, &Map.put(&1, "lp_cleared", lp - cost * length(rolled)))

  defp roll_until_success(character, _skill, 0, _cost, rolls), do: {character, [], rolls}

  defp roll_until_success(character, skill, left, cost, rolls) do
    {roll, rolls} = next_roll(rolls, skill)
    {updated, result} = attempt(character, skill, roll, 0)
    entry = Map.put(result, "lp_spent", cost)

    if entry["improved"] do
      {updated, [entry], rolls}
    else
      {updated, more, rolls} = roll_until_success(updated, skill, left - 1, cost, rolls)
      {updated, [entry | more], rolls}
    end
  end

  defp attempt(character, skill, {roll, gain}, bonus) do
    level = character |> get_in(["skills", skill]) |> to_int()
    improved = improves?(roll, level, bonus)
    gain = if improved, do: gain || improvement_gain(), else: 0
    new_level = min(setting(:skill_cap), level + gain)

    updated =
      character
      |> Map.put_new("skills", %{})
      |> Map.put_new("learning_points", %{})
      |> then(&if improved, do: put_in(&1, ["skills", skill], new_level), else: &1)

    # The sheet shows the effective level (with the stat bonus or the
    # untrained floor), so the entry also has it before and after (QA
    # 2026-10-15: "melee combat +5 (5 to 10)" while the sheet went 10% to 15%).
    entry =
      %{"skill" => skill, "roll" => roll, "raw_skill" => level, "improved" => improved}
      |> then(&if improved, do: Map.put(&1, "gain", new_level - level), else: &1)
      |> then(
        &if improved,
          do:
            Map.merge(&1, %{
              "effective_before" => Mechanics.effective_level(character, skill),
              "effective_after" => Mechanics.effective_level(updated, skill)
            }),
          else: &1
      )

    {updated, entry}
  end

  @doc """
  Points a successful improvement adds: `1d6 + 1` (2 to 7). The skill never
  passes `skill_cap` (100). Tests inject `{roll, gain}` pairs as rolls.
  """
  @spec improvement_gain() :: pos_integer()
  def improvement_gain,
    do: :rand.uniform(setting(:gain_die)) + setting(:gain_flat)

  # An injected roll is a d100 result or a `{roll, gain}` pair.
  defp next_roll(rolls, skill) do
    case Map.get(rolls, skill) do
      [roll | rest] -> {pair(roll), Map.put(rolls, skill, rest)}
      roll when is_integer(roll) or is_tuple(roll) -> {pair(roll), rolls}
      _ -> {{:rand.uniform(100), nil}, rolls}
    end
  end

  defp pair({roll, gain}) when is_integer(roll), do: {roll, gain}
  defp pair(roll) when is_integer(roll), do: {roll, nil}

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: trunc(value)
  defp to_int(_value), do: 0

  defp to_float(value) when is_number(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp to_float(_value), do: 0.0
end
