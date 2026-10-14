# Fantasy RPG Game Mechanics Summary

Why: you learn by failing, as in life. Getting very good is slow on
purpose. See `PRODUCT.md` → Rules philosophy.

## Overview

This is a skill-based fantasy RPG system where character progress is measured by skills acquired and improved primarily through learning from failures, rather than traditional levels or experience points. The system uses a computer as the DM for bookkeeping, eliminating manual tracking burdens. Skills go from 1 to 100 and are rolled on a 1d100 (a percentage roll). A roll succeeds when it is equal to or below the effective skill (skill level plus the stat bonus). Skills grow to at most 100; high levels need trainers or adventures.

## Core Skill Mechanics

- **Skill Rolls** (the server checks in this order):
  - **Critical success**: a roll of 1 to ceil(skill / 10). Not possible at skill 10 or below. It earns no LP.
  - **Success**: a roll equal to or below the effective skill. It earns no LP.
  - **Critical failure**: the top floor((100 - skill) / 10) rolls. A roll of 100 is always a critical failure. It earns no LP.
  - **Near miss** (partial success): 1 to 15 above the skill. The attempt falls just short or succeeds at a cost. +1 LP.
  - **Failure**: any other roll. +1 LP.
  - At skill 100 or higher, a roll of 100 rolls again. A failure on the second roll is a critical failure.
  - The critical bands use the effective skill (level plus stat bonus).
  - Examples: skill 50 gives critical success on 1-5, success on 6-50, near miss on 51-65, failure on 66-95 and critical failure on 96-100. Skill 90 gives critical success on 1-9 and critical failure on 100 only.
- **Critical effects**:
  - Combat critical success: full damage and every bonus. Combat critical failure: the attacker takes normal weapon damage.
  - Running or climbing: about 50% faster.
  - Lockpicking: half the time, and quiet.
  - Persuasion: the deal is better than expected.
- **Learning Points (LP)** — you learn only from failure, only in the skill you failed:
  - Failure or near miss: +1 LP for that skill, a banked improvement chance. Nothing spills to other skills.
  - Success, critical success or critical failure: no LP.
  - The linked stat adds no LP: talent helps you succeed, not learn faster.
- **Skill Improvement** — it sinks in while you sleep, except for physical skills:
  - Banked LP are resolved on a long rest (sleep, or six hours or more of rest). Ordinary turns resolve nothing.
  - Physical skills (melee, ranged and unarmed combat, dodge, climbing, lockpicking) improve right away: their LP are resolved at the end of the turn of the failure, by the same cost, roll and reflection rule. They too improve at most once per skill between two long rests; after that, their LP are dropped until the character has slept. LP too few for a roll wait for more failures until the next long rest.
  - Higher levels need more failures: one improvement roll costs ceil(skill / 15) banked LP (1 LP up to 15, 2 up to 30, 3 up to 45, 4 up to 60, 5 up to 75).
  - Roll 1d100 ≥ 51 and ≥ raw skill: the skill gains 1d6+1 (at most 100). Chance (101 - max(skill, 51))/100: 50% up to 51, 45% at 56, 25% at 76, 5% at 96. No roll is a sure thing, not even at level 0.
  - At most one success per skill per night (for physical skills: per long-rest cycle): the rolls stop at the first success. Then all of that skill's banked LP are gone, and they are gone too if every roll failed or there were too few for a roll. Nothing carries over to the next night.
  - From skill 50, practice alone is not enough: the LP are only resolved on a rest when the character reflected on the skill, practised or studied it deliberately, or trained it with a trainer since the last long rest. Until then they stay banked.
  - Skills stop at 100. Past 75, only a trainer's bonus makes the roll likely.
- **Death Exception**: No LP from fatal failures, and the dead learn nothing. A death roll is a d100: a roll above CON × 2.5 means death.
- **Skill List Categories** (Examples):
  - **Combat**: Melee Combat, Ranged Combat, Unarmed Combat, Tactics, Dodge.
  - **Exploration**: Navigation, Survival, Tracking, Climbing, Stealth.
  - **Social**: Persuasion, Intimidation, Deception, Insight, Etiquette.
  - **Knowledge/Magic**: Arcana, History, Herbalism, Spellcasting, Ritual Magic.
  - **Craft/Utility**: Crafting, Lockpicking, Animal Handling, Alchemy, First Aid.

