defmodule TalesForge.Game.Combat do
  @moduledoc """
  Opposed combat rolls (`priv/rules/combat.md`, `COMBAT_OPPOSED=on`). Pure:
  no Repo, no LLM, no random numbers. The caller injects every roll.

  One exchange has two steps:

    1. The attack. The attacker rolls a d20 for the combat skill against the
       defender's Parry (`parry/1`). The roll hits when it is equal to or
       less than `attack_target/2`, and is not a natural 20. A natural 1
       always hits. A hit gives the defender one wound.
    2. The counterattack. A defender that is still up fights back when the
       chance roll is less than `counter_chance/1`. It rolls its own combat
       skill against the attacker's Parry. A hit gives the attacker one wound.

  A miss is only a miss. The attacker takes a wound only from a counterattack
  hit. A fighter is a string-keyed map with `stats`, `skills` and,
  for an NPC, `ocean`, `maslow`, `concerns`, `wounds` and `wound_max`.

  NPC wounds live in `world_state["npc_state"][id]` (`book/4`). An NPC at the
  wound cap is down. A hit on an NPC that is down makes the death roll of
  `combat.md`: a d20 greater than CON/2 kills it. The death stays in the
  session. A minor foe (`minor_foe/4`) has 1 wound and the untrained floor.
  """

  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.Mechanics

  @combat_skills ~w(melee_combat ranged_combat unarmed_combat)
  @combat_keys ~w(wounds wound_max vitality minor)

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
          required(:attack) => 1..20,
          optional(:counter_chance) => float(),
          optional(:counter) => 1..20,
          optional(:death) => 1..20
        }
  @type target ::
          {:npc, String.t()} | {:foe, String.t(), String.t()} | {:unclear, [String.t()]}

  @doc "The combat skills."
  @spec combat_skills() :: [String.t()]
  def combat_skills, do: @combat_skills

  @doc """
  Parry from `combat.md`: Dodge/2 + 10 + (DEX - 10)/2, rounded down. Dodge is
  the effective dodge level (`Mechanics.effective_level/2`), so an untrained
  fighter uses the untrained floor.

      iex> TalesForge.Game.Combat.parry(%{"stats" => %{"DEX" => 10}, "skills" => %{"dodge" => 4}})
      12
  """
  @spec parry(fighter()) :: integer()
  def parry(fighter) do
    dodge = Mechanics.effective_level(fighter, "dodge")
    dex = fighter |> get_in(["stats", "DEX"]) |> to_int(10)
    div(dodge, 2) + 10 + Integer.floor_div(dex - 10, 2)
  end

  @doc """
  The highest roll that hits: the skill level less the Parry above 10, at
  least 1. Parry 10 gives the skill level.

      iex> TalesForge.Game.Combat.attack_target(8, 12)
      6
      iex> TalesForge.Game.Combat.attack_target(2, 14)
      1
  """
  @spec attack_target(integer(), integer()) :: pos_integer()
  def attack_target(level, parry), do: max(1, level - (parry - 10))

  @doc "True when `roll` hits `target`: a natural 1, or equal to or less than the target and not 20."
  @spec hit?(1..20, pos_integer()) :: boolean()
  def hit?(1, _target), do: true
  def hit?(20, _target), do: false
  def hit?(roll, target), do: roll <= target

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
        0.03 * (min(lvl, 14) - 4) +
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
  defender may counterattack. `rolls.attack` is the attacker's d20,
  `rolls.counter_chance` (0 to 1) decides the counterattack, `rolls.counter`
  is the defender's d20 and `rolls.death` the defender's death roll.

  Returns a string-keyed map: `attacker`, `defender`, `attack`, `counter`
  (nil without a counterattack), `defender_wounds`, `defender_wound_max`,
  `defender_vitality` (`ok`, `hurt`, `down` or `dead`) and `attacker_wounded`.
  """
  @spec exchange(fighter(), fighter(), String.t() | nil, rolls()) :: map()
  def exchange(attacker, defender, skill, rolls) do
    {attack_skill, attack_level} = combat_skill(attacker, skill)
    defender_parry = parry(defender)
    target = attack_target(attack_level, defender_parry)
    hit = hit?(rolls.attack, target)

    cap = wound_max(defender)
    before = defender |> Map.get("wounds", 0) |> to_int(0) |> min(cap)
    vitality_before = Map.get(defender, "vitality") || vitality(before, cap)
    {wounds, vitality} = take_hit(hit, before, cap, vitality_before, defender, rolls)

    counter =
      if vitality in ~w(ok hurt) do
        counterattack(attacker, Map.put(defender, "wounds", wounds), rolls)
      end

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
        "hit" => hit
      },
      "counter" => counter,
      "defender_wounds" => wounds,
      "defender_wound_max" => cap,
      "defender_vitality" => vitality,
      "attacker_wounded" => (counter && counter["hit"]) || false
    }
  end

  defp take_hit(false, wounds, _cap, vitality, _defender, _rolls), do: {wounds, vitality}
  defp take_hit(true, wounds, _cap, "dead", _defender, _rolls), do: {wounds, "dead"}

  defp take_hit(true, wounds, cap, _vitality, defender, rolls) when wounds >= cap do
    con = defender |> get_in(["stats", "CON"]) |> to_int(10)
    if Map.get(rolls, :death, 1) > div(con, 2), do: {cap, "dead"}, else: {cap, "down"}
  end

  defp take_hit(true, wounds, cap, _vitality, _defender, _rolls) do
    after_hit = wounds + 1
    {after_hit, vitality(after_hit, cap)}
  end

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
        "hit" => hit?(roll, target)
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

    * a present NPC by id, by name or by a name word in `text` gives `{:npc, id}`;
    * a person word ("the miner") with no present NPC gives
      `{:foe, id, name}`: the server makes a minor foe for the scene;
    * anything else gives `{:unclear, names}` with the names of the present
      people, and the turn asks the player.

      iex> world = %{"present_npcs" => ["guild_steward"],
      ...>   "npc_state" => %{"guild_steward" => %{"name" => "Osric Vane"}}}
      iex> TalesForge.Game.Combat.target(nil, "I attack Osric the liar", world)
      {:npc, "guild_steward"}
      iex> TalesForge.Game.Combat.target(nil, "I do attack the miner", world)
      {:foe, "foe_miner", "a miner"}
      iex> TalesForge.Game.Combat.target(nil, "I lash out", world)
      {:unclear, ["Osric Vane"]}
  """
  @spec target(String.t() | nil, String.t() | nil, map()) :: target()
  def target(action_target, text, world) do
    present = present_people(world)
    text = String.downcase(text || "")

    cond do
      id = by_id_or_name(present, action_target) -> {:npc, id}
      id = by_text(present, text) -> {:npc, id}
      noun = person_word(action_target, text) -> foe_target(noun, world)
      true -> {:unclear, Enum.map(present, &elem(&1, 1))}
    end
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
  Keeps the combat keys (`wounds`, `wound_max`, `vitality`, `minor`) and the
  minor foes of `before` in the `after_state` npc_state map. The board
  rebuilds npc_state from the NPC instances each turn, so this step carries
  the session combat state over.
  """
  @spec carry(map(), map()) :: map()
  def carry(before, after_state) do
    before = before || %{}

    Enum.reduce(before, after_state || %{}, fn {id, npc}, acc ->
      kept = Map.take(npc || %{}, @combat_keys)

      cond do
        npc["minor"] == true -> Map.put(acc, id, npc)
        kept == %{} -> acc
        Map.has_key?(acc, id) -> Map.update!(acc, id, &Map.merge(&1, kept))
        true -> acc
      end
    end)
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
        "- #{ex["attacker"]} attacks #{ex["defender"]} (#{attack["skill"]} #{attack["level"]}, #{ex["defender"]}'s Parry #{attack["parry"]}): d20 #{attack["roll"]} against #{attack["target"]}. #{hit_word(attack["hit"])}.",
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

  defp hit_word(true), do: "Hit"
  defp hit_word(false), do: "Miss"

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
        do: "Hit: #{ex["attacker"]} takes 1 wound.",
        else: "Miss: #{ex["attacker"]} takes no wound."

    "- #{ex["defender"]} counterattacks #{ex["attacker"]} (#{c["skill"]} #{c["level"]}, Parry #{c["parry"]}): d20 #{c["roll"]} against #{c["target"]}. #{result}"
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
