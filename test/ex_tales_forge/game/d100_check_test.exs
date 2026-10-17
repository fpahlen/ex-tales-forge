defmodule TalesForge.Game.D100CheckTest do
  @moduledoc """
  Acceptance tests for the d100 switch: the outcome bands of
  `Mechanics.resolve_check/2` for skills 5, 10, 11, 25, 50, 90, 95 and 100,
  with injected rolls.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Game.Mechanics

  # {skill, crit success max, crit failure from}: the bands from the locked answers.
  @bands [
    {5, 0, 92},
    {10, 0, 92},
    {11, 2, 93},
    {25, 3, 94},
    {50, 5, 96},
    {90, 9, 100},
    {95, 10, 100},
    {100, 10, 100}
  ]

  defp outcome(roll, skill), do: Mechanics.resolve_check(roll, skill)

  for {skill, crit_max, fail_from} <- @bands do
    test "skill #{skill}: every roll 1..100 lands in the right band" do
      skill = unquote(skill)
      crit_max = unquote(crit_max)
      fail_from = unquote(fail_from)

      for roll <- 1..100 do
        expected =
          cond do
            roll == 100 and skill >= 100 -> :reroll
            roll <= crit_max -> "critical_success"
            roll <= skill -> "success"
            roll >= fail_from -> "critical_failure"
            roll <= skill + 15 -> "partial_success"
            true -> "failure"
          end

        assert outcome(roll, skill) == expected, "skill #{skill}, roll #{roll}"
      end
    end
  end

  test "critical success is not possible at skill 10 or below" do
    for skill <- [1, 5, 10], do: assert(outcome(1, skill) == "success")
    assert outcome(1, 11) == "critical_success"
    assert outcome(2, 11) == "critical_success"
    assert outcome(3, 11) == "success"
  end

  test "a roll of 100 is always a critical failure below skill 100" do
    for skill <- [1, 50, 90, 95, 99], do: assert(outcome(100, skill) == "critical_failure")
  end

  test "near miss is 1 to 15 above the skill, before the critical failure band" do
    assert outcome(26, 25) == "partial_success"
    assert outcome(40, 25) == "partial_success"
    assert outcome(41, 25) == "failure"
    assert outcome(96, 95) == "partial_success"
    assert outcome(99, 95) == "partial_success"
  end

  describe "perform_and_apply/4 with injected rolls" do
    defp char(level), do: %{"skills" => %{"stealth" => level}, "stats" => %{"DEX" => 10}}

    test "at skill 100 a roll of 100 rolls again; a failed second roll is a critical failure" do
      {_c, r} = Mechanics.perform_and_apply(char(100), "stealth", roll: [100, 100])
      assert r.outcome == "critical_failure"

      {_c, r} = Mechanics.perform_and_apply(char(100), "stealth", roll: [100, 40])
      assert r.outcome == "success"
    end

    test "the critical bands use the effective skill (level + stat bonus)" do
      c = %{"skills" => %{"stealth" => 40}, "stats" => %{"DEX" => 14}}
      {_c, r} = Mechanics.perform_and_apply(c, "stealth", roll: 5)
      assert r.effective_skill == 50
      assert r.outcome == "critical_success"
    end

    test "a near miss banks one improvement chance; a critical failure banks none" do
      {near, r} = Mechanics.perform_and_apply(char(25), "stealth", roll: 30)
      assert r.outcome == "partial_success"
      assert near["learning_points"]["stealth"] == 1.0

      {crit, r} = Mechanics.perform_and_apply(char(25), "stealth", roll: 99)
      assert r.outcome == "critical_failure"
      assert Map.get(crit["learning_points"] || %{}, "stealth", 0) == 0
    end

    test "the multiply-by-5 migration keeps the odds of a plain success" do
      for level <- 1..19 do
        d20_success = level / 20
        d100_success = Enum.count(1..100, &(&1 <= level * 5)) / 100
        assert_in_delta d20_success, d100_success, 1.0e-9
      end
    end
  end
end
