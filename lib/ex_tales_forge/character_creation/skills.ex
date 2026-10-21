defmodule TalesForge.CharacterCreation.Skills do
  @moduledoc """
  The skill rules of character creation, as pure functions of a draft and
  its adventure's creation rules: free levels (class package, race bonus and
  past occupation, cut to the caps), the final levels, the point budget and
  spend, the skill errors and the suggested spread.
  """
  alias TalesForge.CharacterCreation.{Draft, Options, Spread}
  alias TalesForge.Game.Mechanics

  @type rules :: %{required(String.t()) => map()}
  @type levels :: %{optional(String.t()) => non_neg_integer()}

  @doc "Free levels before the caps, and the skills in priority order (class package, then race)."
  @spec free_sources(Draft.t(), rules()) :: {levels(), [String.t()]}
  def free_sources(%Draft{} = draft, rules) do
    creation = rules["creation"]
    class = Options.class_skills(rules["labels"]["classes"][draft.class], creation)
    race = Map.get(Options.race_bonus(creation, draft.race), "fixed", %{})
    past = Options.occupation_skills(rules["labels"]["occupations"][draft.occupation], creation)
    sum = fn _skill, a, b -> a + b end

    {class |> Map.merge(race, sum) |> Map.merge(past, sum),
     Map.keys(class) ++ Map.keys(race) ++ Map.keys(past)}
  end

  @doc """
  `{free levels after the caps, points refunded for the levels cut off}`. A
  free level above the cap makes a signature skill; past the signature cap,
  or past the signature count (the highest free levels keep it), it is cut
  and refunded.
  """
  @spec free_levels(rules(), Draft.t()) :: {levels(), non_neg_integer()}
  def free_levels(rules, %Draft{} = draft) do
    sk = rules["creation"]["skills"]
    {raw, _order} = free_sources(draft, rules)
    signature = signature(raw, sk)
    Enum.reduce(raw, {%{}, 0}, &cap_level(&1, &2, {sk, signature}))
  end

  # The free levels that keep a signature skill: the highest above the cap.
  defp signature(raw, sk) do
    raw
    |> Enum.filter(fn {_s, l} -> l > sk["cap"] end)
    |> Enum.sort_by(fn {s, l} -> {-l, s} end)
    |> Enum.take(sk["signature_max"])
    |> MapSet.new(fn {s, _l} -> s end)
  end

  defp cap_level({skill, level}, {acc, refund}, {sk, signature}) do
    top = if MapSet.member?(signature, skill), do: sk["signature_cap"], else: sk["cap"]
    kept = min(level, top)
    {Map.put(acc, skill, kept), refund + Spread.cost(sk, kept, level)}
  end

  @doc "The final levels: for each skill the higher of its free level and the level set."
  @spec levels(Draft.t(), rules()) :: levels()
  def levels(%Draft{} = draft, rules) do
    {free, _refund} = free_levels(rules, draft)

    free
    |> Map.merge(draft.skills, fn _skill, f, set -> max(f, set) end)
    |> Map.reject(fn {_skill, level} -> level <= 0 end)
  end

  @doc "The skill point budget: the base, the race pool and the refund."
  @spec budget(Draft.t(), rules()) :: non_neg_integer()
  def budget(%Draft{} = draft, rules) do
    sk = rules["creation"]["skills"]
    {_free, refund} = free_levels(rules, draft)
    sk["budget"] + Map.get(Options.race_bonus(rules["creation"], draft.race), "pool", 0) + refund
  end

  @doc "The skill points spent on levels above the free ones."
  @spec points_spent(Draft.t(), rules()) :: non_neg_integer()
  def points_spent(%Draft{} = draft, rules) do
    sk = rules["creation"]["skills"]
    {free, _refund} = free_levels(rules, draft)

    Enum.reduce(draft.skills, 0, fn {skill, level}, acc ->
      acc + Spread.cost(sk, Map.get(free, skill, 0), level)
    end)
  end

  @doc "The skill errors (each `{:skills, message}` or `false`), in a fixed order."
  @spec errors(Draft.t(), rules()) :: [{:skills, String.t()} | false]
  def errors(%Draft{} = draft, rules) do
    sk = rules["creation"]["skills"]
    levels = levels(draft, rules)
    budget = budget(draft, rules)
    spent = points_spent(draft, rules)
    signature = Enum.count(levels, fn {_s, l} -> l > sk["cap"] end)

    [
      spent > budget && {:skills, "#{budget} skill points at most; #{spent} spent"},
      signature > sk["signature_max"] &&
        {:skills,
         "#{sk["signature_max"]} signature skills at most (above #{sk["cap"]}); #{signature} chosen"},
      Enum.any?(levels, fn {_s, l} -> l > sk["signature_cap"] end) &&
        {:skills, "a skill goes up to #{sk["signature_cap"]} at most"},
      map_size(levels) < sk["min_skills"] &&
        {:skills, "choose at least #{sk["min_skills"]} skills; #{map_size(levels)} so far"}
    ]
  end

  @doc """
  A spread build: the leading skills (class package, race bonus, past
  occupation) plus fillers for the highest of `stats`, at least one more
  than the minimum. Raised lowest first, one level at a time, up to the
  normal cap; when every one is at the cap and points are left, the next
  filler joins. Returns the levels set above the free ones.
  """
  @spec suggested(Draft.t(), rules(), %{optional(String.t()) => integer()}) :: levels()
  def suggested(%Draft{} = draft, rules, stats) do
    {free, _refund} = free_levels(rules, draft)
    {_raw, sources} = free_sources(draft, rules)
    leading = Enum.uniq(sources)

    %{spread(leading, fillers(leading, stats), rules) | left: budget(draft, rules)}
    |> Spread.start(free)
    |> Spread.raise_lowest()
    |> Map.fetch!(:levels)
    |> Map.reject(fn {skill, level} -> level <= Map.get(free, skill, 0) end)
  end

  defp spread(leading, fillers, rules) do
    sk = rules["creation"]["skills"]
    {first, rest} = Enum.split(fillers, max(sk["min_skills"] + 1 - length(leading), 0))
    %Spread{candidates: leading ++ first, rest: rest, sk: sk}
  end

  defp fillers(leading, stats) do
    Mechanics.skill_stat_map()
    |> Enum.sort_by(fn {skill, stat} -> {-Map.get(stats, stat, 10), skill} end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1 in leading))
  end
end
