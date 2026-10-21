defmodule TalesForge.CharacterCreation.ScenariosGoldenTest do
  @moduledoc """
  Characterization tests for round 1b of the refactor: what validate/1,
  finalize/1, the skill and stat functions, pick_race_bonus/2,
  FromText.build/2, Defaults.derive/3 and Defaults.merge/2 return for the
  scenarios in `TalesForge.CharacterCreationScenarios`, against the
  outputs captured before the refactor.
  """
  use ExUnit.Case, async: true

  alias TalesForge.CharacterCreationScenarios, as: Scenarios

  @fixture "test/support/fixtures/cc_golden.exs"
  @expected @fixture |> Code.eval_file() |> elem(0)

  setup_all do
    {:ok, actual: Scenarios.outputs()}
  end

  for {name, outputs} <- @expected.drafts, {key, _} <- outputs do
    @name name
    @key key
    test "#{name}: #{key}", %{actual: actual} do
      assert get_in(actual, [:drafts, @name, @key]) == get_in(@expected, [:drafts, @name, @key])
    end
  end

  test "the same scenarios as the fixture", %{actual: actual} do
    assert Map.keys(actual.drafts) == Map.keys(@expected.drafts)
  end

  for key <- [:race_picks, :derive, :merge] do
    @key key
    test "#{key} for every input", %{actual: actual} do
      for {input, expected} <- Map.fetch!(@expected, @key) do
        assert Map.fetch!(Map.fetch!(actual, @key), input) == expected, inspect(input)
      end

      assert map_size(Map.fetch!(actual, @key)) == map_size(Map.fetch!(@expected, @key))
    end
  end
end
