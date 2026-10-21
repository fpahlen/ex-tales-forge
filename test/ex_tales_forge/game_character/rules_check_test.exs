defmodule TalesForge.GameCharacter.RulesCheckTest do
  use ExUnit.Case, async: true

  alias TalesForge.GameCharacter.RulesCheck
  alias TalesForge.GameCharacter.RulesCheck.Rule

  test "a rule lists unknown names in order, duplicates kept, and raises its message" do
    rule = %Rule{names: ~w(a x b x), known: ~w(a b), message: &"bad #{inspect(&1)}"}

    assert Rule.unknown(rule) == ["x", "x"]
    assert_raise ArgumentError, ~s(bad ["x", "x"]), fn -> Rule.check!(rule) end
    assert Rule.check!(%{rule | names: ["a"]}) == :ok
  end

  test "the six stats" do
    assert RulesCheck.stats() == ~w(STR DEX CON INT WIS CHA)
  end
end
