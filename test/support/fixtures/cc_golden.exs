# Captured from TalesForge.CharacterCreationScenarios.outputs/0 before round 1b.
# Characterization fixture: regenerate only for an intended behaviour change.
%{
  merge: %{
    %{} => %{
      "coins" => %{"gold" => 1},
      "name" => "x",
      "ocean" => %{"openness" => 1},
      "skills" => %{"arcana" => 10, "stealth" => 20},
      "stats" => %{"DEX" => 12, "STR" => 10}
    },
    %{"skills" => "none"} => %{
      "coins" => %{"gold" => 1},
      "name" => "x",
      "ocean" => %{"openness" => 1},
      "skills" => "none",
      "stats" => %{"DEX" => 12, "STR" => 10}
    },
    %{"stats" => nil} => %{
      "coins" => %{"gold" => 1},
      "name" => "x",
      "ocean" => %{"openness" => 1},
      "skills" => %{"arcana" => 10, "stealth" => 20},
      "stats" => nil
    },
    %{"skills" => %{"arcana" => 0, "history" => 5}, "stats" => %{"STR" => 14}} => %{
      "coins" => %{"gold" => 1},
      "name" => "x",
      "ocean" => %{"openness" => 1},
      "skills" => %{"history" => 5, "stealth" => 20},
      "stats" => %{"DEX" => 12, "STR" => 14}
    },
    %{
      "coins" => %{"silver" => 2},
      "name" => "y",
      "ocean" => %{"neuroticism" => -1}
    } => %{
      "coins" => %{"silver" => 2},
      "name" => "y",
      "ocean" => %{"neuroticism" => -1, "openness" => 1},
      "skills" => %{"arcana" => 10, "stealth" => 20},
      "stats" => %{"DEX" => 12, "STR" => 10}
    }
  },
  derive: %{
    {%{}, 1} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "wages",
          "priority" => 5,
          "text" => "Get paid for the week's work"
        }
      ],
      "maslow" => "safety",
      "ocean" => %{
        "agreeableness" => 4,
        "conscientiousness" => 6,
        "extraversion" => 4,
        "neuroticism" => 5,
        "openness" => 5
      },
      "skills" => %{"climbing" => 40, "survival" => 20, "unarmed_combat" => 40},
      "stats" => %{
        "CHA" => 11,
        "CON" => 9,
        "DEX" => 11,
        "INT" => 10,
        "STR" => 10,
        "WIS" => 11
      }
    },
    {%{}, 7} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "wages",
          "priority" => 5,
          "text" => "Get paid for the week's work"
        }
      ],
      "maslow" => "safety",
      "ocean" => %{
        "agreeableness" => 5,
        "conscientiousness" => 4,
        "extraversion" => 5,
        "neuroticism" => 5,
        "openness" => 4
      },
      "skills" => %{"climbing" => 40, "survival" => 20, "unarmed_combat" => 40},
      "stats" => %{
        "CHA" => 9,
        "CON" => 11,
        "DEX" => 10,
        "INT" => 11,
        "STR" => 9,
        "WIS" => 10
      }
    },
    {%{}, 99} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "wages",
          "priority" => 5,
          "text" => "Get paid for the week's work"
        }
      ],
      "maslow" => "safety",
      "ocean" => %{
        "agreeableness" => 4,
        "conscientiousness" => 6,
        "extraversion" => 4,
        "neuroticism" => 6,
        "openness" => 4
      },
      "skills" => %{"climbing" => 40, "survival" => 20, "unarmed_combat" => 40},
      "stats" => %{
        "CHA" => 10,
        "CON" => 9,
        "DEX" => 11,
        "INT" => 9,
        "STR" => 10,
        "WIS" => 9
      }
    },
    {%{"occupation" => "innkeep"}, 1} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "regulars",
          "priority" => 5,
          "text" => "Keep the inn full and the regulars safe"
        }
      ],
      "maslow" => "belonging",
      "ocean" => %{
        "agreeableness" => 5,
        "conscientiousness" => 7,
        "extraversion" => 6,
        "neuroticism" => 5,
        "openness" => 5
      },
      "skills" => %{"etiquette" => 20, "insight" => 40, "persuasion" => 40},
      "stats" => %{
        "CHA" => 11,
        "CON" => 9,
        "DEX" => 11,
        "INT" => 10,
        "STR" => 10,
        "WIS" => 11
      }
    },
    {%{"occupation" => "innkeep"}, 7} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "regulars",
          "priority" => 5,
          "text" => "Keep the inn full and the regulars safe"
        }
      ],
      "maslow" => "belonging",
      "ocean" => %{
        "agreeableness" => 6,
        "conscientiousness" => 5,
        "extraversion" => 7,
        "neuroticism" => 5,
        "openness" => 4
      },
      "skills" => %{"etiquette" => 20, "insight" => 40, "persuasion" => 40},
      "stats" => %{
        "CHA" => 9,
        "CON" => 11,
        "DEX" => 10,
        "INT" => 11,
        "STR" => 9,
        "WIS" => 10
      }
    },
    {%{"occupation" => "innkeep"}, 99} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "regulars",
          "priority" => 5,
          "text" => "Keep the inn full and the regulars safe"
        }
      ],
      "maslow" => "belonging",
      "ocean" => %{
        "agreeableness" => 5,
        "conscientiousness" => 7,
        "extraversion" => 6,
        "neuroticism" => 6,
        "openness" => 4
      },
      "skills" => %{"etiquette" => 20, "insight" => 40, "persuasion" => 40},
      "stats" => %{
        "CHA" => 10,
        "CON" => 9,
        "DEX" => 11,
        "INT" => 9,
        "STR" => 10,
        "WIS" => 9
      }
    },
    {%{"class" => "wizard", "race" => nil, "standing" => "underclass"}, 1} => %{
      "coins" => %{"copper" => 0, "gold" => 0, "silver" => 5},
      "concerns" => [
        %{
          "focus" => "survival",
          "priority" => 7,
          "text" => "Find food and a roof for the week"
        },
        %{
          "focus" => "wages",
          "priority" => 5,
          "text" => "Get paid for the week's work"
        }
      ],
      "maslow" => "safety",
      "ocean" => %{
        "agreeableness" => 4,
        "conscientiousness" => 6,
        "extraversion" => 4,
        "neuroticism" => 5,
        "openness" => 5
      },
      "skills" => %{
        "arcana" => 15,
        "climbing" => 40,
        "history" => 15,
        "insight" => 15,
        "survival" => 20,
        "unarmed_combat" => 40
      },
      "stats" => %{
        "CHA" => 11,
        "CON" => 9,
        "DEX" => 11,
        "INT" => 12,
        "STR" => 10,
        "WIS" => 12
      }
    },
    {%{"class" => "wizard", "race" => nil, "standing" => "underclass"}, 7} => %{
      "coins" => %{"copper" => 0, "gold" => 0, "silver" => 5},
      "concerns" => [
        %{
          "focus" => "survival",
          "priority" => 7,
          "text" => "Find food and a roof for the week"
        },
        %{
          "focus" => "wages",
          "priority" => 5,
          "text" => "Get paid for the week's work"
        }
      ],
      "maslow" => "safety",
      "ocean" => %{
        "agreeableness" => 5,
        "conscientiousness" => 4,
        "extraversion" => 5,
        "neuroticism" => 5,
        "openness" => 4
      },
      "skills" => %{
        "arcana" => 15,
        "climbing" => 40,
        "history" => 15,
        "insight" => 15,
        "survival" => 20,
        "unarmed_combat" => 40
      },
      "stats" => %{
        "CHA" => 9,
        "CON" => 11,
        "DEX" => 10,
        "INT" => 13,
        "STR" => 9,
        "WIS" => 11
      }
    },
    {%{"class" => "wizard", "race" => nil, "standing" => "underclass"}, 99} => %{
      "coins" => %{"copper" => 0, "gold" => 0, "silver" => 5},
      "concerns" => [
        %{
          "focus" => "survival",
          "priority" => 7,
          "text" => "Find food and a roof for the week"
        },
        %{
          "focus" => "wages",
          "priority" => 5,
          "text" => "Get paid for the week's work"
        }
      ],
      "maslow" => "safety",
      "ocean" => %{
        "agreeableness" => 4,
        "conscientiousness" => 6,
        "extraversion" => 4,
        "neuroticism" => 6,
        "openness" => 4
      },
      "skills" => %{
        "arcana" => 15,
        "climbing" => 40,
        "history" => 15,
        "insight" => 15,
        "survival" => 20,
        "unarmed_combat" => 40
      },
      "stats" => %{
        "CHA" => 10,
        "CON" => 9,
        "DEX" => 11,
        "INT" => 11,
        "STR" => 10,
        "WIS" => 10
      }
    },
    {%{
       "occupation" => "prospector",
       "race" => "dwarf",
       "standing" => "nobility"
     }, 1} => %{
      "coins" => %{"copper" => 0, "gold" => 52, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "profit",
          "priority" => 5,
          "text" => "Strike a vein worth the digging"
        }
      ],
      "maslow" => "physiological",
      "ocean" => %{
        "agreeableness" => 2,
        "conscientiousness" => 8,
        "extraversion" => 4,
        "neuroticism" => 4,
        "openness" => 5
      },
      "skills" => %{
        "climbing" => 40,
        "melee_combat" => 20,
        "survival" => 40,
        "tracking" => 20
      },
      "stats" => %{
        "CHA" => 10,
        "CON" => 11,
        "DEX" => 11,
        "INT" => 10,
        "STR" => 11,
        "WIS" => 11
      }
    },
    {%{
       "occupation" => "prospector",
       "race" => "dwarf",
       "standing" => "nobility"
     }, 7} => %{
      "coins" => %{"copper" => 0, "gold" => 52, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "profit",
          "priority" => 5,
          "text" => "Strike a vein worth the digging"
        }
      ],
      "maslow" => "physiological",
      "ocean" => %{
        "agreeableness" => 3,
        "conscientiousness" => 6,
        "extraversion" => 5,
        "neuroticism" => 4,
        "openness" => 4
      },
      "skills" => %{
        "climbing" => 40,
        "melee_combat" => 20,
        "survival" => 40,
        "tracking" => 20
      },
      "stats" => %{
        "CHA" => 8,
        "CON" => 13,
        "DEX" => 10,
        "INT" => 11,
        "STR" => 10,
        "WIS" => 10
      }
    },
    {%{
       "occupation" => "prospector",
       "race" => "dwarf",
       "standing" => "nobility"
     }, 99} => %{
      "coins" => %{"copper" => 0, "gold" => 52, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "profit",
          "priority" => 5,
          "text" => "Strike a vein worth the digging"
        }
      ],
      "maslow" => "physiological",
      "ocean" => %{
        "agreeableness" => 2,
        "conscientiousness" => 8,
        "extraversion" => 4,
        "neuroticism" => 5,
        "openness" => 4
      },
      "skills" => %{
        "climbing" => 40,
        "melee_combat" => 20,
        "survival" => 40,
        "tracking" => 20
      },
      "stats" => %{
        "CHA" => 9,
        "CON" => 11,
        "DEX" => 11,
        "INT" => 9,
        "STR" => 11,
        "WIS" => 9
      }
    },
    {%{
       "class" => "ranger",
       "occupation" => "hunter",
       "race" => "elf",
       "seniority" => "master"
     }, 1} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "food",
          "priority" => 5,
          "text" => "Bring home enough meat for the winter"
        }
      ],
      "maslow" => "physiological",
      "ocean" => %{
        "agreeableness" => 3,
        "conscientiousness" => 8,
        "extraversion" => 2,
        "neuroticism" => 4,
        "openness" => 7
      },
      "skills" => %{
        "ranged_combat" => 60,
        "stealth" => 30,
        "survival" => 30,
        "tracking" => 60
      },
      "stats" => %{
        "CHA" => 11,
        "CON" => 8,
        "DEX" => 15,
        "INT" => 11,
        "STR" => 10,
        "WIS" => 12
      }
    },
    {%{
       "class" => "ranger",
       "occupation" => "hunter",
       "race" => "elf",
       "seniority" => "master"
     }, 7} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "food",
          "priority" => 5,
          "text" => "Bring home enough meat for the winter"
        }
      ],
      "maslow" => "physiological",
      "ocean" => %{
        "agreeableness" => 4,
        "conscientiousness" => 6,
        "extraversion" => 3,
        "neuroticism" => 4,
        "openness" => 6
      },
      "skills" => %{
        "ranged_combat" => 60,
        "stealth" => 30,
        "survival" => 30,
        "tracking" => 60
      },
      "stats" => %{
        "CHA" => 9,
        "CON" => 10,
        "DEX" => 14,
        "INT" => 12,
        "STR" => 9,
        "WIS" => 11
      }
    },
    {%{
       "class" => "ranger",
       "occupation" => "hunter",
       "race" => "elf",
       "seniority" => "master"
     }, 99} => %{
      "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
      "concerns" => [
        %{
          "focus" => "food",
          "priority" => 5,
          "text" => "Bring home enough meat for the winter"
        }
      ],
      "maslow" => "physiological",
      "ocean" => %{
        "agreeableness" => 3,
        "conscientiousness" => 8,
        "extraversion" => 2,
        "neuroticism" => 5,
        "openness" => 6
      },
      "skills" => %{
        "ranged_combat" => 60,
        "stealth" => 30,
        "survival" => 30,
        "tracking" => 60
      },
      "stats" => %{
        "CHA" => 10,
        "CON" => 8,
        "DEX" => 15,
        "INT" => 10,
        "STR" => 10,
        "WIS" => 10
      }
    }
  },
  drafts: %{
    "default" => %{
      validate: {:error, [name: "type a name"]},
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-default",
        name: "",
        race: "human",
        class: "none",
        occupation: "laborer",
        model: "point_buy",
        base_stats: %{
          "CHA" => 12,
          "CON" => 12,
          "DEX" => 12,
          "INT" => 12,
          "STR" => 12,
          "WIS" => 12
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: nil,
        approved: false,
        race_picks: ["STR", "DEX"],
        skills: %{
          "climbing" => 25,
          "dodge" => 20,
          "lockpicking" => 20,
          "melee_combat" => 20,
          "ranged_combat" => 5,
          "survival" => 25,
          "unarmed_combat" => 20
        },
        edited: MapSet.new([])
      },
      finalize: {:error, [name: "type a name"]},
      final_stats: %{
        "CHA" => 12,
        "CON" => 12,
        "DEX" => 13,
        "INT" => 12,
        "STR" => 13,
        "WIS" => 12
      },
      race_modifiers: %{"DEX" => 1, "STR" => 1},
      points_left: 3,
      free_skills: %{"climbing" => 10, "survival" => 5, "unarmed_combat" => 10},
      skill_levels: %{
        "climbing" => 25,
        "dodge" => 20,
        "lockpicking" => 20,
        "melee_combat" => 20,
        "ranged_combat" => 5,
        "survival" => 25,
        "unarmed_combat" => 20
      },
      skill_budget: 150,
      skill_points_spent: 150,
      signature_skills: [],
      suggested: %{
        "climbing" => 25,
        "dodge" => 20,
        "lockpicking" => 20,
        "melee_combat" => 20,
        "ranged_combat" => 5,
        "survival" => 25,
        "unarmed_combat" => 20
      }
    },
    "dwarf warrior rolled" => %{
      validate: :ok,
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-roll",
        name: "Brokk",
        race: "dwarf",
        class: "warrior",
        occupation: "soldier",
        model: "stat_roll",
        base_stats: %{
          "CHA" => 15,
          "CON" => 15,
          "DEX" => 11,
          "INT" => 12,
          "STR" => 12,
          "WIS" => 11
        },
        rolled_stats: %{
          "CHA" => 15,
          "CON" => 15,
          "DEX" => 11,
          "INT" => 12,
          "STR" => 12,
          "WIS" => 11
        },
        rerolls_left: 1,
        text_labels: nil,
        approved: false,
        race_picks: [],
        skills: %{
          "deception" => 25,
          "etiquette" => 15,
          "intimidation" => 25,
          "ranged_combat" => 25,
          "survival" => 25,
          "tactics" => 25
        },
        edited: MapSet.new([:stats])
      },
      finalize:
        {:ok,
         %{
           "class" => "warrior",
           "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
           "concerns" => [
             %{
               "focus" => "survival",
               "priority" => 5,
               "text" => "Come home from the next campaign"
             }
           ],
           "creation" => %{
             "base_stats" => %{
               "CHA" => 15,
               "CON" => 15,
               "DEX" => 11,
               "INT" => 12,
               "STR" => 12,
               "WIS" => 11
             },
             "derive" => %{
               "occupation" => "soldier",
               "seniority" => "apprentice",
               "standing" => "commoner"
             },
             "model" => "stat_roll",
             "occupation" => "soldier",
             "points_spent" => 76,
             "race_picks" => [],
             "seed_key" => "g-roll",
             "skill_choices" => %{
               "deception" => 25,
               "etiquette" => 15,
               "intimidation" => 25,
               "ranged_combat" => 25,
               "survival" => 25,
               "tactics" => 25
             },
             "skill_points_spent" => 140
           },
           "id" => "pc_brokk",
           "inventory" => [
             %{"id" => "travel_cloak", "name" => "travel cloak", "quantity" => 1},
             %{
               "id" => "hunting_knife",
               "name" => "hunting knife",
               "quantity" => 1
             }
           ],
           "learning_failures" => %{},
           "learning_points" => %{},
           "maslow" => "safety",
           "name" => "Brokk",
           "ocean" => %{
             "agreeableness" => 3,
             "conscientiousness" => 9,
             "extraversion" => 5,
             "neuroticism" => 3,
             "openness" => 4
           },
           "race" => "dwarf",
           "skills" => %{
             "deception" => 25,
             "etiquette" => 15,
             "intimidation" => 25,
             "melee_combat" => 35,
             "ranged_combat" => 25,
             "survival" => 25,
             "tactics" => 25
           },
           "stats" => %{
             "CHA" => 14,
             "CON" => 17,
             "DEX" => 11,
             "INT" => 12,
             "STR" => 13,
             "WIS" => 11
           },
           "vitality" => "ok",
           "wound_max" => 6,
           "wounds" => 0
         }},
      final_stats: %{
        "CHA" => 14,
        "CON" => 17,
        "DEX" => 11,
        "INT" => 12,
        "STR" => 13,
        "WIS" => 11
      },
      race_modifiers: %{"CHA" => -1, "CON" => 2, "STR" => 1},
      points_left: -1,
      free_skills: %{
        "intimidation" => 5,
        "melee_combat" => 35,
        "ranged_combat" => 5,
        "survival" => 15,
        "tactics" => 20
      },
      skill_levels: %{
        "deception" => 25,
        "etiquette" => 15,
        "intimidation" => 25,
        "melee_combat" => 35,
        "ranged_combat" => 25,
        "survival" => 25,
        "tactics" => 25
      },
      skill_budget: 140,
      skill_points_spent: 140,
      signature_skills: ["melee_combat"],
      suggested: %{
        "deception" => 25,
        "etiquette" => 15,
        "intimidation" => 25,
        "ranged_combat" => 25,
        "survival" => 25,
        "tactics" => 25
      }
    },
    "elf ranger hunter" => %{
      validate: {:error, [stats: "75 points at most; 77 spent"]},
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-elf",
        name: "Mira Vale",
        race: "elf",
        class: "ranger",
        occupation: "hunter",
        model: "point_buy",
        base_stats: %{
          "CHA" => 12,
          "CON" => 12,
          "DEX" => 16,
          "INT" => 12,
          "STR" => 12,
          "WIS" => 13
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: nil,
        approved: false,
        race_picks: ["WIS"],
        skills: %{
          "arcana" => 5,
          "dodge" => 25,
          "insight" => 15,
          "lockpicking" => 25,
          "stealth" => 20,
          "survival" => 25,
          "tracking" => 25
        },
        edited: MapSet.new([:stats, :skills, :occupation])
      },
      finalize: {:error, [stats: "75 points at most; 77 spent"]},
      final_stats: %{
        "CHA" => 12,
        "CON" => 11,
        "DEX" => 18,
        "INT" => 12,
        "STR" => 12,
        "WIS" => 14
      },
      race_modifiers: %{"CON" => -1, "DEX" => 2, "WIS" => 1},
      points_left: -2,
      free_skills: %{
        "ranged_combat" => 35,
        "stealth" => 5,
        "survival" => 20,
        "tracking" => 20
      },
      skill_levels: %{
        "arcana" => 5,
        "dodge" => 25,
        "insight" => 15,
        "lockpicking" => 25,
        "ranged_combat" => 35,
        "stealth" => 20,
        "survival" => 25,
        "tracking" => 25
      },
      skill_budget: 140,
      skill_points_spent: 130,
      signature_skills: ["ranged_combat"],
      suggested: %{
        "arcana" => 5,
        "dodge" => 25,
        "insight" => 15,
        "lockpicking" => 25,
        "stealth" => 25,
        "survival" => 25,
        "tracking" => 25
      }
    },
    "from text approved" => %{
      validate: :ok,
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-text",
        name: "Tam",
        race: "halfling",
        class: "none",
        occupation: "thief",
        model: "from_text",
        base_stats: %{
          "CHA" => 17,
          "CON" => 12,
          "DEX" => 16,
          "INT" => 12,
          "STR" => 4,
          "WIS" => 12
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: %{
          "class" => %TalesForge.CharacterCreation.FromText.Label{
            value: "thief",
            confidence: 0.4
          },
          "name" => %TalesForge.CharacterCreation.FromText.Label{
            value: "Tam",
            confidence: 0.9
          },
          "occupation" => %TalesForge.CharacterCreation.FromText.Label{
            value: "thief",
            confidence: 0.9
          },
          "race" => %TalesForge.CharacterCreation.FromText.Label{
            value: "halfling",
            confidence: 0.8
          },
          "skills" => %TalesForge.CharacterCreation.FromText.Label{
            value: %{"lockpicking" => 30, "stealth" => 35},
            confidence: 0.9
          },
          "stats" => %TalesForge.CharacterCreation.FromText.Label{
            value: %{"CHA" => 17, "DEX" => 18, "STR" => 3},
            confidence: 0.9
          }
        },
        approved: true,
        race_picks: [],
        skills: %{
          "deception" => 25,
          "dodge" => 25,
          "etiquette" => 20,
          "intimidation" => 20,
          "lockpicking" => 25,
          "persuasion" => 5
        },
        edited: MapSet.new([:stats, :occupation])
      },
      finalize:
        {:ok,
         %{
           "class" => "none",
           "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
           "concerns" => [
             %{
               "focus" => "freedom",
               "priority" => 6,
               "text" => "Stay one step ahead of the law"
             }
           ],
           "creation" => %{
             "base_stats" => %{
               "CHA" => 17,
               "CON" => 12,
               "DEX" => 16,
               "INT" => 12,
               "STR" => 4,
               "WIS" => 12
             },
             "derive" => %{
               "occupation" => "thief",
               "seniority" => "apprentice",
               "standing" => "commoner"
             },
             "model" => "from_text",
             "occupation" => "thief",
             "points_spent" => 73,
             "race_picks" => [],
             "seed_key" => "g-text",
             "skill_choices" => %{
               "deception" => 25,
               "dodge" => 25,
               "etiquette" => 20,
               "intimidation" => 20,
               "lockpicking" => 25,
               "persuasion" => 5
             },
             "skill_points_spent" => 125
           },
           "id" => "pc_tam",
           "inventory" => [
             %{"id" => "travel_cloak", "name" => "travel cloak", "quantity" => 1},
             %{
               "id" => "hunting_knife",
               "name" => "hunting knife",
               "quantity" => 1
             }
           ],
           "learning_failures" => %{},
           "learning_points" => %{},
           "maslow" => "safety",
           "name" => "Tam",
           "ocean" => %{
             "agreeableness" => 5,
             "conscientiousness" => 3,
             "extraversion" => 8,
             "neuroticism" => 5,
             "openness" => 8
           },
           "race" => "halfling",
           "skills" => %{
             "deception" => 25,
             "dodge" => 25,
             "etiquette" => 20,
             "intimidation" => 20,
             "lockpicking" => 25,
             "persuasion" => 5,
             "stealth" => 25
           },
           "stats" => %{
             "CHA" => 18,
             "CON" => 12,
             "DEX" => 18,
             "INT" => 12,
             "STR" => 3,
             "WIS" => 12
           },
           "vitality" => "ok",
           "wound_max" => 4,
           "wounds" => 0
         }},
      final_stats: %{
        "CHA" => 18,
        "CON" => 12,
        "DEX" => 18,
        "INT" => 12,
        "STR" => 3,
        "WIS" => 12
      },
      race_modifiers: %{"CHA" => 1, "DEX" => 2, "STR" => -1},
      points_left: 2,
      free_skills: %{
        "deception" => 5,
        "dodge" => 5,
        "lockpicking" => 20,
        "stealth" => 25
      },
      skill_levels: %{
        "deception" => 25,
        "dodge" => 25,
        "etiquette" => 20,
        "intimidation" => 20,
        "lockpicking" => 25,
        "persuasion" => 5,
        "stealth" => 25
      },
      skill_budget: 125,
      skill_points_spent: 125,
      signature_skills: [],
      suggested: %{
        "deception" => 25,
        "dodge" => 25,
        "etiquette" => 20,
        "intimidation" => 20,
        "lockpicking" => 25,
        "persuasion" => 5
      }
    },
    "from text unapproved" => %{
      validate: {:error, [approval: "approve the AI draft before play"]},
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-text",
        name: "Tam",
        race: "halfling",
        class: "none",
        occupation: "thief",
        model: "from_text",
        base_stats: %{
          "CHA" => 17,
          "CON" => 12,
          "DEX" => 16,
          "INT" => 12,
          "STR" => 4,
          "WIS" => 12
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: %{
          "class" => %TalesForge.CharacterCreation.FromText.Label{
            value: "thief",
            confidence: 0.4
          },
          "name" => %TalesForge.CharacterCreation.FromText.Label{
            value: "Tam",
            confidence: 0.9
          },
          "occupation" => %TalesForge.CharacterCreation.FromText.Label{
            value: "thief",
            confidence: 0.9
          },
          "race" => %TalesForge.CharacterCreation.FromText.Label{
            value: "halfling",
            confidence: 0.8
          },
          "skills" => %TalesForge.CharacterCreation.FromText.Label{
            value: %{"lockpicking" => 30, "stealth" => 35},
            confidence: 0.9
          },
          "stats" => %TalesForge.CharacterCreation.FromText.Label{
            value: %{"CHA" => 17, "DEX" => 18, "STR" => 3},
            confidence: 0.9
          }
        },
        approved: false,
        race_picks: [],
        skills: %{
          "deception" => 25,
          "dodge" => 25,
          "etiquette" => 20,
          "intimidation" => 20,
          "lockpicking" => 25,
          "persuasion" => 5
        },
        edited: MapSet.new([:stats, :occupation])
      },
      finalize: {:error, [approval: "approve the AI draft before play"]},
      final_stats: %{
        "CHA" => 18,
        "CON" => 12,
        "DEX" => 18,
        "INT" => 12,
        "STR" => 3,
        "WIS" => 12
      },
      race_modifiers: %{"CHA" => 1, "DEX" => 2, "STR" => -1},
      points_left: 2,
      free_skills: %{
        "deception" => 5,
        "dodge" => 5,
        "lockpicking" => 20,
        "stealth" => 25
      },
      skill_levels: %{
        "deception" => 25,
        "dodge" => 25,
        "etiquette" => 20,
        "intimidation" => 20,
        "lockpicking" => 25,
        "persuasion" => 5,
        "stealth" => 25
      },
      skill_budget: 125,
      skill_points_spent: 125,
      signature_skills: [],
      suggested: %{
        "deception" => 25,
        "dodge" => 25,
        "etiquette" => 20,
        "intimidation" => 20,
        "lockpicking" => 25,
        "persuasion" => 5
      }
    },
    "half-elf picks" => %{
      validate: :ok,
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-half",
        name: "Ilse",
        race: "half_elf",
        class: "wizard",
        occupation: "scholar",
        model: "point_buy",
        base_stats: %{
          "CHA" => 12,
          "CON" => 12,
          "DEX" => 12,
          "INT" => 14,
          "STR" => 12,
          "WIS" => 13
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: nil,
        approved: false,
        race_picks: [],
        skills: %{
          "deception" => 25,
          "dodge" => 25,
          "history" => 25,
          "insight" => 25,
          "tactics" => 25
        },
        edited: MapSet.new([])
      },
      finalize:
        {:ok,
         %{
           "class" => "wizard",
           "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
           "concerns" => [
             %{
               "focus" => "knowledge",
               "priority" => 5,
               "text" => "Find the missing piece of the research"
             }
           ],
           "creation" => %{
             "base_stats" => %{
               "CHA" => 12,
               "CON" => 12,
               "DEX" => 12,
               "INT" => 14,
               "STR" => 12,
               "WIS" => 13
             },
             "derive" => %{
               "occupation" => "scholar",
               "seniority" => "apprentice",
               "standing" => "commoner"
             },
             "model" => "point_buy",
             "occupation" => "scholar",
             "points_spent" => 75,
             "race_picks" => [],
             "seed_key" => "g-half",
             "skill_choices" => %{
               "deception" => 25,
               "dodge" => 25,
               "history" => 25,
               "insight" => 25,
               "tactics" => 25
             },
             "skill_points_spent" => 140
           },
           "id" => "pc_ilse",
           "inventory" => [
             %{"id" => "travel_cloak", "name" => "travel cloak", "quantity" => 1},
             %{
               "id" => "hunting_knife",
               "name" => "hunting knife",
               "quantity" => 1
             }
           ],
           "learning_failures" => %{},
           "learning_points" => %{},
           "maslow" => "esteem",
           "name" => "Ilse",
           "ocean" => %{
             "agreeableness" => 6,
             "conscientiousness" => 5,
             "extraversion" => 5,
             "neuroticism" => 6,
             "openness" => 8
           },
           "race" => "half_elf",
           "skills" => %{
             "arcana" => 25,
             "deception" => 25,
             "dodge" => 25,
             "history" => 25,
             "insight" => 25,
             "tactics" => 25
           },
           "stats" => %{
             "CHA" => 13,
             "CON" => 12,
             "DEX" => 13,
             "INT" => 14,
             "STR" => 12,
             "WIS" => 13
           },
           "vitality" => "ok",
           "wound_max" => 4,
           "wounds" => 0
         }},
      final_stats: %{
        "CHA" => 13,
        "CON" => 12,
        "DEX" => 13,
        "INT" => 14,
        "STR" => 12,
        "WIS" => 13
      },
      race_modifiers: %{"CHA" => 1, "DEX" => 1},
      points_left: 0,
      free_skills: %{"arcana" => 25, "history" => 20, "insight" => 10},
      skill_levels: %{
        "arcana" => 25,
        "deception" => 25,
        "dodge" => 25,
        "history" => 25,
        "insight" => 25,
        "tactics" => 25
      },
      skill_budget: 140,
      skill_points_spent: 140,
      signature_skills: [],
      suggested: %{
        "deception" => 25,
        "dodge" => 25,
        "history" => 25,
        "insight" => 25,
        "tactics" => 25
      }
    },
    "many errors" => %{
      validate:
        {:error,
         [
           name: "type a name",
           stats: "75 points at most; 108 spent",
           stats: "CHA would be 19 after the half_elf modifier (+1); it must be 3–18",
           stats: "DEX would be 19 after the half_elf modifier (+1); it must be 3–18",
           skills: "140 skill points at most; 230 spent",
           skills: "a skill goes up to 35 at most",
           skills: "choose at least 5 skills; 4 so far"
         ]},
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-bad",
        name: "",
        race: "half_elf",
        class: "none",
        occupation: "laborer",
        model: "point_buy",
        base_stats: %{
          "CHA" => 18,
          "CON" => 18,
          "DEX" => 18,
          "INT" => 18,
          "STR" => 18,
          "WIS" => 18
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: nil,
        approved: false,
        race_picks: ["STR"],
        skills: %{"stealth" => 90},
        edited: MapSet.new([])
      },
      finalize:
        {:error,
         [
           name: "type a name",
           stats: "75 points at most; 108 spent",
           stats: "CHA would be 19 after the half_elf modifier (+1); it must be 3–18",
           stats: "DEX would be 19 after the half_elf modifier (+1); it must be 3–18",
           skills: "140 skill points at most; 230 spent",
           skills: "a skill goes up to 35 at most",
           skills: "choose at least 5 skills; 4 so far"
         ]},
      final_stats: %{
        "CHA" => 19,
        "CON" => 18,
        "DEX" => 19,
        "INT" => 18,
        "STR" => 18,
        "WIS" => 18
      },
      race_modifiers: %{"CHA" => 1, "DEX" => 1},
      points_left: -33,
      free_skills: %{"climbing" => 10, "survival" => 5, "unarmed_combat" => 10},
      skill_levels: %{
        "climbing" => 10,
        "stealth" => 90,
        "survival" => 5,
        "unarmed_combat" => 10
      },
      skill_budget: 140,
      skill_points_spent: 230,
      signature_skills: ["stealth"],
      suggested: %{
        "climbing" => 25,
        "deception" => 20,
        "dodge" => 20,
        "etiquette" => 20,
        "intimidation" => 5,
        "survival" => 20,
        "unarmed_combat" => 20
      }
    },
    "named human" => %{
      validate: :ok,
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-human",
        name: "Ada Lovelace",
        race: "human",
        class: "none",
        occupation: "laborer",
        model: "point_buy",
        base_stats: %{
          "CHA" => 12,
          "CON" => 12,
          "DEX" => 12,
          "INT" => 12,
          "STR" => 12,
          "WIS" => 12
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: nil,
        approved: false,
        race_picks: ["STR", "DEX"],
        skills: %{
          "climbing" => 25,
          "dodge" => 20,
          "lockpicking" => 20,
          "melee_combat" => 20,
          "ranged_combat" => 5,
          "survival" => 25,
          "unarmed_combat" => 20
        },
        edited: MapSet.new([])
      },
      finalize:
        {:ok,
         %{
           "class" => "none",
           "coins" => %{"copper" => 0, "gold" => 1, "silver" => 0},
           "concerns" => [
             %{
               "focus" => "wages",
               "priority" => 5,
               "text" => "Get paid for the week's work"
             }
           ],
           "creation" => %{
             "base_stats" => %{
               "CHA" => 12,
               "CON" => 12,
               "DEX" => 12,
               "INT" => 12,
               "STR" => 12,
               "WIS" => 12
             },
             "derive" => %{
               "occupation" => "laborer",
               "seniority" => "apprentice",
               "standing" => "commoner"
             },
             "model" => "point_buy",
             "occupation" => "laborer",
             "points_spent" => 72,
             "race_picks" => ["STR", "DEX"],
             "seed_key" => "g-human",
             "skill_choices" => %{
               "climbing" => 25,
               "dodge" => 20,
               "lockpicking" => 20,
               "melee_combat" => 20,
               "ranged_combat" => 5,
               "survival" => 25,
               "unarmed_combat" => 20
             },
             "skill_points_spent" => 150
           },
           "id" => "pc_ada_lovelace",
           "inventory" => [
             %{"id" => "travel_cloak", "name" => "travel cloak", "quantity" => 1},
             %{
               "id" => "hunting_knife",
               "name" => "hunting knife",
               "quantity" => 1
             }
           ],
           "learning_failures" => %{},
           "learning_points" => %{},
           "maslow" => "safety",
           "name" => "Ada Lovelace",
           "ocean" => %{
             "agreeableness" => 5,
             "conscientiousness" => 4,
             "extraversion" => 6,
             "neuroticism" => 6,
             "openness" => 4
           },
           "race" => "human",
           "skills" => %{
             "climbing" => 25,
             "dodge" => 20,
             "lockpicking" => 20,
             "melee_combat" => 20,
             "ranged_combat" => 5,
             "survival" => 25,
             "unarmed_combat" => 20
           },
           "stats" => %{
             "CHA" => 12,
             "CON" => 12,
             "DEX" => 13,
             "INT" => 12,
             "STR" => 13,
             "WIS" => 12
           },
           "vitality" => "ok",
           "wound_max" => 4,
           "wounds" => 0
         }},
      final_stats: %{
        "CHA" => 12,
        "CON" => 12,
        "DEX" => 13,
        "INT" => 12,
        "STR" => 13,
        "WIS" => 12
      },
      race_modifiers: %{"DEX" => 1, "STR" => 1},
      points_left: 3,
      free_skills: %{"climbing" => 10, "survival" => 5, "unarmed_combat" => 10},
      skill_levels: %{
        "climbing" => 25,
        "dodge" => 20,
        "lockpicking" => 20,
        "melee_combat" => 20,
        "ranged_combat" => 5,
        "survival" => 25,
        "unarmed_combat" => 20
      },
      skill_budget: 150,
      skill_points_spent: 150,
      signature_skills: [],
      suggested: %{
        "climbing" => 25,
        "dodge" => 20,
        "lockpicking" => 20,
        "melee_combat" => 20,
        "ranged_combat" => 5,
        "survival" => 25,
        "unarmed_combat" => 20
      }
    },
    "rolled then edited" => %{
      validate: {:error, [stats: "the stats must be the rolled stats"]},
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-roll",
        name: "Brokk",
        race: "dwarf",
        class: "warrior",
        occupation: "soldier",
        model: "stat_roll",
        base_stats: %{
          "CHA" => 15,
          "CON" => 15,
          "DEX" => 11,
          "INT" => 12,
          "STR" => 3,
          "WIS" => 11
        },
        rolled_stats: %{
          "CHA" => 15,
          "CON" => 15,
          "DEX" => 11,
          "INT" => 12,
          "STR" => 12,
          "WIS" => 11
        },
        rerolls_left: 0,
        text_labels: nil,
        approved: false,
        race_picks: [],
        skills: %{
          "deception" => 25,
          "etiquette" => 15,
          "intimidation" => 25,
          "ranged_combat" => 25,
          "survival" => 25,
          "tactics" => 25
        },
        edited: MapSet.new([:stats])
      },
      finalize: {:error, [stats: "the stats must be the rolled stats"]},
      final_stats: %{
        "CHA" => 14,
        "CON" => 17,
        "DEX" => 11,
        "INT" => 12,
        "STR" => 4,
        "WIS" => 11
      },
      race_modifiers: %{"CHA" => -1, "CON" => 2, "STR" => 1},
      points_left: 8,
      free_skills: %{
        "intimidation" => 5,
        "melee_combat" => 35,
        "ranged_combat" => 5,
        "survival" => 15,
        "tactics" => 20
      },
      skill_levels: %{
        "deception" => 25,
        "etiquette" => 15,
        "intimidation" => 25,
        "melee_combat" => 35,
        "ranged_combat" => 25,
        "survival" => 25,
        "tactics" => 25
      },
      skill_budget: 140,
      skill_points_spent: 140,
      signature_skills: ["melee_combat"],
      suggested: %{
        "deception" => 25,
        "etiquette" => 15,
        "intimidation" => 25,
        "ranged_combat" => 25,
        "survival" => 25,
        "tactics" => 25
      }
    },
    "skills over the caps" => %{
      validate:
        {:error,
         [
           skills: "150 skill points at most; 425 spent",
           skills: "2 signature skills at most (above 25); 4 chosen",
           skills: "a skill goes up to 35 at most"
         ]},
      draft: %TalesForge.CharacterCreation.Draft{
        adventure_id: "tin_valley",
        seed_key: "g-caps",
        name: "Cap",
        race: "human",
        class: "none",
        occupation: "laborer",
        model: "point_buy",
        base_stats: %{
          "CHA" => 12,
          "CON" => 12,
          "DEX" => 12,
          "INT" => 12,
          "STR" => 12,
          "WIS" => 12
        },
        rolled_stats: nil,
        rerolls_left: 0,
        text_labels: nil,
        approved: false,
        race_picks: ["STR", "DEX"],
        skills: %{
          "arcana" => 45,
          "history" => 60,
          "lockpicking" => 45,
          "stealth" => 45
        },
        edited: MapSet.new([])
      },
      finalize:
        {:error,
         [
           skills: "150 skill points at most; 425 spent",
           skills: "2 signature skills at most (above 25); 4 chosen",
           skills: "a skill goes up to 35 at most"
         ]},
      final_stats: %{
        "CHA" => 12,
        "CON" => 12,
        "DEX" => 13,
        "INT" => 12,
        "STR" => 13,
        "WIS" => 12
      },
      race_modifiers: %{"DEX" => 1, "STR" => 1},
      points_left: 3,
      free_skills: %{"climbing" => 10, "survival" => 5, "unarmed_combat" => 10},
      skill_levels: %{
        "arcana" => 45,
        "climbing" => 10,
        "history" => 60,
        "lockpicking" => 45,
        "stealth" => 45,
        "survival" => 5,
        "unarmed_combat" => 10
      },
      skill_budget: 150,
      skill_points_spent: 425,
      signature_skills: ["arcana", "history", "lockpicking", "stealth"],
      suggested: %{
        "climbing" => 25,
        "dodge" => 20,
        "lockpicking" => 20,
        "melee_combat" => 20,
        "ranged_combat" => 5,
        "survival" => 25,
        "unarmed_combat" => 20
      }
    }
  },
  race_picks: %{
    {"dwarf", []} => {:error, {:race_picks, "dwarf has no stat choice"}},
    {"dwarf", ["INT"]} => {:error, {:race_picks, "dwarf has no stat choice"}},
    {"dwarf", ["LUCK"]} => {:error, {:race_picks, "dwarf has no stat choice"}},
    {"dwarf", ["STR"]} => {:error, {:race_picks, "dwarf has no stat choice"}},
    {"dwarf", ["STR", "DEX"]} => {:error, {:race_picks, "dwarf has no stat choice"}},
    {"dwarf", ["STR", "STR"]} => {:error, {:race_picks, "dwarf has no stat choice"}},
    {"dwarf", ["WIS"]} => {:error, {:race_picks, "dwarf has no stat choice"}},
    {"elf", []} => {:error, {:race_picks, "choose 1 different stats for the elf bonus"}},
    {"elf", ["INT"]} =>
      {:ok,
       %TalesForge.CharacterCreation.Draft{
         adventure_id: "tin_valley",
         seed_key: "g-picks",
         name: "",
         race: "elf",
         class: "none",
         occupation: "laborer",
         model: "point_buy",
         base_stats: %{
           "CHA" => 12,
           "CON" => 12,
           "DEX" => 12,
           "INT" => 12,
           "STR" => 12,
           "WIS" => 12
         },
         rolled_stats: nil,
         rerolls_left: 0,
         text_labels: nil,
         approved: false,
         race_picks: ["INT"],
         skills: %{
           "climbing" => 20,
           "dodge" => 20,
           "lockpicking" => 20,
           "ranged_combat" => 25,
           "stealth" => 5,
           "survival" => 25,
           "unarmed_combat" => 20
         },
         edited: MapSet.new([:race_picks])
       }},
    {"elf", ["LUCK"]} => {:error, {:race_picks, "the elf bonus goes to INT or WIS"}},
    {"elf", ["STR"]} => {:error, {:race_picks, "the elf bonus goes to INT or WIS"}},
    {"elf", ["STR", "DEX"]} =>
      {:error, {:race_picks, "choose 1 different stats for the elf bonus"}},
    {"elf", ["STR", "STR"]} =>
      {:error, {:race_picks, "choose 1 different stats for the elf bonus"}},
    {"elf", ["WIS"]} =>
      {:ok,
       %TalesForge.CharacterCreation.Draft{
         adventure_id: "tin_valley",
         seed_key: "g-picks",
         name: "",
         race: "elf",
         class: "none",
         occupation: "laborer",
         model: "point_buy",
         base_stats: %{
           "CHA" => 12,
           "CON" => 12,
           "DEX" => 12,
           "INT" => 12,
           "STR" => 12,
           "WIS" => 12
         },
         rolled_stats: nil,
         rerolls_left: 0,
         text_labels: nil,
         approved: false,
         race_picks: ["WIS"],
         skills: %{
           "climbing" => 20,
           "dodge" => 20,
           "lockpicking" => 20,
           "ranged_combat" => 25,
           "stealth" => 5,
           "survival" => 25,
           "unarmed_combat" => 20
         },
         edited: MapSet.new([:race_picks])
       }},
    {"half_elf", []} => {:error, {:race_picks, "half_elf has no stat choice"}},
    {"half_elf", ["INT"]} => {:error, {:race_picks, "half_elf has no stat choice"}},
    {"half_elf", ["LUCK"]} => {:error, {:race_picks, "half_elf has no stat choice"}},
    {"half_elf", ["STR"]} => {:error, {:race_picks, "half_elf has no stat choice"}},
    {"half_elf", ["STR", "DEX"]} => {:error, {:race_picks, "half_elf has no stat choice"}},
    {"half_elf", ["STR", "STR"]} => {:error, {:race_picks, "half_elf has no stat choice"}},
    {"half_elf", ["WIS"]} => {:error, {:race_picks, "half_elf has no stat choice"}},
    {"human", []} => {:error, {:race_picks, "choose 2 different stats for the human bonus"}},
    {"human", ["INT"]} => {:error, {:race_picks, "choose 2 different stats for the human bonus"}},
    {"human", ["LUCK"]} =>
      {:error, {:race_picks, "choose 2 different stats for the human bonus"}},
    {"human", ["STR"]} => {:error, {:race_picks, "choose 2 different stats for the human bonus"}},
    {"human", ["STR", "DEX"]} =>
      {:ok,
       %TalesForge.CharacterCreation.Draft{
         adventure_id: "tin_valley",
         seed_key: "g-picks",
         name: "",
         race: "human",
         class: "none",
         occupation: "laborer",
         model: "point_buy",
         base_stats: %{
           "CHA" => 12,
           "CON" => 12,
           "DEX" => 12,
           "INT" => 12,
           "STR" => 12,
           "WIS" => 12
         },
         rolled_stats: nil,
         rerolls_left: 0,
         text_labels: nil,
         approved: false,
         race_picks: ["STR", "DEX"],
         skills: %{
           "climbing" => 25,
           "dodge" => 20,
           "lockpicking" => 20,
           "melee_combat" => 20,
           "ranged_combat" => 5,
           "survival" => 25,
           "unarmed_combat" => 20
         },
         edited: MapSet.new([:race_picks])
       }},
    {"human", ["STR", "STR"]} =>
      {:error, {:race_picks, "choose 2 different stats for the human bonus"}},
    {"human", ["WIS"]} => {:error, {:race_picks, "choose 2 different stats for the human bonus"}}
  }
}
