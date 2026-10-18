defmodule TalesForge.Game.Mechanics do
  @moduledoc """
  Server-side dice rolls and Learning Points.

  A skill check rolls 1d100 against the effective skill (raw level plus the
  linked stat's bonus, or the untrained floor at level 0): equal or under
  succeeds. The outcome order is critical success, success, critical failure,
  near miss, failure (`resolve_check/2`).

  What a roll earns (decision 2026-10-09): only a failure or a partial
  success earns, and only for the skill rolled: 1 LP, one banked improvement
  chance (`growth_lp/1`). A success or a critical success earns nothing, a critical failure earns
  nothing, and
  the linked stat adds nothing. `TalesForge.Game.Progression` resolves the
  banked chances on a long rest. Failures are counted in
  `learning_failures`.

  Vitality (wounds, down, death rolls) is here too.
  """

  defmodule Roll do
    @moduledoc false
    # One d100 check: the normalized skill, the effective level and an
    # injected roll (tests, replays) or nil.
    @enforce_keys [:skill, :effective]
    defstruct [:skill, :effective, :injected]
  end

  defmodule Harm do
    @moduledoc """
    The harm step of a turn (`TalesForge.Game.Mechanics.apply_character_vitality/3`):
    the mechanical resolution (its LP go on a fatal death roll) and an
    injected death roll (1..100) or nil.
    """
    defstruct [:mechanical, :death_roll]
    @type t :: %__MODULE__{}
  end

  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction}
  alias TalesForge.GameCharacter

  @skill_stat %{
    "melee_combat" => "STR",
    "ranged_combat" => "DEX",
    "unarmed_combat" => "STR",
    "tactics" => "INT",
    "dodge" => "DEX",
    "stealth" => "DEX",
    "lockpicking" => "DEX",
    "climbing" => "STR",
    "persuasion" => "CHA",
    "deception" => "CHA",
    "intimidation" => "CHA",
    "insight" => "WIS",
    "etiquette" => "CHA",
    "survival" => "CON",
    "tracking" => "WIS",
    "history" => "INT",
    "arcana" => "INT"
  }

  # Skill list v2 (decision 2026-10-12, JEV_CATALOGUE_V2): 28 skills in five
  # domains. The stat lookup always knows them; the list of valid skills
  # (`skill_stat_map/0`) has them only with the flag on.
  @skill_stat_v2 Map.merge(@skill_stat, %{
                   "sleight_of_hand" => "DEX",
                   "acrobatics" => "DEX",
                   "perception" => "WIS",
                   "performance" => "CHA",
                   "medicine" => "WIS",
                   "appraisal" => "INT",
                   "smithing" => "STR",
                   "carpentry" => "DEX",
                   "leatherworking" => "DEX",
                   "cooking" => "WIS",
                   "alchemy" => "INT"
                 })

  # Verbs that mean a real check: someone resists, something is hidden, or
  # failing costs something. Ordinary talk ("ask", "greet", "tell") and
  # looking around are not here: they get no roll (decision 2026-10-07).
  @check_skill_hints [
    {~r/\b(sneak|hide|stealth)\b/i, "stealth"},
    {~r/\b(persuad\w*|convinc\w*|barter|haggle)\b/i, "persuasion"},
    {~r/\b(lie|bluff|deceiv\w*)\b/i, "deception"},
    {~r/\b(intimidat\w*|threaten\w*|menac\w*)\b/i, "intimidation"},
    {~r/\b(search|inspect|examine)\b/i, "insight"},
    {~r/\b(fight|attack|strike|swing|stab)\b/i, "melee_combat"},
    {~r/\b(shoot|aim|bow|arrow)\b/i, "ranged_combat"},
    # "scale" only as a verb with something to go up: "silver to the scale"
    # in Paul's speech to Rusk rolled climbing (run 3f7777a6, turn 7).
    {~r/\b(?:climb(?:s|ing)?|scal(?:e|es|ing) (?:the|a|an|that|this|those|its|his|her|up|down))\b/i,
     "climbing"},
    {~r/\b(track|follow trail)\b/i, "tracking"},
    {~r/\b(pick the lock|pick a lock|lockpick\w*)\b/i, "lockpicking"}
  ]

  # Fight verbs and their skill. When a text names several (loose an arrow,
  # then draw a knife), the first one in the text decides.
  @combat_skill_hints [
    {~r/\b(punch\w*|kick\w*|tackl\w*|grappl\w*|wrestl\w*|headbutt\w*|fists?)\b/i,
     "unarmed_combat"},
    {~r/\b(shoot\w*|aim(?:s|ing)? at|nock\w*|draw(?:s|ing)? (?:my |the |his |her )?bow|loos(?:e|es|ing) (?:an |another |my |a |the |two |more )?(?:arrow|shaft|bolt)s?|fir(?:e|es|ing) (?:an |another |my |a |the |two |more )?(?:arrow|shaft|bolt)s?|fir(?:e|es|ing) at|hurl(?:s|ing)?|throw(?:s|ing)? (?:my |the |a )?(?:knife|dagger|spear|axe|hatchet))\b/i,
     "ranged_combat"},
    {~r/\b(fight\w*|attack\w*|strike|strikes|striking|swing\w*|stab\w*|lunge\w*|slash\w*|thrust\w*|hack\w*|(?<!the )cut(?:s|ting)? (?:at|down)|charg(?:e|es|ing)|club\w*|bash\w*|hit|hits|kill\w*|slay\w*|parr(?:y|ies|ying)|disarm\w*|take (?:down|out))\b/i,
     "melee_combat"}
  ]

  # Skill list v2: the verbs of the new skills. Search, spot and notice move
  # from insight to perception. Cooking a simple meal needs no roll.
  @check_skill_hints_v2 [
                          {~r/\b(search\w*|inspect\w*|examin\w*|spot\w*|notic\w*)\b/i,
                           "perception"},
                          {~r/\b(pickpocket\w*|pick (?:his|her|their|a|the) pocket|palm(?:s|ing)? (?:the|a)|sleight)\b/i,
                           "sleight_of_hand"},
                          {~r/\b(tumbl\w*|somersault\w*|cartwheel\w*|escape (?:my|the) bonds|slip (?:my|the) bonds|acrobat\w*)\b/i,
                           "acrobatics"},
                          {~r/\b(perform\w*|juggl\w*|sing (?:for|a|to)|play (?:a|the) (?:lute|song|tune))\b/i,
                           "performance"},
                          {~r/\b(bandag\w*|first aid|treat (?:the|his|her|my) wound|splint\w*|stitch (?:the|his|her|my) wound)\b/i,
                           "medicine"},
                          {~r/\b(apprais\w*|assess (?:its|the) (?:worth|value)|what (?:is|it's) (?:it )?worth)\b/i,
                           "appraisal"},
                          {~r/\b(forg(?:e|es|ing) (?:a|an|the)|smith(?:ing)?|hammer out)\b/i,
                           "smithing"},
                          {~r/\b(carpentr\w*|carv(?:e|es|ing) (?:a|an|the) (?:plank|beam|board)|build (?:a|an) (?:shelf|table|crate))\b/i,
                           "carpentry"},
                          {~r/\b(tan(?:s|ning)? (?:the|a) hide|leatherwork\w*|stitch (?:a|the) (?:boot|belt|saddle))\b/i,
                           "leatherworking"},
                          {~r/\b(brew(?:s|ing)? (?:a|an|the) (?:potion|tincture|draught)|alchem\w*|distil\w*)\b/i,
                           "alchemy"},
                          {~r/\b(cook(?:s|ing)? (?:a )?(?:feast|banquet))\b/i, "cooking"}
                        ] ++ Enum.reject(@check_skill_hints, &(elem(&1, 1) == "insight"))

  @combat_skills ~w(melee_combat ranged_combat unarmed_combat)

  @doc ~S"""
  The stat linked to each valid skill, e.g. `"stealth" => "DEX"`; unlisted
  skills use WIS. With `JEV_CATALOGUE_V2=on` this is skill list v2 (28
  skills); otherwise the 17 skills of list v1.
  """
  @spec skill_stat_map() :: %{String.t() => String.t()}
  def skill_stat_map,
    do: skill_stat_map(if TalesForge.Config.jev_catalogue_v2?(), do: :v2, else: :v1)

  @doc "The skill list `:v1` (17 skills) or `:v2` (28 skills) with the linked stats."
  @spec skill_stat_map(:v1 | :v2) :: %{String.t() => String.t()}
  def skill_stat_map(:v1), do: @skill_stat
  def skill_stat_map(:v2), do: @skill_stat_v2

  @doc """
  A skill name as the sheet keys it: trimmed, lower case, spaces as
  underscores; nil for empty, "none" or "n/a".

      iex> TalesForge.Game.Mechanics.normalize_skill_name(" Melee Combat ")
      "melee_combat"
      iex> TalesForge.Game.Mechanics.normalize_skill_name("none")
      nil
  """
  @spec normalize_skill_name(term()) :: String.t() | nil
  def normalize_skill_name(nil), do: nil

  def normalize_skill_name(skill) do
    cleaned = skill |> to_string() |> String.trim() |> String.downcase()

    if cleaned in ["none", "n/a", ""] do
      nil
    else
      String.replace(cleaned, " ", "_")
    end
  end

  @doc """
  The skill a player's text clearly calls for, or nil when it needs no check.
  There is no fallback: ordinary talk and everyday actions get no roll.

      iex> TalesForge.Game.Mechanics.infer_check_skill("I try to convince her to lower the price")
      "persuasion"
      iex> TalesForge.Game.Mechanics.infer_check_skill("A tankard of your finest ale, please")
      nil
      iex> TalesForge.Game.Mechanics.infer_check_skill("I ask Brenna what the miners talk about")
      nil
      iex> TalesForge.Game.Mechanics.infer_check_skill("I scale the wall behind the stable")
      "climbing"
      iex> TalesForge.Game.Mechanics.infer_check_skill("Why add silver to the scale?")
      nil
  """
  @spec infer_check_skill(String.t()) :: String.t() | nil
  def infer_check_skill(action) when is_binary(action) do
    hints =
      if TalesForge.Config.jev_catalogue_v2?(),
        do: @check_skill_hints_v2,
        else: @check_skill_hints

    Enum.find_value(hints, fn {pattern, skill} ->
      if Regex.match?(pattern, action), do: skill
    end)
  end

  @doc """
  Combat actions only: the skill of the first fight verb in
  the text (melee, ranged or unarmed), or nil when it names none.

      iex> TalesForge.Game.Mechanics.first_combat_skill("I punch him, then grab the knife and stab")
      "unarmed_combat"
      iex> TalesForge.Game.Mechanics.first_combat_skill("I lunge low at the goblin's spear arm")
      "melee_combat"
      iex> TalesForge.Game.Mechanics.first_combat_skill("I loose another arrow, then draw my knife")
      "ranged_combat"
      iex> TalesForge.Game.Mechanics.first_combat_skill("I order a mug of ale")
      nil
  """
  @spec first_combat_skill(String.t()) :: String.t() | nil
  def first_combat_skill(action) when is_binary(action) do
    @combat_skill_hints
    |> Enum.flat_map(fn {pattern, skill} ->
      case Regex.run(pattern, action, return: :index) do
        [{pos, _} | _] -> [{pos, skill}]
        nil -> []
      end
    end)
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
    |> case do
      {_pos, skill} -> skill
      nil -> nil
    end
  end

  @doc """
  The server's check for a turn: the skill the action or handler names (none
  for move, inventory, wait and train), rolled with `perform_and_apply/4`.
  Returns the updated character and the resolution.
  """
  @spec apply_server_mechanics(map(), PlayerAction.t(), HandlerResult.t()) ::
          {map(), MechanicalResolution.t()}
  def apply_server_mechanics(
        character,
        %PlayerAction{} = player_action,
        %HandlerResult{} = handler
      ) do
    action_skill =
      player_action.action.parameters
      |> Map.get("skill")
      |> normalize_skill_name()

    skill = resolve_check_skill(handler.handler, handler.skill, action_skill)

    if is_nil(skill) do
      {character, no_check_resolution()}
    else
      modifier = (handler.state_hints || %{})["roll_modifier"] || 0
      perform_and_apply(character, skill, modifier: modifier)
    end
  end

  @doc """
  The skill to check: none for the move, inventory, wait and train handlers,
  else the action's skill or the handler's.

      iex> TalesForge.Game.Mechanics.resolve_check_skill("wait", "insight", "stealth")
      nil
      iex> TalesForge.Game.Mechanics.resolve_check_skill("observe", "Insight", nil)
      "insight"
      iex> TalesForge.Game.Mechanics.resolve_check_skill("move", nil, "stealth")
      "stealth"
      iex> TalesForge.Game.Mechanics.resolve_check_skill("move", nil, "insight")
      nil
  """
  @spec resolve_check_skill(String.t() | nil, term(), String.t() | nil) :: String.t() | nil
  # A move rolls only to sneak or to climb (QA 2026-10-14 21:15: "I try to
  # sneak toward the cellar stairs" is a move with a stealth check).
  def resolve_check_skill("move", _handler_skill, action_skill)
      when action_skill in ~w(stealth climbing),
      do: action_skill

  def resolve_check_skill(handler, handler_skill, action_skill) do
    if handler in ["move", "inventory", "wait", "train", "work", "equip", "give"] do
      nil
    else
      action_skill || normalize_skill_name(handler_skill)
    end
  end

  @doc """
  Rolls 1d100 for `skill`, adds the LP it earns and counts a failure. LP are
  only earned here; spending them is `TalesForge.Game.Progression`.

  `opts`: `:roll` injects the roll (1..100, or a list for a re-roll at 100)
  in tests and replays; `:modifier` is the manner adverb's roll modifier
  (Catalogue v2, default 0).
  """
  @spec perform_and_apply(map(), String.t() | nil, keyword()) ::
          {map(), MechanicalResolution.t()}
  def perform_and_apply(character, skill, opts \\ []) do
    normalized = normalize_skill_name(skill) || "insight"
    # Catalogue v2: the manner adverb's roll modifier (PROVISIONAL table).
    effective =
      max(0, effective_skill_level(character, normalized) + Keyword.get(opts, :modifier, 0))

    roll_at(character, %Roll{skill: normalized, effective: effective, injected: opts[:roll]})
  end

  @doc """
  Rolls one part of a skill split, `{skill, level}`, at the part level. The
  rules are the rules of `perform_and_apply/3`. Inject `roll` in tests.
  """
  @spec perform_part(map(), {String.t(), non_neg_integer()}, 1..100 | [1..100] | nil) ::
          {map(), MechanicalResolution.t()}
  def perform_part(character, {skill, level}, roll \\ nil) when is_integer(level) do
    normalized = normalize_skill_name(skill) || "insight"
    roll_at(character, %Roll{skill: normalized, effective: max(0, level), injected: roll})
  end

  @doc """
  The effective level of `skill` for `character`: the raw level plus the
  linked stat bonus, or the untrained floor at level 0.
  """
  @spec effective_level(map(), String.t()) :: non_neg_integer()
  def effective_level(character, skill),
    do: effective_skill_level(character, normalize_skill_name(skill) || "insight")

  @doc "The raw level of `skill` for `character` (0 when untrained)."
  @spec raw_level(map(), String.t()) :: integer()
  def raw_level(character, skill),
    do: character |> get_in(["skills", normalize_skill_name(skill) || "insight"]) |> to_int(0)

  @doc """
  The part levels of a skill split. `level` is the skill level, or
  `{raw, effective}`. The raw level unlocks the split. The parts sum to the
  effective level. `request` is `1`, `2`, `3` or a list of two uneven parts
  (one number gives the first part; the second part is the remainder).

  The thresholds come from `settings` (default
  `TalesForge.Config.skill_split_settings/0`, d100 scale):

    * from `start`, the player can split into two even parts;
    * from `triple`, the player can also split into three even parts, or into
      two uneven parts with each part at least `min_uneven_part`.

  Even parts differ by 1 at most, because the parts always sum to the level.

      iex> TalesForge.Game.Mechanics.split_levels(120, 1)
      {:ok, [120]}
      iex> TalesForge.Game.Mechanics.split_levels(100, 2)
      {:ok, [50, 50]}
      iex> TalesForge.Game.Mechanics.split_levels(101, 2)
      {:ok, [51, 50]}
      iex> TalesForge.Game.Mechanics.split_levels(99, 2)
      {:error, :below_start}
      iex> TalesForge.Game.Mechanics.split_levels(120, 3)
      {:error, :below_triple}
      iex> TalesForge.Game.Mechanics.split_levels(150, 3)
      {:ok, [50, 50, 50]}
      iex> TalesForge.Game.Mechanics.split_levels(150, [95, 55])
      {:ok, [95, 55]}
      iex> TalesForge.Game.Mechanics.split_levels(160, [120])
      {:ok, [120, 40]}
      iex> TalesForge.Game.Mechanics.split_levels(150, [130, 20])
      {:error, :part_below_minimum}
      iex> TalesForge.Game.Mechanics.split_levels(150, [90, 70])
      {:error, :parts_do_not_sum}
      iex> TalesForge.Game.Mechanics.split_levels(140, [90, 50])
      {:error, :below_triple}
      iex> TalesForge.Game.Mechanics.split_levels({100, 104}, 2)
      {:ok, [52, 52]}
  """
  @spec split_levels(integer() | {integer(), integer()}, 1..3 | [integer()], map() | nil) ::
          {:ok, [non_neg_integer()]} | {:error, atom()}
  def split_levels(level, request, settings \\ nil)

  def split_levels(level, request, settings) when is_integer(level),
    do: split_levels({level, level}, request, settings)

  def split_levels({raw, effective}, request, nil),
    do: split_levels({raw, effective}, request, TalesForge.Config.skill_split_settings())

  def split_levels({_raw, effective}, 1, _settings), do: {:ok, [effective]}

  def split_levels({raw, _effective}, _request, %{start: start}) when raw < start,
    do: {:error, :below_start}

  def split_levels({_raw, effective}, 2, _settings), do: {:ok, even_parts(effective, 2)}

  def split_levels({raw, _effective}, request, %{triple: triple})
      when (request == 3 or is_list(request)) and raw < triple,
      do: {:error, :below_triple}

  def split_levels({_raw, effective}, 3, _settings), do: {:ok, even_parts(effective, 3)}

  def split_levels({_raw, effective}, [first], settings) when is_integer(first),
    do: split_levels({effective, effective}, [first, effective - first], settings)

  def split_levels({_raw, effective}, [a, b], %{min_uneven_part: min})
      when is_integer(a) and is_integer(b) do
    cond do
      a + b != effective -> {:error, :parts_do_not_sum}
      min(a, b) < min -> {:error, :part_below_minimum}
      true -> {:ok, [a, b]}
    end
  end

  def split_levels(_level, _request, _settings), do: {:error, :bad_request}

  defp even_parts(level, count) do
    base = div(level, count)
    extra = rem(level, count)
    for i <- 1..count, do: if(i <= extra, do: base + 1, else: base)
  end

  defp roll_at(character, %Roll{skill: normalized, effective: effective, injected: injected}) do
    raw_level = character |> get_in(["skills", normalized]) |> to_int(0)
    {roll, outcome} = roll_outcome(effective, injected)
    {updated, lp} = award(character, normalized, outcome)

    resolution = %MechanicalResolution{
      skill: normalized,
      outcome: outcome,
      roll: roll,
      effective_skill: effective,
      lp_awarded: lp,
      notes:
        "Rolled #{roll} vs #{normalized} #{effective} (#{base_note(raw_level)}). " <>
          lp_note(outcome) <> nat_notes(outcome) <> critical_effect(outcome, normalized)
    }

    {updated, resolution}
  end

  # The LP the outcome earns, and the failure count.
  defp award(character, skill, outcome) do
    lp = growth_lp(outcome)

    learning_points =
      character
      |> Map.get("learning_points", %{})
      |> add_lp(skill, lp)

    updated =
      character
      |> Map.put("learning_points", learning_points)
      |> maybe_count_failure(skill, outcome)

    {updated, lp}
  end

  # At skill 100 or above, a roll of 100 rolls again. A failure on the second
  # roll is a critical failure; any other second outcome stands.
  defp roll_outcome(effective, injected) do
    {roll, rest} = take_roll(injected)
    outcome = resolve_check(roll, effective)

    if outcome == :reroll do
      {second, _rest} = take_roll(rest)
      {roll, reroll_outcome(resolve_check(second, effective))}
    else
      {roll, outcome}
    end
  end

  # A second 100 is a failed second roll.
  defp reroll_outcome(:reroll), do: "critical_failure"
  defp reroll_outcome("failure"), do: "critical_failure"
  defp reroll_outcome("critical_failure"), do: "critical_failure"
  defp reroll_outcome(outcome), do: outcome

  defp take_roll([roll | rest]) when is_integer(roll), do: {roll, rest}
  defp take_roll(roll) when is_integer(roll), do: {roll, nil}
  defp take_roll(_injected), do: {:rand.uniform(100), nil}

  @doc """
  The LP a roll's outcome earns for the skill rolled, one
  banked improvement chance for a failure or a partial success and nothing
  for a success.

      iex> Enum.map(~w(failure partial_success success), &TalesForge.Game.Mechanics.growth_lp/1)
      [1.0, 1.0, 0.0]
  """
  @spec growth_lp(String.t()) :: float()
  def growth_lp("failure"), do: 1.0
  def growth_lp("partial_success"), do: 1.0
  def growth_lp(_outcome), do: 0.0

  # A success earns nothing; the sheet is left as it was.
  defp add_lp(lp_map, _skill, lp) when lp == 0.0, do: lp_map

  defp add_lp(lp_map, skill, lp),
    do: Map.update(lp_map, skill, lp, fn current -> Float.round(to_float(current) + lp, 1) end)

  defp lp_note(outcome) when outcome in ["failure", "partial_success"],
    do: "+1 banked improvement chance (resolved on sleep)."

  defp lp_note("critical_failure"), do: "Critical failure: nothing to learn."
  defp lp_note(_outcome), do: "Success: nothing to learn."

  @doc """
  Wound cap from CON. Minimum 1 (CON 3). A minor foe has 1.
  """
  @spec wound_max(GameCharacter.t() | map()) :: pos_integer()
  def wound_max(%GameCharacter{minor: true}), do: 1
  def wound_max(%GameCharacter{stats: stats}), do: wound_max(%{"stats" => stats})

  def wound_max(character) when is_map(character) do
    con = character |> get_in(["stats", "CON"]) |> to_int(10)
    max(1, 3 + div(con - 10, 2))
  end

  @doc """
  One wound on any character, player or NPC (refactor step 10c): below
  the cap it adds a wound (`"hurt"`, or `"down"` at the cap); at the cap it
  makes the death roll of `combat.md`, a d100 (`death_roll`, else random)
  greater than CON × 2.5 kills. A dead character stays as it is. Wounds
  below 0 count as 0.
  """
  @spec wound(GameCharacter.t(), 1..100 | nil) :: GameCharacter.t()
  def wound(%GameCharacter{vitality: "dead"} = character, _death_roll), do: character

  def wound(%GameCharacter{} = character, death_roll) do
    cap = wound_max(character)
    wounds = character.wounds |> to_int(0) |> max(0)

    if wounds >= cap do
      vitality = if fatal_death_roll?(character, death_roll), do: "dead", else: "down"
      GameCharacter.put(character, wounds: cap, wound_max: cap, vitality: vitality)
    else
      vitality = if wounds + 1 >= cap, do: "down", else: "hurt"
      GameCharacter.put(character, wounds: wounds + 1, wound_max: cap, vitality: vitality)
    end
  end

  @doc ~S(The character's vitality: "ok", "hurt", "down" when wounds reach the cap, or "dead".)
  @spec vitality(map()) :: String.t()
  def vitality(character) when is_map(character) do
    cond do
      Map.get(character, "vitality") == "dead" -> "dead"
      to_int(Map.get(character, "wounds", 0), 0) >= wound_max(character) -> "down"
      to_int(Map.get(character, "wounds", 0), 0) > 0 -> "hurt"
      true -> "ok"
    end
  end

  @doc "True when the character (or the world_state's character) is dead."
  @spec dead?(term()) :: boolean()
  def dead?(world_or_character) when is_map(world_or_character) do
    Map.get(world_or_character, "vitality") == "dead" or
      get_in(world_or_character, ["character", "vitality"]) == "dead"
  end

  def dead?(_), do: false

  @doc """
  Apply at most one wound or one death roll after the perception snapshot.
  Inject `opts[:death_roll]` (1..100) in tests.

  With `opts[:opposed]` true (`COMBAT_OPPOSED=on`), the exchange in
  `opts[:combat]` (`TalesForge.Game.Combat.exchange/3`) replaces the failed
  combat roll: the character takes a wound only from a counterattack hit.
  """
  @spec apply_vitality(map(), MechanicalResolution.t() | nil, keyword()) :: map()
  def apply_vitality(world, mechanical, opts \\ []) when is_map(world) do
    character = world |> Map.get("character", %{}) |> GameCharacter.from_sheet()
    facts = Map.get(world, "public_facts", [])
    hits = harm_count(mechanical, facts, opts)
    harm = %Harm{mechanical: mechanical, death_roll: opts[:death_roll]}
    vital = apply_character_vitality(character, harm, hits)
    put_in(world, ["character"], GameCharacter.to_sheet(vital))
  end

  @doc """
  The vitality step for any character: `hits` wounds (`wound/2`; the turn's
  LP go on a fatal death roll), or, without a hit, the wound cap and
  vitality stamped from the wounds.
  """
  @spec apply_character_vitality(GameCharacter.t(), Harm.t(), non_neg_integer()) ::
          GameCharacter.t()
  def apply_character_vitality(%GameCharacter{} = character, %Harm{} = harm, hits) do
    character = GameCharacter.put(character, wound_max: wound_max(character))

    cond do
      character.vitality == "dead" ->
        GameCharacter.put(character, vitality: "dead")

      hits > 0 ->
        Enum.reduce(1..hits, character, fn _hit, acc -> harm_once(acc, harm) end)

      true ->
        stamp_vitality(character)
    end
  end

  # The wounds of the turn: the opposed exchange gives its count, the flat
  # roll one wound on a failed combat roll, and a wound fact at least one.
  defp harm_count(mechanical, facts, opts) do
    hits =
      cond do
        opts[:opposed] -> opposed_hits(opts[:combat])
        combat_failure?(mechanical) -> 1
        true -> 0
      end

    if hits == 0 and wound_fact?(facts), do: 1, else: hits
  end

  defp harm_once(%GameCharacter{vitality: "dead"} = character, _harm), do: character

  defp harm_once(%GameCharacter{} = character, %Harm{} = harm) do
    case wound(character, harm.death_roll) do
      %GameCharacter{vitality: "dead"} = dead -> strip_turn_lp(dead, harm.mechanical)
      wounded -> wounded
    end
  end

  defp fatal_death_roll?(%GameCharacter{stats: stats}, death_roll) do
    con = %{"stats" => stats} |> get_in(["stats", "CON"]) |> to_int(10)
    roll = death_roll || :rand.uniform(100)
    roll > con * 2.5
  end

  defp strip_turn_lp(%GameCharacter{} = character, %MechanicalResolution{
         skill: skill,
         lp_awarded: lp
       })
       when is_binary(skill) and is_number(lp) and lp > 0 do
    lp_map = character.learning_points
    remaining = Float.round(max(to_float(Map.get(lp_map, skill, 0)) - lp, 0.0), 1)
    GameCharacter.put(character, learning_points: Map.put(lp_map, skill, remaining))
  end

  defp strip_turn_lp(character, _), do: character

  # Opposed combat: a counterattack hit and a critical miss (the attacker's
  # own wound) each give one wound.
  defp opposed_hits(%{"attacker_wounds" => n}) when is_integer(n) and n > 0, do: n
  defp opposed_hits(%{"attacker_wounded" => true}), do: 1
  defp opposed_hits(_combat), do: 0

  defp combat_failure?(%MechanicalResolution{outcome: outcome, skill: skill})
       when outcome in ["failure", "critical_failure"] and skill in @combat_skills,
       do: true

  defp combat_failure?(_), do: false

  defp wound_fact?(facts) do
    facts
    |> List.wrap()
    |> Enum.any?(fn
      %{"harm" => "wound"} -> true
      _ -> false
    end)
  end

  defp stamp_vitality(%GameCharacter{} = character) do
    cap = wound_max(character)
    wounds = character.wounds |> to_int(0) |> max(0) |> min(cap)
    vitality = vitality(%{"stats" => character.stats, "wounds" => wounds})
    GameCharacter.put(character, wounds: wounds, wound_max: cap, vitality: vitality)
  end

  defp no_check_resolution do
    %MechanicalResolution{outcome: "none", notes: "No skill check required."}
  end

  defp maybe_count_failure(character, skill, outcome) do
    if outcome in ["failure", "critical_failure"] do
      failures =
        character
        |> Map.get("learning_failures", %{})
        |> Map.update(skill, 1, fn current -> to_int(current, 0) + 1 end)

      Map.put(character, "learning_failures", failures)
    else
      character
    end
  end

  # A trained skill: level plus the linked stat's bonus (5 × ((stat - 10) div 2)).
  # An untrained one (level 0) uses the untrained floor 5 × max(stat div 3, bonus):
  # anyone can try with raw talent (old rules, 2026-10-07).
  defp effective_skill_level(character, skill) do
    base = character |> get_in(["skills", skill]) |> to_int(0)
    stat_key = Map.get(@skill_stat_v2, skill, "WIS")
    stat_value = character |> get_in(["stats", stat_key]) |> to_int(10)

    if base <= 0,
      do: untrained_floor(stat_value),
      else: max(0, base + stat_bonus(stat_value))
  end

  @doc """
  The untrained roll level for a stat on the d100 scale:
  `5 × max(stat div 3, (stat - 10) div 2)`. A skill at level 0 rolls against
  it; a trained skill uses its level plus the stat bonus, so every level counts.

      iex> TalesForge.Game.Mechanics.untrained_floor(12)
      20
      iex> TalesForge.Game.Mechanics.untrained_floor(18)
      30
  """
  @spec untrained_floor(integer()) :: non_neg_integer()
  def untrained_floor(stat) when is_integer(stat),
    do: 5 * max(0, max(div(stat, 3), div(stat - 10, 2)))

  @doc """
  The stat bonus added to a trained skill on the d100 scale:
  `5 × ((stat - 10) div 2)`.

      iex> Enum.map([8, 10, 12, 16], &TalesForge.Game.Mechanics.stat_bonus/1)
      [-5, 0, 5, 15]
  """
  @spec stat_bonus(integer()) :: integer()
  def stat_bonus(stat) when is_integer(stat), do: 5 * div(stat - 10, 2)

  @doc """
  The outcome of one d100 roll against the effective skill, in this order:
  critical success, success, critical failure, near miss, failure.

  - Critical success: rolls `1..ceil(skill / 10)`. Not possible at skill 10 or
    below.
  - Success: a roll at most the skill.
  - Critical failure: the top `floor((100 - skill) / 10)` rolls. A roll of 100
    is always in the band. At skill 100 or above, a roll of 100 is not decided
    here: the caller rolls again (`:reroll`).
  - Near miss: a roll 1 to 15 above the skill.

      iex> Enum.map([1, 3, 4, 25, 26, 40, 41, 93, 94], &TalesForge.Game.Mechanics.resolve_check(&1, 25))
      ["critical_success", "critical_success", "success", "success", "partial_success",
       "partial_success", "failure", "failure", "critical_failure"]
      iex> TalesForge.Game.Mechanics.resolve_check(1, 10)
      "success"
      iex> TalesForge.Game.Mechanics.resolve_check(100, 100)
      :reroll
  """
  @spec resolve_check(1..100, integer()) :: String.t() | :reroll
  def resolve_check(roll, skill) when roll in 1..100 and is_integer(skill) do
    skill = max(skill, 0)

    cond do
      roll == 100 and skill >= 100 -> :reroll
      roll <= critical_success_max(skill) -> "critical_success"
      roll <= skill -> "success"
      roll > critical_failure_floor(skill) -> "critical_failure"
      roll <= skill + 15 -> "partial_success"
      true -> "failure"
    end
  end

  @doc """
  The highest roll that is a critical success at `skill`: `ceil(skill / 10)`,
  and 0 when skill is 10 or below (critical success is not possible).

      iex> Enum.map([5, 10, 11, 25, 95], &TalesForge.Game.Mechanics.critical_success_max/1)
      [0, 0, 2, 3, 10]
  """
  @spec critical_success_max(integer()) :: non_neg_integer()
  def critical_success_max(skill) when is_integer(skill) and skill <= 10, do: 0
  def critical_success_max(skill) when is_integer(skill), do: div(skill + 9, 10)

  @doc """
  The roll a critical failure must be above: `100 - floor((100 - skill) / 10)`,
  so the band is the top `floor((100 - skill) / 10)` rolls and a roll of 100
  is always in it. At skill 100 or above the band is empty (a roll of 100 is a
  reroll instead).

      iex> Enum.map([5, 50, 90, 95, 100], &TalesForge.Game.Mechanics.critical_failure_floor/1)
      [91, 95, 99, 99, 100]
  """
  @spec critical_failure_floor(integer()) :: non_neg_integer()
  def critical_failure_floor(skill) when is_integer(skill) and skill >= 100, do: 100

  def critical_failure_floor(skill) when is_integer(skill),
    do: min(99, 100 - div(100 - max(skill, 0), 10))

  defp base_note(raw) when raw <= 0, do: "untrained: stat ÷ 3"
  defp base_note(raw), do: "base #{raw}"

  defp nat_notes("critical_success"), do: " Critical success."
  defp nat_notes("critical_failure"), do: " Critical failure."
  defp nat_notes(_), do: ""

  @doc """
  The effect of a critical result for `skill`, as a note for the GM (locked
  answer 8 of the d100 switch). Empty for other outcomes.

      iex> TalesForge.Game.Mechanics.critical_effect("critical_success", "lockpicking")
      " The lock opens in half the time and without a sound."
      iex> TalesForge.Game.Mechanics.critical_effect("success", "lockpicking")
      ""
  """
  @spec critical_effect(String.t(), String.t() | nil) :: String.t()
  def critical_effect("critical_success", skill) when skill in @combat_skills,
    do: " The blow lands with full damage and every bonus."

  def critical_effect("critical_success", skill)
      when skill in ~w(athletics acrobatics climbing running),
      do: " About 50% faster than normal."

  def critical_effect("critical_success", "lockpicking"),
    do: " The lock opens in half the time and without a sound."

  def critical_effect("critical_success", "persuasion"),
    do: " The other side agrees to more than expected."

  def critical_effect("critical_failure", skill) when skill in @combat_skills,
    do: " The attack goes wrong: the attacker takes normal weapon damage."

  def critical_effect(_outcome, _skill), do: ""

  defp to_int(value, _default) when is_integer(value), do: value
  defp to_int(value, _default) when is_float(value), do: trunc(value)

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp to_int(_, default), do: default

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0
end
