# Captured from CharacterCreation.options("tin_valley") at origin/main 5f4a75f.
# Characterization fixture: regenerate only for an intended behaviour change.
%{
  skills: %{
    "budget" => 125,
    "cap" => 25,
    "class_package" => [15, 10, 5],
    "level_costs" => [1, 1, 1, 2, 2, 3, 3],
    "level_step" => 5,
    "min_skills" => 5,
    "race_bonuses" => %{
      "dwarf" => %{"fixed" => %{"melee_combat" => 15, "survival" => 10}},
      "elf" => %{"fixed" => %{"ranged_combat" => 15, "survival" => 10}},
      "gnome" => %{"fixed" => %{"arcana" => 15, "lockpicking" => 10}},
      "half_elf" => %{"pool" => 15},
      "halfling" => %{"fixed" => %{"lockpicking" => 10, "stealth" => 15}},
      "human" => %{"pool" => 25}
    },
    "signature_cap" => 35,
    "signature_max" => 2
  },
  classes: [
    %{
      id: "none",
      description: "No trade of arms or magic: your past and your choices speak for you.",
      stats: %{},
      occupation: "laborer",
      skills: %{}
    },
    %{
      id: "cleric",
      description: "A voice of faith: insight, persuasion and old stories.",
      stats: %{"CHA" => 1, "WIS" => 2},
      occupation: "priest",
      skills: %{"history" => 5, "insight" => 15, "persuasion" => 10}
    },
    %{
      id: "druid",
      description: "Bound to the land: survival, arcana and tracking.",
      stats: %{"CON" => 1, "WIS" => 2},
      occupation: "hunter",
      skills: %{"arcana" => 10, "survival" => 15, "tracking" => 5}
    },
    %{
      id: "ranger",
      description: "At home in the wild: bow, tracks and survival.",
      stats: %{"DEX" => 2, "WIS" => 1},
      occupation: "hunter",
      skills: %{"ranged_combat" => 15, "survival" => 5, "tracking" => 10}
    },
    %{
      id: "thief",
      description: "Quiet hands and a quick tongue: stealth, locks and lies.",
      stats: %{"DEX" => 2, "INT" => 1},
      occupation: "thief",
      skills: %{"deception" => 5, "lockpicking" => 10, "stealth" => 15}
    },
    %{
      id: "warrior",
      description: "Trained to fight: melee, tactics and a hard stare.",
      stats: %{"CON" => 1, "STR" => 2},
      occupation: "soldier",
      skills: %{"intimidation" => 5, "melee_combat" => 15, "tactics" => 10}
    },
    %{
      id: "wizard",
      description: "A student of the arcane: arcana, history and insight.",
      stats: %{"INT" => 2, "WIS" => 1},
      occupation: "scholar",
      skills: %{"arcana" => 15, "history" => 10, "insight" => 5}
    }
  ],
  name_max_length: 40,
  occupations: [
    %{
      id: "laborer",
      description: "Hauled, dug and built for a day's wage.",
      skills: %{"climbing" => 10, "survival" => 5, "unarmed_combat" => 10}
    },
    %{
      id: "innkeep",
      description: "Kept an inn: rooms, rumours and regulars.",
      skills: %{"etiquette" => 5, "insight" => 10, "persuasion" => 10}
    },
    %{
      id: "barkeep",
      description: "Poured drinks and kept the peace across the bar.",
      skills: %{
        "insight" => 10,
        "intimidation" => 5,
        "persuasion" => 10,
        "unarmed_combat" => 5
      }
    },
    %{
      id: "merchant",
      description: "Bought cheap, sold dear and read every buyer.",
      skills: %{
        "deception" => 10,
        "etiquette" => 5,
        "insight" => 5,
        "persuasion" => 10
      }
    },
    %{
      id: "guard",
      description: "Stood watch on a gate, a wall or someone important.",
      skills: %{
        "insight" => 5,
        "intimidation" => 10,
        "melee_combat" => 10,
        "tactics" => 5
      }
    },
    %{
      id: "soldier",
      description: "Marched, drilled and fought in someone's war.",
      skills: %{
        "melee_combat" => 10,
        "ranged_combat" => 5,
        "survival" => 5,
        "tactics" => 10
      }
    },
    %{
      id: "hunter",
      description: "Tracked game through the wilds to feed a village.",
      skills: %{
        "ranged_combat" => 10,
        "stealth" => 5,
        "survival" => 5,
        "tracking" => 10
      }
    },
    %{
      id: "miner",
      description: "Worked the dark seams under the hills.",
      skills: %{"climbing" => 10, "melee_combat" => 10, "survival" => 5}
    },
    %{
      id: "priest",
      description: "Served a temple, its rites and its people.",
      skills: %{
        "etiquette" => 5,
        "history" => 10,
        "insight" => 10,
        "persuasion" => 5
      }
    },
    %{
      id: "scholar",
      description: "Studied old books, older languages and stranger lore.",
      skills: %{"arcana" => 10, "history" => 10, "insight" => 5}
    },
    %{
      id: "thief",
      description: "Lived off locks, pockets and shadows.",
      skills: %{
        "deception" => 5,
        "dodge" => 5,
        "lockpicking" => 10,
        "stealth" => 10
      }
    },
    %{
      id: "noble",
      description: "Grew up at court among titles, manners and feuds.",
      skills: %{
        "etiquette" => 10,
        "history" => 5,
        "insight" => 5,
        "persuasion" => 10
      }
    }
  ],
  point_buy: %{"budget" => 75, "max" => 18, "min" => 3},
  races: [
    %{
      id: "human",
      description:
        "Versatile and resilient; humans adapt quickly, thriving on trial and error. +1 to any two stats, +5 skill points.",
      choice: %{
        "amount" => 1,
        "count" => 2,
        "from" => ["STR", "DEX", "CON", "INT", "WIS", "CHA"],
        "replaces" => %{}
      },
      stats: %{},
      skill_bonus: %{"pool" => 25}
    },
    %{
      id: "dwarf",
      description:
        "Sturdy craftsfolk who endure harsh conditions. +2 CON, +1 STR, -1 CHA; Melee Combat +3, Survival +2.",
      choice: nil,
      stats: %{"CHA" => -1, "CON" => 2, "STR" => 1},
      skill_bonus: %{"fixed" => %{"melee_combat" => 15, "survival" => 10}}
    },
    %{
      id: "elf",
      description:
        "Graceful, long-lived and attuned to nature and magic. +2 DEX, +1 INT or WIS, -1 CON; Ranged Combat +3, Survival +2.",
      choice: %{
        "amount" => 1,
        "count" => 1,
        "from" => ["INT", "WIS"],
        "replaces" => %{"INT" => 1}
      },
      stats: %{"CON" => -1, "DEX" => 2, "INT" => 1},
      skill_bonus: %{"fixed" => %{"ranged_combat" => 15, "survival" => 10}}
    },
    %{
      id: "gnome",
      description:
        "Curious tinkerers who treat failures as experiments. +2 INT, +1 DEX, -1 STR; Arcana +3, Lockpicking +2.",
      choice: nil,
      stats: %{"DEX" => 1, "INT" => 2, "STR" => -1},
      skill_bonus: %{"fixed" => %{"arcana" => 15, "lockpicking" => 10}}
    },
    %{
      id: "half_elf",
      description:
        "Bridging two worlds, with human adaptability and elven grace. +1 DEX, +1 CHA, +3 skill points.",
      choice: nil,
      stats: %{"CHA" => 1, "DEX" => 1},
      skill_bonus: %{"pool" => 15}
    },
    %{
      id: "halfling",
      description:
        "Cheerful, social and lucky in danger. +2 DEX, +1 CHA, -1 STR; Stealth +3, Lockpicking +2.",
      choice: nil,
      stats: %{"CHA" => 1, "DEX" => 2, "STR" => -1},
      skill_bonus: %{"fixed" => %{"lockpicking" => 10, "stealth" => 15}}
    }
  ],
  skill_list: [
    %{id: "arcana", stat: "INT"},
    %{id: "climbing", stat: "STR"},
    %{id: "deception", stat: "CHA"},
    %{id: "dodge", stat: "DEX"},
    %{id: "etiquette", stat: "CHA"},
    %{id: "history", stat: "INT"},
    %{id: "insight", stat: "WIS"},
    %{id: "intimidation", stat: "CHA"},
    %{id: "lockpicking", stat: "DEX"},
    %{id: "melee_combat", stat: "STR"},
    %{id: "persuasion", stat: "CHA"},
    %{id: "ranged_combat", stat: "DEX"},
    %{id: "stealth", stat: "DEX"},
    %{id: "survival", stat: "CON"},
    %{id: "tactics", stat: "INT"},
    %{id: "tracking", stat: "WIS"},
    %{id: "unarmed_combat", stat: "STR"}
  ],
  stat_roll: %{
    "dice" => 4,
    "keep" => 3,
    "max" => 18,
    "min" => 3,
    "rerolls" => 1,
    "sides" => 6
  }
}
