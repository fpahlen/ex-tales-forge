---
title: "Playtest: the character each persona creates"
updated: 2026-10-07
status: provisional (until founder survey Q10–Q14)
related: personas.md, character-creation-persona-prefs.md, plan-jev-baseline-and-ab.md
---

# Playtest: the character each persona creates

Until now every playtest bot played the pack's default character, Elara Voss. With [ex-tales-forge PR #60](https://github.com/whyse-ab/ex-tales-forge/pull/60), each persona creates its own character instead, through the same `CharacterCreation` steps as the creation screen: race, class, 75-point buy, race bonus and name. The bot plays that character.

- The picks are data: `priv/playtest/characters.json` in ex-tales-forge. Change them there; no code change is needed.
- The seed is fixed per persona, so every run of a persona plays the identical character, including its derived OCEAN, Maslow level, concerns and coins. That keeps runs comparable.
- The persona's system prompt gets one line saying who it created (name, race, class, concept), because a real player knows that.
- `Runner.start(..., character: :default)` still plays Elara, for comparison runs.
- **Provisional:** the picks are derived from [personas](personas.md) and the [creation preferences interviews](character-creation-persona-prefs.md). Revisit them when the founder survey answers to Q10–Q14 (character creation per persona) arrive.

## The picks and why

The options are: races human, dwarf, elf, gnome, half-elf and halfling; classes cleric, druid, ranger, thief, warrior and wizard. Base stats are before the race modifier; the budget is 75 points, with 3–18 per stat.

| Persona | Character | Race / class | Final stats (STR DEX CON INT WIS CHA) | Concept |
|---|---|---|---|---|
| Hawk | Brannoc Hale | Human warrior (+1 STR, CON) | 16 12 15 12 12 10 | A sellsword who reads the ground before a fight and never walks in without a plan |
| Paul | Corvin Ashdown | Half-elf cleric | 11 12 11 12 14 17 | A wandering lay preacher with a silver tongue, who would rather talk a fight down than draw steel |
| Lotta | Hilde Stonebrook | Dwarf druid | 13 11 16 12 15 10 | A gruff, plain-spoken hedge-druid, an outsider in a human mining valley, hoping it will see who she really is |
| Lars | Taren Swiftbrook | Elf ranger (+1 WIS) | 12 17 12 11 14 11 | A tracker who wants a real quest, a fight worth winning and a name the Guild will remember |
| Ronny | Maxx Goldhand | Human warrior (+1 STR, CON) | 18 14 18 9 9 9 | The strongest build the rules allow, here for the loot |

- **Hawk:** he wants hard fights won through "planning, tactics and the right equipment". A warrior has melee combat and tactics. His stats are solid but nothing is maxed: a hard-mode player doesn't build an easy character, and the danger has to stay real.
- **Paul:** a role-player who talks a fight down and rallies people. The cleric's skills are persuasion and insight, and CHA is his top stat. Half-elf gives a "dramatic entrance" and fits his race-and-concept-first preference. With the new roll rule, most of his talk needs no roll at all, and the skills matter only when the outcome is genuinely uncertain.
- **Lotta:** she wants to be "a different person, not necessarily a better one" (founder input: the introvert plays an extrovert, the shy person plays someone rough). A gruff dwarf druid is an outsider in a human mining valley: an underdog start for her Ugly Duckling arc. It also gives the world something to react to "who she is" (race, manner, a link to the hills). WIS is high and CHA is low, on purpose.
- **Lars:** action, a clear quest and visible impact. A ranger has ranged combat and tracking, which fit the orcs on the cut and the hill. DEX is his top stat. The Elf bonus goes to WIS for tracking and perception.
- **Ronny:** the anti-persona "builds the character that is easiest to win with". He maxes STR and CON at 18 and dumps INT, WIS and CHA to 9. It is a legitimate point buy; the red-team question is whether the game still resists him in play.

## Occupation and skills (skill rules, 2026-10-07)

With the old game's skill rules ([decision 2026-10-07](decisions.md#2026-10-07-skill-rules-ported-from-the-old-game-signature-skills-up-to-7-growth-no-longer-stalls), [ex-tales-forge #65](https://github.com/whyse-ab/ex-tales-forge/pull/65), not merged yet), each pick also has a past occupation and a full skill build that spends the whole budget.

- The budget is 25, Human +5, Half-Elf +3.
- Free levels come from the class package (3/2/1), the race and the occupation.
- Signature skills (above 5, up to 7) are in bold.

| Persona | Occupation | Skills | Points |
|---|---|---|---|
| Hawk | soldier | **Tactics 6**, Melee Combat 5, Survival 5, Insight 4, Ranged Combat 4, Climbing 4, Tracking 3, Intimidation 3 | 30 |
| Paul | priest | **Persuasion 7**, Insight 5, Deception 5, Etiquette 5, History 5, Intimidation 1 | 28 |
| Lotta | miner | **Survival 6**, Tracking 5, Arcana 5, Melee Combat 5, Insight 5, Climbing 4, Intimidation 3, Unarmed Combat 1 | 25 |
| Lars | hunter | **Ranged Combat 7**, Tracking 5, Survival 5, Stealth 5, Dodge 5, Melee Combat 4, Climbing 4, Insight 1 | 25 + 3 back |
| Ronny | soldier | **Melee Combat 7, Dodge 7**, Tactics 5, Intimidation 5, Survival 3, Ranged Combat 2 | 30 |

- **Hawk:** his signature skill is Tactics, because he plans before he fights. Insight and Tracking let him read the ground. A former soldier.
- **Paul:** his signature skill is Persuasion 7, and he is well rounded on the social side: Insight, Deception, Etiquette and History. A former priest, which fits the lay preacher.
- **Lotta:** a former miner, which ties her to the hills and the mining valley. Her free Survival 6 (druid 3, dwarf 2, miner 1) makes her a signature hedge-druid. She has Intimidation 3 for the gruff manner but no Persuasion, on purpose.
- **Lars:** a former hunter. Ranged Combat 3 + 3 + 2 = 8 is capped at 7, and the extra level comes back as 3 points. Tracking, Stealth and Dodge make him a scout.
- **Ronny:** he takes both signature slots in combat (Melee 7, Dodge 7), the min-max the rules allow.
- The persona's prompt line now names the past occupation ("…, a dwarf druid, a former miner.").

## Open points

- Founder survey Q10–Q14 may change race, class or concept per persona. Update the JSON and this note; the old runs keep the character they played (it is in the session's world state).
- Elara (Tin Valley) is a classless human with persuasion 3, insight 2, stealth 2, melee 1 and CHA 14. Paul's new character is stronger at talk (CHA 17), Hawk's and Lars's at fighting, and Lotta's CHA is lower (10). That is part of the comparison with the Elara runs. If a persona's score moves, check whether the character explains it (see [the measurement plan](plan-jev-baseline-and-ab.md)).
