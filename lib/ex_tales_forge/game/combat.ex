defmodule TalesForge.Game.Combat do
  @moduledoc """
  Opposed combat rolls (`priv/rules/combat.md`, `COMBAT_OPPOSED=on`). Pure:
  no Repo, no LLM, no random numbers. The caller injects every roll.

  One exchange has two steps:

    1. The attack. The attacker rolls a d100 for the combat skill against the
       defender's Parry (`parry/1`). The roll hits when it is equal to or
       less than `attack_target/2` and is not in the critical failure band.
       A roll of 1 always hits. A hit gives the defender one wound.
    2. The counterattack. A defender that is still up fights back when the
       chance roll is less than `counter_chance/1`. It rolls its own combat
       skill against the attacker's Parry. A hit gives the attacker one wound.

  A miss is only a miss. The attacker takes a wound only from a counterattack
  hit. A fighter is a string-keyed map with `stats`, `skills` and,
  for an NPC, `ocean`, `maslow`, `concerns`, `wounds` and `wound_max`.

  NPC wounds live in `world_state["npc_state"][id]` (`book/4`). An NPC at the
  wound cap is down. A hit on an NPC that is down makes the death roll of
  `combat.md`: a d100 greater than CON × 2.5 kills it. The death stays in the
  session. A minor foe (`minor_foe/4`) has 1 wound and the untrained floor.
  """

  defmodule Hit do
    @moduledoc """
    One attack on the defender, as `TalesForge.Game.Combat.exchange/4` books
    it: whether it hit, the defender's wounds, wound cap and vitality before
    it, the defender and the death roll (d100).
    """

    @enforce_keys [:hit, :wounds, :cap, :vitality, :defender, :roll]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            hit: boolean(),
            wounds: non_neg_integer(),
            cap: pos_integer(),
            vitality: String.t(),
            defender: map(),
            roll: integer()
          }
  end

  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.Mechanics

  @combat_skills ~w(melee_combat ranged_combat unarmed_combat)

  # Words that name a person. An attack on one of these words, with no
  # person in the world data, makes a minor foe for the scene.
  @person_words ~w(miner miners guard guards man woman thug bandit goblin orc stranger soldier
                   merchant boy girl drunk worker sentry brute scout villager farmer smith hunter
                   thief robber cutpurse ruffian sailor laborer labourer porter clerk watchman
                   tinjack mercenary blade bowman spearman archer)
  @attack_verbs ~w(attack attacks hit strike stab punch slash kick shoot charge tackle lunge
                   swing cut)

  @type fighter :: map()
  @type rolls :: %{
          required(:attack) => 1..100,
          optional(:counter_chance) => float(),
          optional(:counter) => 1..100,
          optional(:death) => 1..100,
          optional(:qa_forced) => boolean()
        }
  @type target ::
          {:npc, String.t()} | {:foe, String.t(), String.t()} | {:unclear, [String.t()]}

  @doc "The combat skills."
  @spec combat_skills() :: [String.t()]
  def combat_skills, do: @combat_skills

  @doc """
  Parry from `combat.md`: Dodge/2 + 50 + 5 × ((DEX - 10)/2), rounded down. Dodge is
  the effective dodge level (`Mechanics.effective_level/2`), so an untrained
  fighter uses the untrained floor.

      iex> TalesForge.Game.Combat.parry(%{"stats" => %{"DEX" => 10}, "skills" => %{"dodge" => 20}})
      60
  """
  @spec parry(fighter()) :: integer()
  def parry(fighter) do
    dodge = Mechanics.effective_level(fighter, "dodge")
    dex = fighter |> get_in(["stats", "DEX"]) |> to_int(10)
    div(dodge, 2) + 50 + 5 * Integer.floor_div(dex - 10, 2)
  end

  @doc """
  The highest roll that hits: the skill level less the Parry above 50, at
  least 1. Parry 50 gives the skill level.

      iex> TalesForge.Game.Combat.attack_target(40, 60)
      30
      iex> TalesForge.Game.Combat.attack_target(10, 70)
      1
  """
  @spec attack_target(integer(), integer()) :: pos_integer()
  def attack_target(level, parry), do: max(1, level - (parry - 50))

  @doc """
  True when the d100 `roll` hits `target`: a success or a critical success
  from `Mechanics.resolve_check/2`. A roll of 1 always hits; a roll in the
  critical failure band always misses.
  """
  @spec hit?(1..100, pos_integer()) :: boolean()
  def hit?(1, _target), do: true

  def hit?(roll, target),
    do: Mechanics.resolve_check(roll, target) in ~w(success critical_success)

  @doc """
  The d100 band of an attack roll against `target` (QA 2026-10-14 21:15):
  `critical_success`, `success`, `partial_success` (a near miss: a miss that
  was 1 to 15 above the target), `failure` or `critical_failure`. The band
  agrees with `hit?/2`: the first two hit, the others miss.

      iex> Enum.map([1, 3, 30, 31, 45, 46, 100], &TalesForge.Game.Combat.result(&1, 30))
      ["critical_success", "critical_success", "success", "partial_success", "partial_success", "failure", "critical_failure"]
      iex> TalesForge.Game.Combat.result(1, 8)
      "success"
  """
  @spec result(1..100, pos_integer()) :: String.t()
  def result(roll, target) do
    case Mechanics.resolve_check(roll, target) do
      :reroll -> "failure"
      band -> band
    end
  end

  @doc """
  The word for an attack band, as the player reads it.

      iex> Enum.map(~w(critical_success success partial_success failure critical_failure), &TalesForge.Game.Combat.result_word/1)
      ["critical hit", "hit", "miss (near miss)", "miss", "critical miss"]
  """
  @spec result_word(String.t() | nil) :: String.t()
  def result_word("critical_success"), do: "critical hit"
  def result_word("success"), do: "hit"
  def result_word("partial_success"), do: "miss (near miss)"
  def result_word("critical_failure"), do: "critical miss"
  def result_word(_), do: "miss"

  @doc """
  The combat skill of `fighter` and its effective level: `preferred` when it
  is a combat skill, otherwise the combat skill with the highest level.
  """
  @spec combat_skill(fighter(), String.t() | nil) :: {String.t(), non_neg_integer()}
  def combat_skill(fighter, preferred \\ nil)

  def combat_skill(fighter, preferred) when preferred in @combat_skills,
    do: {preferred, level(fighter, preferred)}

  def combat_skill(fighter, _preferred) do
    @combat_skills
    |> Enum.map(&{&1, level(fighter, &1)})
    |> Enum.max_by(fn {_skill, lvl} -> lvl end)
  end

  defp level(%{"minor" => true} = fighter, skill),
    do: Mechanics.effective_level(Map.put(fighter, "skills", %{}), skill)

  defp level(fighter, skill), do: Mechanics.effective_level(fighter, skill)

  @doc """
  The chance (0.05 to 0.95) that `npc` fights back when it is attacked. The
  chance grows with the combat skill, low agreeableness, high extraversion,
  the esteem need and a duty, order, revenge or fame concern. It falls with
  high neuroticism, the physiological or safety need, a safety, family,
  survival or escape concern, and each wound.

  A guard fights back most of the time. A scared shopkeeper often does not.
  """
  @spec counter_chance(fighter()) :: float()
  def counter_chance(npc) do
    {_skill, lvl} = combat_skill(npc)
    ocean = Map.get(npc, "ocean") || %{}
    trait = fn name -> ocean |> Map.get(name, 5) |> to_int(5) end

    chance =
      0.5 +
        0.006 * (min(lvl, 70) - 20) +
        0.04 * (5 - trait.("agreeableness")) +
        0.02 * (trait.("extraversion") - 5) -
        0.05 * (trait.("neuroticism") - 5) +
        maslow_shift(Map.get(npc, "maslow")) +
        concern_shift(npc) -
        0.1 * (npc |> Map.get("wounds", 0) |> to_int(0))

    chance |> max(0.05) |> min(0.95) |> Float.round(2)
  end

  defp maslow_shift("physiological"), do: -0.15
  defp maslow_shift("safety"), do: -0.05
  defp maslow_shift("esteem"), do: 0.1
  defp maslow_shift(_), do: 0.0

  @bold_focuses ~w(duty order revenge fame)
  @timid_focuses ["safety", "family", "survival", "escape the past"]

  defp concern_shift(npc) do
    focuses =
      [Map.get(npc, "current_concern") | List.wrap(Map.get(npc, "concerns"))]
      |> Enum.flat_map(fn
        %{"focus" => focus} when is_binary(focus) -> [focus]
        _ -> []
      end)

    bold = if Enum.any?(focuses, &(&1 in @bold_focuses)), do: 0.15, else: 0.0
    timid = if Enum.any?(focuses, &(&1 in @timid_focuses)), do: 0.15, else: 0.0
    bold - timid
  end

  @doc """
  One exchange: `attacker` attacks `defender` with `skill`, and the
  defender may counterattack. `rolls.attack` is the attacker's d100,
  `rolls.counter_chance` (0 to 1) decides the counterattack, `rolls.counter`
  is the defender's d100 and `rolls.death` the defender's death roll.

  Returns a string-keyed map: `attacker`, `defender`, `attack`, `counter`
  (nil without a counterattack), `defender_wounds`, `defender_wound_max`,
  `defender_vitality` (`ok`, `hurt`, `down` or `dead`), `self_wound` and
  `attacker_wounded`.

  A critical miss wounds the attacker (`combat.md`: the attack goes wrong and
  the attacker takes normal weapon damage), so `self_wound` and
  `attacker_wounded` are true (QA 2026-10-15 retest: the prose told the
  wound and the sheet stayed at 0/3).
  """
  @spec exchange(fighter(), fighter(), String.t() | nil, rolls()) :: map()
  def exchange(attacker, defender, skill, rolls) do
    {attack_skill, attack_level} = combat_skill(attacker, skill)
    defender_parry = parry(defender)
    target = attack_target(attack_level, defender_parry)
    hit = hit?(rolls.attack, target)
    result = result(rolls.attack, target)

    %Hit{cap: cap} = on_defender = hit_on(defender, hit, rolls)
    {wounds, vitality} = take_hit(on_defender)
    death = death_roll(on_defender)

    counter =
      if vitality in ~w(ok hurt) do
        counterattack(attacker, Map.put(defender, "wounds", wounds), rolls)
      end

    self_wound = result == "critical_failure"
    attacker_wounds = Enum.count([self_wound, counter_hit?(counter)], & &1)

    %{
      "attacker" => name(attacker),
      "attacker_id" => Map.get(attacker, "id", "player"),
      "defender" => name(defender),
      "defender_id" => Map.get(defender, "id"),
      "minor" => Map.get(defender, "minor", false),
      "attack" => %{
        "skill" => attack_skill,
        "level" => attack_level,
        "parry" => defender_parry,
        "target" => target,
        "roll" => rolls.attack,
        "hit" => hit,
        "result" => result,
        "untrained" => untrained?(attacker, attack_skill)
      },
      "death" => death,
      "qa_forced" => Map.get(rolls, :qa_forced, false),
      "counter" => counter,
      "defender_wounds" => wounds,
      "defender_wound_max" => cap,
      "defender_vitality" => vitality,
      "self_wound" => self_wound,
      "attacker_wounds" => attacker_wounds,
      "attacker_wounded" => attacker_wounds > 0
    }
  end

  # The attack on `defender`, with its wounds, wound cap and vitality before it.
  defp hit_on(defender, hit, rolls) do
    cap = wound_max(defender)
    before = defender |> Map.get("wounds", 0) |> to_int(0) |> min(cap)

    %Hit{
      hit: hit,
      wounds: before,
      cap: cap,
      vitality: Map.get(defender, "vitality") || vitality(before, cap),
      defender: defender,
      roll: Map.get(rolls, :death, 1)
    }
  end

  # QA 2026-10-15: the death roll of a hit on a downed defender, so the line
  # can show it. The defender dies when the d100 is above CON × 2.5
  # (`combat.md`), so `"kills_above"` is that number, rounded down.
  defp death_roll(%Hit{hit: true, wounds: wounds, cap: cap, vitality: vitality, roll: roll} = hit)
       when wounds >= cap and vitality != "dead" do
    con = con(hit)
    %{"roll" => roll, "kills_above" => trunc(con * 2.5), "dead" => roll > con * 2.5}
  end

  defp death_roll(%Hit{}), do: nil

  # A fighter with level 0 in the skill rolls the untrained floor
  # (`Mechanics.untrained_floor/1`). A minor foe is always untrained.
  defp untrained?(%{"minor" => true}, _skill), do: true
  defp untrained?(fighter, skill), do: Mechanics.raw_level(fighter, skill) <= 0

  defp take_hit(%Hit{hit: false, wounds: wounds, vitality: vitality}), do: {wounds, vitality}
  defp take_hit(%Hit{wounds: wounds, vitality: "dead"}), do: {wounds, "dead"}

  defp take_hit(%Hit{wounds: wounds, cap: cap} = hit) when wounds >= cap do
    if hit.roll > con(hit) * 2.5, do: {cap, "dead"}, else: {cap, "down"}
  end

  defp take_hit(%Hit{wounds: wounds, cap: cap}) do
    after_hit = wounds + 1
    {after_hit, vitality(after_hit, cap)}
  end

  defp con(%Hit{defender: defender}), do: defender |> get_in(["stats", "CON"]) |> to_int(10)

  defp self_wound_line(%{"self_wound" => true} = ex),
    do: "- #{ex["attacker"]} takes 1 wound from the critical miss. The server books it."

  defp self_wound_line(_ex), do: nil

  defp counter_hit?(%{"hit" => true}), do: true
  defp counter_hit?(_counter), do: false

  defp counterattack(attacker, defender, rolls) do
    chance = counter_chance(defender)
    chance_roll = Map.get(rolls, :counter_chance, 1.0)

    if chance_roll < chance do
      {skill, lvl} = combat_skill(defender)
      attacker_parry = parry(attacker)
      target = attack_target(lvl, attacker_parry)
      roll = Map.fetch!(rolls, :counter)

      %{
        "chance" => chance,
        "chance_roll" => chance_roll,
        "skill" => skill,
        "level" => lvl,
        "parry" => attacker_parry,
        "target" => target,
        "roll" => roll,
        "hit" => hit?(roll, target),
        "result" => result(roll, target),
        "untrained" => untrained?(defender, skill)
      }
    end
  end

  @doc "The wound cap of a fighter: 1 for a minor foe, otherwise `Mechanics.wound_max/1`."
  @spec wound_max(fighter()) :: pos_integer()
  def wound_max(%{"minor" => true}), do: 1
  def wound_max(fighter), do: Mechanics.wound_max(fighter)

  defp vitality(wounds, cap) when wounds >= cap, do: "down"
  defp vitality(wounds, _cap) when wounds > 0, do: "hurt"
  defp vitality(_wounds, _cap), do: "ok"

  @doc """
  The target of an attack. `action_target` is the Jev target (a world id or
  a name). The target must be a person in the scene (`present_npcs`):

    * a present NPC by a name word in `text` gives `{:npc, id}`;
    * the Jev target (id or name) gives `{:npc, id}` only when `text` refers
      to a person: a pronoun or a word of that id or name. A bare "I attack"
      asks whom;
    * a person word ("the miner") with no present NPC gives
      `{:foe, id, name}`: the server makes a minor foe for the scene;
    * anything else gives `{:unclear, names}` with the names of the present
      people, and the turn asks the player.

      iex> world = %{"present_npcs" => ["guild_steward"],
      ...>   "npc_state" => %{"guild_steward" => %{"name" => "Osric Vane"}}}
      iex> TalesForge.Game.Combat.target(nil, "I attack Osric the liar", world) == {:npc, "guild_steward"}
      true
      iex> TalesForge.Game.Combat.target(nil, "I do attack the miner", world) == {:foe, "foe_miner", "a miner"}
      true
      iex> TalesForge.Game.Combat.target(nil, "I lash out", world) == {:unclear, ["Osric Vane"]}
      true
      iex> TalesForge.Game.Combat.target("guild_steward", "I attack", world) == {:unclear, ["Osric Vane"]}
      true
      iex> TalesForge.Game.Combat.target("guild_steward", "I attack him", world) == {:npc, "guild_steward"}
      true
  """
  @spec target(String.t() | nil, String.t() | nil, map()) :: target()
  def target(action_target, text, world) do
    present = present_people(world)
    text = String.downcase(text || "")

    cond do
      id = by_text(present, text) -> {:npc, id}
      id = named_jev_target(present, action_target, text) -> {:npc, id}
      noun = person_word(action_target, text) -> foe_target(noun, world)
      true -> {:unclear, Enum.map(present, &elem(&1, 1))}
    end
  end

  # QA 2026-10-14 08:57 (f): Jev fills the only present person as the target
  # of a bare "I attack". The Jev target counts only when the text refers to
  # a person: a pronoun or a word of the target id or name.
  @pronouns ~w(him her them it he she they)

  defp named_jev_target(present, action_target, text) do
    with id when is_binary(id) <- by_id_or_name(present, action_target),
         true <- refers_to_person?(text, id, action_target) do
      id
    else
      _ -> nil
    end
  end

  defp refers_to_person?(text, id, action_target) do
    words = String.split(text, ~r/[^a-z']+/, trim: true)

    target_words =
      String.split(String.downcase("#{id} #{action_target}"), ~r/[^a-z']+/, trim: true)
      |> Enum.reject(&(String.length(&1) < 3 or &1 in ~w(the and foe)))

    Enum.any?(words, fn word ->
      word in @pronouns or Enum.any?(target_words, &String.starts_with?(word, &1))
    end)
  end

  defp present_people(world) do
    state = Map.get(world, "npc_state") || %{}

    present =
      world
      |> Map.get("present_npcs", [])
      |> List.wrap()
      |> Enum.reject(&dead?(state, &1))
      |> Enum.map(fn id -> {id, get_in(state, [id, "name"]) || id} end)

    foes =
      state
      |> Enum.filter(fn {id, npc} ->
        npc["minor"] == true and npc["location_id"] == world["location_id"] and
          not dead?(state, id)
      end)
      |> Enum.map(fn {id, npc} -> {id, npc["name"] || id} end)

    Enum.sort(present) ++ Enum.sort(foes)
  end

  defp dead?(state, id), do: get_in(state, [id, "vitality"]) == "dead"

  defp by_id_or_name(_present, target) when target in [nil, ""], do: nil

  defp by_id_or_name(present, target) do
    wanted = String.downcase(target)

    Enum.find_value(present, fn {id, name} ->
      if id == target or String.downcase(name) == wanted, do: id
    end)
  end

  defp by_text(present, text) do
    words = MapSet.new(Regex.scan(~r/[a-z']+/, text) |> List.flatten())

    matches =
      Enum.filter(present, fn {id, name} ->
        name_words =
          (String.split(String.downcase(name), ~r/[^a-z']+/, trim: true) ++
             [String.replace(id, "foe_", "")])
          |> Enum.reject(&(String.length(&1) < 3 or &1 in ~w(the and)))

        Enum.any?(name_words, &MapSet.member?(words, &1))
      end)

    case matches do
      [{id, _name}] -> id
      _ -> nil
    end
  end

  defp person_word(action_target, text) do
    candidates =
      String.split(String.downcase(action_target || ""), ~r/[^a-z]+/, trim: true) ++
        after_attack_verb(text)

    Enum.find_value(candidates, fn word ->
      if word in @person_words, do: singular(word)
    end)
  end

  defp after_attack_verb(text) do
    words = String.split(text, ~r/[^a-z]+/, trim: true)

    case Enum.drop_while(words, &(&1 not in @attack_verbs)) do
      [] ->
        []

      [_verb | rest] ->
        rest |> Enum.reject(&(&1 in ~w(the a an at that this one other))) |> Enum.take(3)
    end
  end

  defp singular(word) do
    if String.ends_with?(word, "s") and String.trim_trailing(word, "s") in @person_words,
      do: String.trim_trailing(word, "s"),
      else: word
  end

  defp foe_target(noun, _world), do: {:foe, "foe_" <> noun, "a " <> noun}

  @doc """
  A minor foe for the scene: stats from `Defaults.derive/3` (the occupation
  of the person word, or laborer), no skills (the untrained floor) and 1 wound.
  """
  @spec minor_foe(String.t(), String.t(), Defaults.rules(), integer()) :: fighter()
  def minor_foe(id, name, rules, seed) do
    noun = String.replace_prefix(id, "foe_", "")
    occupation = if Map.has_key?(rules["occupations"] || %{}, noun), do: noun, else: "laborer"

    derived =
      Defaults.derive(%{"occupation" => occupation, "seniority" => "apprentice"}, rules, seed)

    derived
    |> Map.take(~w(stats ocean maslow concerns))
    |> Map.merge(%{
      "id" => id,
      "name" => name,
      "role" => "minor foe",
      "skills" => %{},
      "minor" => true,
      "wounds" => 0,
      "wound_max" => 1
    })
  end

  @doc """
  Writes the defender's wounds of `exchange` to `world["npc_state"]`. A
  minor foe also gets its scene entry (`foe` is its fighter map). Returns
  `{world, events}`; the events are `npc.down` or `npc.dead` when the
  defender went down or died in this exchange.
  """
  @spec book(map(), map() | nil, fighter() | nil, map()) :: {map(), [map()]}
  def book(world, nil, _foe, _before), do: {world, []}

  def book(world, exchange, foe, before) do
    id = exchange["defender_id"]
    state = Map.get(world, "npc_state") || %{}
    base = Map.get(state, id) || foe_entry(foe, world)

    entry =
      Map.merge(base, %{
        "wounds" => exchange["defender_wounds"],
        "wound_max" => exchange["defender_wound_max"],
        "vitality" => exchange["defender_vitality"]
      })

    world = Map.put(world, "npc_state", Map.put(state, id, entry))
    vitality_before = get_in(before || %{}, [id, "vitality"]) || "ok"
    {world, events(exchange, vitality_before, world)}
  end

  defp foe_entry(nil, _world), do: %{}

  defp foe_entry(foe, world) do
    foe
    |> Map.take(~w(id name role minor stats ocean maslow concerns))
    |> Map.put("location_id", world["location_id"])
  end

  defp events(%{"defender_vitality" => same}, same, _world), do: []

  defp events(%{"defender_vitality" => vitality} = exchange, _before, world)
       when vitality in ~w(down dead) do
    [
      %{
        "kind" => "npc." <> vitality,
        "actor" => "player",
        "player_aware" => true,
        "tick" => world["world_tick"] || 0,
        "location_id" => world["location_id"],
        "payload" => %{
          "npc_id" => exchange["defender_id"],
          "name" => exchange["defender"],
          "minor" => exchange["minor"],
          "session_only" => true
        }
      }
    ]
  end

  defp events(_exchange, _before, _world), do: []

  @doc """
  The GM prompt section for `exchange`: who attacked whom, both rolls, both
  results and the wounds. Returns nil without an exchange.
  """
  @spec prompt_section(map() | nil) :: String.t() | nil
  def prompt_section(nil), do: nil

  def prompt_section(%{"target_unclear" => names}) do
    """
    ## Combat target
    The server cannot name the target of the attack. No die was rolled. Ask the player whom the character attacks. The people here: #{Enum.join(names, ", ")}.
    """
  end

  def prompt_section(%{"attack" => attack} = ex) do
    lines =
      [
        "- #{ex["attacker"]} attacks #{ex["defender"]} (#{level_text(attack)}, #{ex["defender"]}'s Parry #{attack["parry"]}): d100 #{attack["roll"]} against #{attack["target"]}. #{sentence(band_word(attack))}.#{critical_note(attack)}",
        self_wound_line(ex),
        death_line(ex),
        defender_line(ex),
        counter_line(ex)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    """
    ## Combat exchange (rolled by the server)
    The target is #{ex["defender"]}. Tell only these rolls, hits and wounds. Tell a miss as a miss: no blood and no wound. Add no hit, no wound and no other target.
    #{lines}
    """
  end

  @doc """
  A one-line text of the exchange for the mechanical resolution and the UI:
  the d100 against the target number with the Parry, the wounds and the
  counterattack. Returns nil without an attack.

      iex> ex = %{"attacker" => "Ezzor", "defender" => "Brenna",
      ...>   "attack" => %{"skill" => "melee_combat", "level" => 15, "parry" => 60, "roll" => 15, "target" => 5, "hit" => false},
      ...>   "defender_wounds" => 0, "defender_wound_max" => 3, "defender_vitality" => "ok",
      ...>   "counter" => %{"skill" => "melee_combat", "level" => 45, "parry" => 50, "roll" => 20, "target" => 45, "hit" => true}}
      iex> TalesForge.Game.Combat.summary(ex)
      "Attack: d100 15 vs 5 (melee_combat 15, Brenna's Parry 60): miss. Brenna: 0/3 wounds. Counterattack: d100 20 vs 45 (melee_combat 45, Ezzor's Parry 50): hit, Ezzor takes 1 wound."
      iex> TalesForge.Game.Combat.summary(put_in(ex, ["attack", "result"], "partial_success"))
      "Attack: d100 15 vs 5 (melee_combat 15, Brenna's Parry 60): miss (near miss). Brenna: 0/3 wounds. Counterattack: d100 20 vs 45 (melee_combat 45, Ezzor's Parry 50): hit, Ezzor takes 1 wound."
  """
  @spec summary(map() | nil) :: String.t() | nil
  def summary(%{"attack" => a} = ex) do
    attack =
      "Attack: d100 #{a["roll"]}#{forced_tail(ex)} vs #{a["target"]} (#{level_text(a)}, #{ex["defender"]}'s Parry #{a["parry"]}): #{band_word(a)}."

    wounds =
      "#{ex["defender"]}: #{ex["defender_wounds"]}/#{ex["defender_wound_max"]} wounds#{vitality_tail(ex["defender_vitality"])}."

    counter =
      case ex["counter"] do
        %{} = c ->
          tail =
            if c["hit"],
              do: "#{band_word(c)}, #{ex["attacker"]} takes 1 wound.",
              else: "#{band_word(c)}."

          "Counterattack: d100 #{c["roll"]} vs #{c["target"]} (#{level_text(c)}, #{ex["attacker"]}'s Parry #{c["parry"]}): " <>
            tail

        _ ->
          if ex["defender_vitality"] in ~w(ok hurt), do: "No counterattack.", else: nil
      end

    self_wound = if ex["self_wound"], do: "#{ex["attacker"]} takes 1 wound."

    [attack, self_wound, death_text(ex), wounds, counter]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def summary(_exchange), do: nil

  # "unarmed_combat 20 untrained": level 0 in the skill rolls the untrained
  # floor, 5 × (stat ÷ 3) (QA 2026-10-15: "unarmed_combat 20" with skill 0).
  defp level_text(%{"untrained" => true} = a), do: "#{a["skill"]} #{a["level"]} untrained"
  defp level_text(a), do: "#{a["skill"]} #{a["level"]}"

  defp forced_tail(%{"qa_forced" => true}), do: " (QA forced)"
  defp forced_tail(_ex), do: ""

  @doc """
  The death roll text of an exchange, or nil when the hit made no death roll.

      iex> TalesForge.Game.Combat.death_text(%{"defender" => "Marta Kellen",
      ...>   "death" => %{"roll" => 83, "kills_above" => 27, "dead" => true}})
      "Death roll: d100 83, above 27 kills: Marta Kellen dies."
      iex> TalesForge.Game.Combat.death_text(%{"defender" => "Marta Kellen",
      ...>   "death" => %{"roll" => 12, "kills_above" => 27, "dead" => false}})
      "Death roll: d100 12, above 27 kills: Marta Kellen lives, still down."
  """
  @spec death_text(map()) :: String.t() | nil
  def death_text(%{"death" => %{"roll" => roll, "kills_above" => above} = d} = ex) do
    fate = if d["dead"], do: "dies", else: "lives, still down"
    "Death roll: d100 #{roll}, above #{above} kills: #{ex["defender"]} #{fate}."
  end

  def death_text(_ex), do: nil

  @doc """
  The GM prompt section for the dead and the downed people of the world
  (QA 2026-10-15, session 99817343: a dead Marta talked again in the
  cellar). Nil when nobody is dead or down.

      iex> TalesForge.Game.Combat.fallen_section(%{"npc_state" => %{"marta_kellen" =>
      ...>   %{"name" => "Marta Kellen", "vitality" => "dead", "location_id" => "weary_pilgrim"}}})
      ...> |> String.split("\\n")
      ...> |> Enum.drop(1)
      ["These people cannot come back. Never narrate them alive, moving, talking or acting.",
       "- Marta Kellen is dead. The body lies at The Weary Pilgrim.", ""]
      iex> TalesForge.Game.Combat.fallen_section(%{"npc_state" => %{}})
      nil
  """
  @spec fallen_section(map() | nil) :: String.t() | nil
  def fallen_section(%{"npc_state" => state} = world) when is_map(state) do
    lines =
      state
      |> Enum.filter(fn {_id, npc} -> is_map(npc) and npc["vitality"] in ~w(dead down) end)
      |> Enum.sort_by(fn {id, _npc} -> id end)
      |> Enum.map(fn {id, npc} -> fallen_line(world, npc["name"] || id, npc) end)

    if lines == [] do
      nil
    else
      "## The dead and the downed (server state)\n" <>
        "These people cannot come back. Never narrate them alive, moving, talking or acting.\n" <>
        Enum.join(lines, "\n") <> "\n"
    end
  end

  def fallen_section(_world), do: nil

  defp fallen_line(world, name, %{"vitality" => "dead"} = npc),
    do: "- #{name} is dead. The body lies at #{body_place(world, npc["location_id"])}."

  defp fallen_line(world, name, npc),
    do:
      "- #{name} is down at #{body_place(world, npc["location_id"])}: alive, but cannot fight, stand, talk or leave."

  # The GM gets the place name, not the world id (QA 2026-10-15: a raw id
  # came out in the prose).
  defp body_place(world, id) when is_binary(id) do
    TalesForge.Game.World.runtime_location(world, id)["name"] ||
      TalesForge.Game.Context.place_name(id)
  end

  defp body_place(_world, _id), do: "the place of the fight"

  # The locked effect of a critical attack (card 26706846, answer 4) for the GM.
  defp critical_note(%{"result" => "critical_success", "skill" => skill}),
    do: Mechanics.critical_effect("critical_success", skill)

  defp critical_note(%{"result" => "critical_failure", "skill" => skill}),
    do: Mechanics.critical_effect("critical_failure", skill)

  defp critical_note(_attack), do: ""

  defp vitality_tail("down"), do: ", down"
  defp vitality_tail("dead"), do: ", dead"
  defp vitality_tail(_), do: ""

  # The band word of an attack or counterattack map. A map from before the
  # bands (no "result") falls back to hit or miss.
  defp band_word(%{"result" => result}) when is_binary(result), do: result_word(result)
  defp band_word(%{"hit" => true}), do: "hit"
  defp band_word(_), do: "miss"

  defp sentence(word), do: String.capitalize(word)

  defp death_line(ex) do
    case death_text(ex) do
      nil -> nil
      text -> "- " <> text
    end
  end

  defp defender_line(ex) do
    state =
      case ex["defender_vitality"] do
        "dead" -> "is dead"
        "down" -> "is down and cannot fight"
        "hurt" -> "is hurt and still fights"
        _ -> "has no wound"
      end

    "- #{ex["defender"]}: #{ex["defender_wounds"]} of #{ex["defender_wound_max"]} wounds, #{state}."
  end

  defp counter_line(%{"counter" => nil, "defender_vitality" => v} = ex) when v in ~w(ok hurt),
    do: "- #{ex["defender"]} does not counterattack."

  defp counter_line(%{"counter" => nil}), do: nil

  defp counter_line(%{"counter" => c} = ex) do
    result =
      if c["hit"],
        do: "#{sentence(band_word(c))}: #{ex["attacker"]} takes 1 wound.",
        else: "#{sentence(band_word(c))}: #{ex["attacker"]} takes no wound."

    "- #{ex["defender"]} counterattacks #{ex["attacker"]} (#{level_text(c)}, Parry #{c["parry"]}): d100 #{c["roll"]} against #{c["target"]}. #{result}"
  end

  defp name(fighter), do: Map.get(fighter, "name") || Map.get(fighter, "id") || "the character"

  defp to_int(value, _default) when is_integer(value), do: value
  defp to_int(value, _default) when is_float(value), do: trunc(value)

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp to_int(_value, default), do: default
end