<!-- skill_split:on -->
## Skill split

A character with a high skill can split one skill action into parts in one turn. The server rolls each part. The thresholds use the d100 scale.

- **Unlock**: The raw skill level unlocks the split. The stat bonus does not count for the unlock. The split starts at raw level 100.
- **Two even parts**: From raw level 100, the player splits the action into two even parts. Example: level 100 gives two parts at 50.
- **Three parts or uneven parts**: From raw level 150, the player can also split into three even parts, or into two uneven parts. Each uneven part is 25 or more. Example: level 150 gives three parts at 50, or two parts at 95 and 55.
- **Sum**: The parts always sum to the skill level. When the level does not divide evenly, the first parts get 1 more.
- **Rolls**: Each part rolls as a normal skill roll at its part level. The critical and near miss rules apply to each part.
- **Learning**: A split action banks one learning chance at most, also when more than one part fails.
- **Every skill**: Every skill can split. The skill table in `skills.md` gives the meaning of a split for each skill family. A skill with no entry in the table: the parts are separate attempts in the same turn.
- **Foes**: A foe can split Dodge and parry more than one attack. In v1 this is rules text only; the server rolls no foe split.
- **Refusal**: Below the start level, or below level 150 for three parts or uneven parts, the server rolls one normal attempt. The story tells the player that the split needs more skill.
- **Combat**: The split replaces the old Multi-Actions rule (-10 for each extra action).

<!-- /skill_split:on -->
## Trainers and Adventures

- **Trainers**: NPCs with skill level ≥25 above the character's. A training session is one free improvement attempt (no LP) with +25 to the roll (1d100 + 25 ≥ 51 and ≥ skill).
  - Found via quests (e.g., journey to a master thief for Stealth training).
  - One attempt per training session; costs time and the trainer's fee.
  - Can be group quests for party training.
- **Integration**: Trainers can bypass/reduce stat minima for advancements; quests add narrative depth.

## Stats (STR, DEX, CON, INT, WIS, CHA)

- **Range**: 3-18 (rolled or point-buy).
- **Bonuses to Skill Rolls**: 5 × ((Stat - 10)/2, rounded down) added to effective skill level for related skills.
  - STR: Physical power (e.g., Melee, Climbing).
  - DEX: Agility/precision (e.g., Ranged, Stealth).
  - CON: Endurance (e.g., Survival, First Aid).
  - INT: Knowledge (e.g., Arcana, Herbalism).
  - WIS: Perception (e.g., Insight, Tracking).
  - CHA: Social (e.g., Persuasion, Deception).
- **Minimum Requirements for Advancement**:
  - Skills divided into tiers (Novice 1-25, Adept 26-50, Expert 51-75, Master 76+).
  - Min stat for higher tiers (e.g., STR ≥8 for Adept in Melee; increases per tier).
  - Auto-fail improvement if unmet; LP retained. Trainers can reduce minima.
- **Base Chance for Unskilled Attempts (Level 0)**:
  - Effective level = 5 × (Stat / 3, rounded down) for related tasks.
  - Adjustable by difficulty (/2 easy, /4 hard).
  - Failures grant LP to start building the skill.
- **Additional Integrations**:
  - Derived Attributes: HP = 10 + (CON / 2) + other modifiers; damage bonuses from STR, etc.
  - Role-Playing Hooks: Stats gate equipment/actions (e.g., STR 13+ for greatswords); low stats prompt quests.

## Character Creation and Starting Allocation

- **Stats**: 75-point buy (min 3/max 18 per stat).
- **Skill Points**: 100-150 total to distribute (adjust for campaign).
  - Skills rise in steps of 5. Cost: 5 points per step up to 15; 10 points per step from 20 to 25 (cap at 25 starting, 35 for a signature skill).
  - Stat Bonuses: +5 points per (stat &gt;10) for linked skills.
  - Backgrounds: Grant 15-25 free points in thematic skills (e.g., Warrior: +15 Melee, +10 Tactics).
  - Minimum: Allocate to at least 3-5 skills for diversity.
  - Wildcards: 5-10 extra points for quirks.
- **Computer DM Role**: Suggests builds, simulates practice rolls for feedback.