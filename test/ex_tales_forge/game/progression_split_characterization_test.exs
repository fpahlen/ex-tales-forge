defmodule TalesForge.Game.ProgressionSplitCharacterizationTest do
  @moduledoc """
  Characterization of `Progression.resolve_rest/3` and `SkillSplit.apply/2`
  (the private `split/3`) before round 2 PR 7: exact outputs from main, with
  every roll injected. Pure, no LLM calls.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Game.{Progression, SkillSplit}
  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction, SingleAction}

  # Skills below and at or above the reflection level (50), banked LP as a
  # float, an integer, a string and zero, and a skill with LP but no level.
  @character %{
    "skills" => %{"climbing" => 25, "stealth" => 60, "lore" => 55, "dodge" => 10, "zeal" => 70},
    "learning_points" => %{
      "climbing" => 5.0,
      "stealth" => 3,
      "lore" => "4.5",
      "dodge" => 0.0,
      "zeal" => 2.0,
      "swim" => 2.0
    }
  }

  @rolls %{
    "climbing" => [3, {55, 5}],
    "stealth" => [90, 91],
    "swim" => [{99, 4}],
    "lore" => [10]
  }

  describe "resolve_rest/3" do
    test "alphabetical; skills that need reflection are pending, in order" do
      assert Progression.resolve_rest(@character, @rolls) ==
               {%{
                  "learning_points" => %{
                    "climbing" => 0.0,
                    "dodge" => 0.0,
                    "lore" => "4.5",
                    "stealth" => 3,
                    "swim" => 0.0,
                    "zeal" => 2.0
                  },
                  "skills" => %{
                    "climbing" => 30,
                    "dodge" => 10,
                    "lore" => 55,
                    "stealth" => 60,
                    "swim" => 4,
                    "zeal" => 70
                  }
                },
                [
                  %{
                    "improved" => false,
                    "lp_spent" => 2,
                    "raw_skill" => 25,
                    "roll" => 3,
                    "skill" => "climbing"
                  },
                  %{
                    "effective_after" => 30,
                    "effective_before" => 25,
                    "gain" => 5,
                    "improved" => true,
                    "lp_cleared" => 1,
                    "lp_spent" => 2,
                    "raw_skill" => 25,
                    "roll" => 55,
                    "skill" => "climbing"
                  },
                  %{
                    "effective_after" => 4,
                    "effective_before" => 15,
                    "gain" => 4,
                    "improved" => true,
                    "lp_cleared" => 1,
                    "lp_spent" => 1,
                    "raw_skill" => 0,
                    "roll" => 99,
                    "skill" => "swim"
                  }
                ], ["lore", "stealth", "zeal"]}
    end

    test "a reflected skill rolls; the rest stay pending" do
      assert Progression.resolve_rest(@character, @rolls, reflected: ["lore"]) ==
               {%{
                  "learning_points" => %{
                    "climbing" => 0.0,
                    "dodge" => 0.0,
                    "lore" => 0.0,
                    "stealth" => 3,
                    "swim" => 0.0,
                    "zeal" => 2.0
                  },
                  "skills" => %{
                    "climbing" => 30,
                    "dodge" => 10,
                    "lore" => 55,
                    "stealth" => 60,
                    "swim" => 4,
                    "zeal" => 70
                  }
                },
                [
                  %{
                    "improved" => false,
                    "lp_spent" => 2,
                    "raw_skill" => 25,
                    "roll" => 3,
                    "skill" => "climbing"
                  },
                  %{
                    "effective_after" => 30,
                    "effective_before" => 25,
                    "gain" => 5,
                    "improved" => true,
                    "lp_cleared" => 1,
                    "lp_spent" => 2,
                    "raw_skill" => 25,
                    "roll" => 55,
                    "skill" => "climbing"
                  },
                  %{
                    "improved" => false,
                    "lp_cleared" => 0,
                    "lp_spent" => 4,
                    "raw_skill" => 55,
                    "roll" => 10,
                    "skill" => "lore"
                  },
                  %{
                    "effective_after" => 4,
                    "effective_before" => 15,
                    "gain" => 4,
                    "improved" => true,
                    "lp_cleared" => 1,
                    "lp_spent" => 1,
                    "raw_skill" => 0,
                    "roll" => 99,
                    "skill" => "swim"
                  }
                ], ["stealth", "zeal"]}
    end

    test "only: the named skills" do
      assert Progression.resolve_rest(@character, @rolls, only: ["zeal", "climbing", "stealth"]) ==
               {%{
                  "learning_points" => %{
                    "climbing" => 0.0,
                    "dodge" => 0.0,
                    "lore" => "4.5",
                    "stealth" => 3,
                    "swim" => 2.0,
                    "zeal" => 2.0
                  },
                  "skills" => %{
                    "climbing" => 30,
                    "dodge" => 10,
                    "lore" => 55,
                    "stealth" => 60,
                    "zeal" => 70
                  }
                },
                [
                  %{
                    "improved" => false,
                    "lp_spent" => 2,
                    "raw_skill" => 25,
                    "roll" => 3,
                    "skill" => "climbing"
                  },
                  %{
                    "effective_after" => 30,
                    "effective_before" => 25,
                    "gain" => 5,
                    "improved" => true,
                    "lp_cleared" => 1,
                    "lp_spent" => 2,
                    "raw_skill" => 25,
                    "roll" => 55,
                    "skill" => "climbing"
                  }
                ], ["stealth", "zeal"]}
    end

    test "only: [] rests nothing" do
      assert Progression.resolve_rest(@character, %{}, only: [], reflected: ["stealth"]) ==
               {%{
                  "learning_points" => %{
                    "climbing" => 5.0,
                    "dodge" => 0.0,
                    "lore" => "4.5",
                    "stealth" => 3,
                    "swim" => 2.0,
                    "zeal" => 2.0
                  },
                  "skills" => %{
                    "climbing" => 25,
                    "dodge" => 10,
                    "lore" => 55,
                    "stealth" => 60,
                    "zeal" => 70
                  }
                }, [], []}
    end

    test "no learning points" do
      assert Progression.resolve_rest(%{}) == {%{}, [], []}
    end
  end

  describe "SkillSplit.apply/2" do
    @fighter %{
      "skills" => %{"melee_combat" => 160},
      "stats" => %{"STR" => 10},
      "learning_points" => %{}
    }

    defp apply_split(text, rolls, params) do
      action = %PlayerAction{
        overall_intent: text,
        action: %SingleAction{action_type: :combat, parameters: params}
      }

      SkillSplit.apply(@fighter, %SkillSplit.Check{
        player_action: action,
        handler: %HandlerResult{handler: "skill_check", skill: "melee_combat"},
        text: text,
        rolls: rolls
      })
    end

    test "the exact character and resolution for each split" do
      cases = [
        {"three attacks", [80, 80, 80], %{},
         {%{
            "learning_failures" => %{"melee_combat" => 1},
            "learning_points" => %{"melee_combat" => 1.0},
            "skills" => %{"melee_combat" => 160},
            "stats" => %{"STR" => 10}
          },
          %MechanicalResolution{
            skill: "melee_combat",
            outcome: "failure",
            roll: 80,
            effective_skill: 54,
            lp_awarded: 1.0,
            notes:
              "Split into 3 parts: 54 rolled 80 (failure), 53 rolled 80 (failure), 53 rolled 80 (failure). One learning chance at most.",
            improvements: [],
            training: nil,
            parts: [
              %{"level" => 54, "outcome" => "failure", "roll" => 80},
              %{"level" => 53, "outcome" => "failure", "roll" => 80},
              %{"level" => 53, "outcome" => "failure", "roll" => 80}
            ],
            split: %{"parts" => ~c"655", "requested" => 3},
            combat: nil
          }}},
        {"three attacks", [5, 90, 40], %{},
         {%{
            "learning_failures" => %{"melee_combat" => 1},
            "learning_points" => %{"melee_combat" => 1.0},
            "skills" => %{"melee_combat" => 160},
            "stats" => %{"STR" => 10}
          },
          %MechanicalResolution{
            skill: "melee_combat",
            outcome: "critical_success",
            roll: 5,
            effective_skill: 54,
            lp_awarded: 1.0,
            notes:
              "Split into 3 parts: 54 rolled 5 (critical_success), 53 rolled 90 (failure), 53 rolled 40 (success). One learning chance at most.",
            improvements: [],
            training: nil,
            parts: [
              %{"level" => 54, "outcome" => "critical_success", "roll" => 5},
              %{"level" => 53, "outcome" => "failure", "roll" => 90},
              %{"level" => 53, "outcome" => "success", "roll" => 40}
            ],
            split: %{"parts" => ~c"655", "requested" => 3},
            combat: nil
          }}},
        {"I attack twice", [12, 20], %{},
         {%{
            "learning_points" => %{},
            "skills" => %{"melee_combat" => 160},
            "stats" => %{"STR" => 10}
          },
          %MechanicalResolution{
            skill: "melee_combat",
            outcome: "success",
            roll: 12,
            effective_skill: 80,
            lp_awarded: 0.0,
            notes:
              "Split into 2 parts: 80 rolled 12 (success), 80 rolled 20 (success). One learning chance at most.",
            improvements: [],
            training: nil,
            parts: [
              %{"level" => 80, "outcome" => "success", "roll" => 12},
              %{"level" => 80, "outcome" => "success", "roll" => 20}
            ],
            split: %{"parts" => ~c"PP", "requested" => 2},
            combat: nil
          }}},
        {"two cuts at 95 and 55", [50, 3], %{},
         {%{
            "learning_points" => %{},
            "skills" => %{"melee_combat" => 160},
            "stats" => %{"STR" => 10}
          },
          %MechanicalResolution{
            skill: "melee_combat",
            outcome: "success",
            roll: 50,
            effective_skill: 160,
            lp_awarded: 0.0,
            notes: "Rolled 50 vs melee_combat 160 (base 160). Success: nothing to learn.",
            improvements: [],
            training: nil,
            parts: nil,
            split: %{"refused" => "parts_do_not_sum", "requested" => ~c"_7"},
            combat: nil
          }}},
        {"two cuts at 100 and 60", [50, 3], %{},
         {%{
            "learning_points" => %{},
            "skills" => %{"melee_combat" => 160},
            "stats" => %{"STR" => 10}
          },
          %MechanicalResolution{
            skill: "melee_combat",
            outcome: "critical_success",
            roll: 3,
            effective_skill: 60,
            lp_awarded: 0.0,
            notes:
              "Split into 2 parts: 100 rolled 50 (success), 60 rolled 3 (critical_success). One learning chance at most.",
            improvements: [],
            training: nil,
            parts: [
              %{"level" => 100, "outcome" => "success", "roll" => 50},
              %{"level" => 60, "outcome" => "critical_success", "roll" => 3}
            ],
            split: %{"parts" => ~c"d<", "requested" => 2},
            combat: nil
          }}},
        {"I attack", [3, 60], %{"split" => 2},
         {%{
            "learning_points" => %{},
            "skills" => %{"melee_combat" => 160},
            "stats" => %{"STR" => 10}
          },
          %MechanicalResolution{
            skill: "melee_combat",
            outcome: "critical_success",
            roll: 3,
            effective_skill: 80,
            lp_awarded: 0.0,
            notes:
              "Split into 2 parts: 80 rolled 3 (critical_success), 80 rolled 60 (success). One learning chance at most.",
            improvements: [],
            training: nil,
            parts: [
              %{"level" => 80, "outcome" => "critical_success", "roll" => 3},
              %{"level" => 80, "outcome" => "success", "roll" => 60}
            ],
            split: %{"parts" => ~c"PP", "requested" => 2},
            combat: nil
          }}},
        {"I attack", [3], %{},
         {%{
            "learning_points" => %{},
            "skills" => %{"melee_combat" => 160},
            "stats" => %{"STR" => 10}
          },
          %MechanicalResolution{
            skill: "melee_combat",
            outcome: "critical_success",
            roll: 3,
            effective_skill: 160,
            lp_awarded: 0.0,
            notes:
              "Rolled 3 vs melee_combat 160 (base 160). Success: nothing to learn. Critical success. The blow lands with full damage and every bonus.",
            improvements: [],
            training: nil,
            parts: nil,
            split: nil,
            combat: nil
          }}}
      ]

      for {text, rolls, params, expected} <- cases do
        assert apply_split(text, rolls, params) == expected, "#{text} #{inspect(rolls)}"
      end
    end
  end
end
