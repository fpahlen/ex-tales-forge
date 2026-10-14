# Combat System Summary for Skill-Based Fantasy RPG

## Overview
This combat system, adapted from Savage Worlds' wound-based mechanics, is designed for a skill-centered fantasy RPG where progression emphasizes learning from failures. It is fast-paced, dangerous, and exciting, using minimal rules to ensure quick resolution while integrating with the core system (1d100 skill rolls from 1 to 100, success on ≤ skill level, LP-driven improvement, and six stats from 3-18). The computer DM handles bookkeeping, tracking wounds, initiative, and LP seamlessly.

## Core Mechanics
- **Wound Track**:
  - Characters/NPCs: 3 wounds base + (CON - 10)/2 (rounded down). E.g., CON 18 = 7 wounds; CON 10 = 3; CON 3 = 1 minimum.
  - Mooks (minor foes): 1 wound; major enemies: 3-5 wounds.
  - At 0 wounds: Incapacitated (unconscious, needs rescue). Excess hit triggers death roll (d100 > CON × 2.5: the character dies).
- **Initiative**:
  - Roll Tactics or Dodge (d100, success on ≤ skill level) each round; highest successes act first, ties favor players then DEX stat.
  - Computer DM rerolls initiative per round for dynamic pacing.
- **Attacks**:
  - Roll combat skill (Melee, Ranged, Unarmed) vs. Parry (Dodge/2 + 50 + 5 × ((DEX - 10)/2)). The target is the skill less the Parry above 50.
  - Success (≤ target, not a critical failure): Roll damage (1d6 + STR/3 for melee/unarmed, +DEX/3 for ranged, rounded down) vs. Toughness (5 + armor + CON/2).
  - Critical success (1 to ceil(skill / 10)): full damage and every bonus (e.g., disarm).
  - Critical failure (the top floor((100 - skill) / 10) rolls, always 100): the attacker takes normal weapon damage. No LP.
  - Damage Outcomes:
    - < Toughness: No effect.
    - ≥ Toughness: Shaken (lose next action unless WIS/2 roll succeeds).
    - ≥ Toughness + 4: 1 wound + Shaken (or +1 wound if Shaken).
    - Mooks die on 1 wound; others take wounds up to max.
- **Learning Points (LP)**:
  - Miss or near miss: +1 LP for the skill rolled. A hit or a critical failure earns none.
  - Nothing spills to other skills.
  - Combat skills and dodge are physical: their LP are resolved at the end of the turn of the miss, not on a rest: ceil(skill / 15) LP per roll, d100 ≥ 51 and ≥ skill level: +1d6+1, at most one success per skill between two long rests; from skill 50 only after reflecting on it. Other skills rolled in a fight (deception, intimidation) wait for sleep.

## Additional Features
<!-- skill_split:off -->
- **Multi-Actions**: Multiple actions per round (e.g., attack twice) at -10 skill per extra action, granting LP on failures.
<!-- /skill_split:off -->
<!-- skill_split:on -->
- **Skill split**: To attack more than one time in a round, split the combat skill. See `core_mechanics.md`, "Skill split".
<!-- /skill_split:on -->
- **Tactical Options**:
  - Reckless: +10 attack skill, -10 Parry next round.
  - Defensive: +10 Parry, -10 attack skill.
  - Trick (Deception/Intimidation): Success lowers foe’s Parry by 10 (+1 LP on fail).
- **Group Advantage**: +5 attack skill per ally engaged with target.
- **Recovery**: Post-combat, First Aid (≤ skill level) heals 1 wound per success (once per ally per fight). Otherwise, 1 wound/day with CON/2 roll success.
- **Computer DM**: Tracks wounds, initiative, LP; adds environmental effects (e.g., -5 Dodge on mud) or fumble tables for flavor.

## Design Goals
- **Deadly**: Low wounds (1-7) and high damage (~4 average) resolve fights in 2-4 rounds.
- **Fast-Paced**: Simple rolls and initiative keep combat swift.
- **Exciting**: Tactical choices and dynamic initiative add cinematic tension.
- **Skill-Centric**: Skills drive outcomes, with stats as modifiers; failures fuel LP for growth.
- **Trainer Integration**: Trainers (+25 to improvement rolls) or stat-boosting quests ease high-skill advancement.