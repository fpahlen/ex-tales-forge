defmodule TalesForge.Game.SkillListV2Test do
  # The env flag is global, so this test is not async.
  use ExUnit.Case, async: false

  alias TalesForge.Game.Mechanics

  setup do
    on_exit(fn -> System.delete_env("JEV_CATALOGUE_V2") end)
  end

  test "flag off: list v1 and insight for a search" do
    System.delete_env("JEV_CATALOGUE_V2")
    assert map_size(Mechanics.skill_stat_map()) == 17
    assert Mechanics.infer_check_skill("I search the chest") == "insight"
  end

  test "flag on: 28 skills, no general crafting skill, and the new verbs" do
    System.put_env("JEV_CATALOGUE_V2", "on")
    skills = Mechanics.skill_stat_map()
    assert map_size(skills) == 28
    refute Map.has_key?(skills, "crafting")
    assert Mechanics.infer_check_skill("I search the chest") == "perception"
    assert Mechanics.infer_check_skill("I pickpocket the drover") == "sleight_of_hand"
    assert Mechanics.infer_check_skill("I bandage his arm") == "medicine"
    assert Mechanics.infer_check_skill("I appraise the ring") == "appraisal"
    assert Mechanics.infer_check_skill("I cook a simple stew") == nil
  end
end
