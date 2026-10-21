defmodule TalesForge.CharacterCreationScenarios do
  @moduledoc """
  Drafts and inputs for the character-creation golden tests.

  What the public functions return for them, `outputs/0`, is captured into
  `test/support/fixtures/cc_golden.exs`; the golden test compares against it.
  """
  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.CharacterCreation.FromText
  alias TalesForge.CharacterCreation.FromText.{Label, Reading}
  alias TalesForge.GameCharacter.Defaults

  @adventure "tin_valley"

  defp ok!({:ok, value}), do: value

  defp draft(key), do: CC.new(@adventure, seed_key: key)

  # A fixed die: each call gives the next value of a cycle.
  defp rng do
    counter = :counters.new(1, [])

    fn sides ->
      :counters.add(counter, 1, 1)
      rem(:counters.get(counter, 1) * 7, sides) + 1
    end
  end

  @doc "Named drafts covering each model, race picks, skills and error cases."
  def drafts do
    [
      {"default", draft("g-default")},
      {"named human", draft("g-human") |> CC.set_name("Ada Lovelace") |> ok!()},
      {"elf ranger hunter", elf_ranger()},
      {"half-elf picks", half_elf()},
      {"dwarf warrior rolled", rolled()},
      {"rolled then edited", rolled_edited()},
      {"from text approved", from_text() |> CC.approve() |> ok!()},
      {"from text unapproved", from_text()},
      {"many errors", many_errors()},
      {"skills over the caps", over_caps()}
    ]
  end

  defp elf_ranger do
    d = draft("g-elf")
    d = d |> CC.choose_race("elf") |> ok!() |> CC.choose_class("ranger") |> ok!()
    d = d |> CC.choose_occupation("hunter") |> ok!() |> CC.set_stat("DEX", 16) |> ok!()
    d |> CC.set_skill("stealth", 20) |> ok!() |> CC.set_name("Mira Vale") |> ok!()
  end

  defp half_elf do
    d =
      draft("g-half") |> CC.choose_race("half_elf") |> ok!() |> CC.choose_class("wizard") |> ok!()

    d |> CC.set_name("Ilse") |> ok!()
  end

  defp rolled do
    d = draft("g-roll") |> CC.choose_race("dwarf") |> ok!() |> CC.choose_class("warrior") |> ok!()
    d |> CC.choose_model("stat_roll", rng()) |> ok!() |> CC.set_name("Brokk") |> ok!()
  end

  defp rolled_edited do
    d = rolled() |> CC.reroll_stats(rng()) |> ok!()
    %{d | base_stats: Map.put(d.base_stats, "STR", 3)}
  end

  defp from_text do
    reading = %Reading{
      labels: %{
        "name" => %Label{value: "Tam", confidence: 0.9},
        "race" => %Label{value: "halfling", confidence: 0.8},
        "class" => %Label{value: "thief", confidence: 0.4},
        "occupation" => %Label{value: "thief", confidence: 0.9},
        "stats" => %Label{value: %{"DEX" => 18, "CHA" => 17, "STR" => 3}, confidence: 0.9},
        "skills" => %Label{value: %{"stealth" => 35, "lockpicking" => 30}, confidence: 0.9}
      }
    }

    draft("g-text") |> FromText.build(reading) |> ok!()
  end

  defp many_errors do
    d = draft("g-bad")
    stats = Map.new(~w(STR DEX CON INT WIS CHA), &{&1, 18})
    %{d | base_stats: stats, race: "half_elf", race_picks: ["STR"], skills: %{"stealth" => 90}}
  end

  defp over_caps do
    d = draft("g-caps") |> CC.set_name("Cap") |> ok!()
    %{d | skills: %{"stealth" => 45, "arcana" => 45, "lockpicking" => 45, "history" => 60}}
  end

  @doc "What the public functions return for each draft and input."
  def outputs do
    %{
      drafts: Map.new(drafts(), fn {name, d} -> {name, draft_outputs(d)} end),
      race_picks: race_picks(),
      derive: derive(),
      merge: merge()
    }
  end

  defp draft_outputs(d) do
    %{
      draft: d,
      validate: CC.validate(d),
      finalize: CC.finalize(d),
      final_stats: CC.final_stats(d),
      race_modifiers: CC.race_modifiers(d),
      points_left: CC.points_left(d),
      free_skills: CC.free_skills(d),
      skill_levels: CC.skill_levels(d),
      skill_budget: CC.skill_budget(d),
      skill_points_spent: CC.skill_points_spent(d),
      signature_skills: CC.signature_skills(d),
      suggested: CC.suggest_skills(d).skills
    }
  end

  defp race_picks do
    for race <- ~w(human half_elf elf dwarf),
        picks <- [[], ["STR"], ["STR", "DEX"], ["STR", "STR"], ["INT"], ["WIS"], ["LUCK"]],
        into: %{} do
      d = draft("g-picks") |> CC.choose_race(race) |> ok!()
      {{race, picks}, CC.pick_race_bonus(d, picks)}
    end
  end

  defp derive do
    rules = Defaults.rules(@adventure)

    inputs = [
      %{},
      %{"occupation" => "innkeep"},
      %{"race" => "elf", "class" => "ranger", "occupation" => "hunter", "seniority" => "master"},
      %{"race" => "dwarf", "standing" => "nobility", "occupation" => "prospector"},
      %{"race" => nil, "class" => "wizard", "standing" => "underclass"}
    ]

    for i <- inputs,
        seed <- [1, 7, 99],
        into: %{},
        do: {{i, seed}, Defaults.derive(i, rules, seed)}
  end

  defp merge do
    defaults = %{
      "stats" => %{"STR" => 10, "DEX" => 12},
      "skills" => %{"stealth" => 20, "arcana" => 10},
      "ocean" => %{"openness" => 1},
      "name" => "x",
      "coins" => %{"gold" => 1}
    }

    overrides = [
      %{},
      %{"stats" => %{"STR" => 14}, "skills" => %{"arcana" => 0, "history" => 5}},
      %{"ocean" => %{"neuroticism" => -1}, "coins" => %{"silver" => 2}, "name" => "y"},
      %{"skills" => "none"},
      %{"stats" => nil}
    ]

    Map.new(overrides, &{&1, Defaults.merge(defaults, &1)})
  end
end
