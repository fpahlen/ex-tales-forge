---
title: "Design: one rule for skills and the economy"
updated: 2026-10-09
status: design note (docs only, no code)
---

# Design: one rule for skills and the economy

**Status:** design note, 2026-10-09, approved by Fredrik as a docs-only note ([decision](decisions.md#2026-10-09-write-one-design-note-for-skills-and-the-economy-docs-only)). No code changes. Every follow-up code PR needs Fredrik's OK.

**Revised 2026-10-09 after Fredrik's guidance** ([decision](decisions.md#2026-10-09-prices-are-anchors-with-bounded-situational-modifiers-practice-hours-are-narrative-bands)): "the formulas are an anchor so prices stay consistent, not exact price tags. Like real life, supply and demand apply. Hiring the last available guards for a dangerous journey gives those guards pricing power. Levels and hours likewise give the GM something to build a story from, not exact numbers." So every formula below gives an **anchor price**; the price actually paid is the anchor times bounded situational modifiers (§3.6), and practice hours are shown as narrative bands (§2.1).

**Read against:** ex-tales-forge `main` at `702cf6f` and [PR #100](https://github.com/whyse-ab/ex-tales-forge/pull/100) (open, head `f99b3e0`, the new growth rules); the two earlier designs in `fpahlen/tales-forge-new-31993d9d` (`main` at `20b791c1`):

- **Skill Progression and Convergence:** [`docs/game-rules/skill_domains.md`](https://github.com/fpahlen/tales-forge-new-31993d9d/blob/main/docs/game-rules/skill_domains.md), first planned in `.lovable/plan.md` at [`b9952c11`](https://github.com/fpahlen/tales-forge-new-31993d9d/blob/b9952c115dda4b60746018021e595106491ddf2a/.lovable/plan.md).
- **Labor-Anchored Economy:** [`docs/game-rules/economy_system.md`](https://github.com/fpahlen/tales-forge-new-31993d9d/blob/main/docs/game-rules/economy_system.md), first planned in `.lovable/plan.md` at [`2da5f015`](https://github.com/fpahlen/tales-forge-new-31993d9d/blob/2da5f015025ecb9fa45036a85aa9f91ac904b8e3/.lovable/plan.md).

Both were copied into the game as `priv/rules/skills.md` and `priv/rules/economy.md` (plus the copies in each pack). The game then went its own way, and the numbers no longer agree with each other or with the docs.

## 1. Summary

- **One rule, as an anchor:** a person's day rate depends on their skill level, through the practice hours that level stands for. Wages, hireling and thug prices, trainer fees, expert services and the labour part of item prices all get their **anchor price** from that one curve. The anchor keeps prices consistent; it is not a price tag.
- **Actual price = anchor × situational modifiers:** scarcity, demand, danger, leverage, relationship and haggling, each with its own band, and the product clamped to **0.5× to 3×** the anchor. Elixir computes the anchor and the range, Jev (or the GM) reads the situation and picks within it, Elixir clamps and records the result. The last two guards for a dangerous pass charge about 2.6× the anchor (§3.6).
- **Hours as narrative bands:** keep the formula, `hours = 10,000 × (level / 20)³`, as the anchor behind the scale, and drop the rounded table (§2). What the GM and the player see is a band (novice, apprentice, journeyman, expert, master) with rough hours and story flavour, not a ledger (§2.1).
- **Day rate:** `day_rate = 10c + 30c × (level / 10)^1.5`, that is 10c plus a part that grows with the square root of practice hours. Unskilled (level 0) earns 10c a day, a skilled worker (level 10) 40c, so a month of skilled work (25 days) is 1,000c = 2g = 1 oz of gold, the old anchor (§3).
- **Growth stays PR #100's LP model.** Practice hours are not tracked for player characters; they are the scale that prices labour, sets NPC levels and gives the GM words for how good someone is. Deliberate practice in downtime can feed the LP model as rolls that can fail (§4).
- **Drift to fix:** the smith's short sword (60c) is 8× under the doc's sword (1g = 500c); starting coins come from the old table, not the budget; trainer fees are typed in by hand (three level-9 trainers charge 20c, 50c and 80c); the economy doc gives three different unskilled wages; `priv/rules/skills.md` mixes two growth models and rules the code never applies (§6).
- **Call types:** anchor, range, clamping and recording are Elixir. Jev turns the player's words and the scene into a typed deal (who, what job, how risky, how many days) and the situational modifiers. The LLM only narrates, with the final price given to it (§7).

```mermaid
flowchart LR
  L[Skill level 0-20] --> H["Practice hours<br/>10,000 x (L/20)^3"]
  H --> D["Day rate<br/>10c + 30c x sqrt(hours / 1,250)"]
  D --> W[NPC wages<br/>day rate x 25 days]
  D --> T[Trainer fee<br/>trainer's level in the skill taught]
  D --> R[Hirelings and thugs<br/>day rate x danger]
  D --> S[Expert services<br/>day rate / 8 per hour]
  D --> P[Item prices<br/>days x intensity x day rate x materials]
  W & T & R & S & P --> A[Anchor price]
  A --> M["x situational modifiers<br/>scarcity, demand, danger,<br/>leverage, relationship, haggling"]
  M --> C["Elixir clamps to 0.5x-3x<br/>and records"] --> Q[Price paid]
  F[Failed roll] --> LP[Banked LP] --> N["Long rest: PR 100 roll"] --> L
  X[Downtime practice] --> F
  T --> N
```

## 2. The hours scale: formula, not table

`skill_domains.md` gives both a formula and a table, and they disagree:

| Level | Table (`~`) | Formula `10,000 × (L/20)³` | Gap |
| --- | --- | --- | --- |
| 5 | 100 | 156 | table 36% low |
| 10 | 1,000 | 1,250 | table 20% low |
| 15 | 3,000 | 4,219 | table 29% low |
| 20 | 10,000 | 10,000 | same |

**Pick the formula.** Why:

1. The table isn't one curve at all. Its points at 5 and 10 fit a power of about 3.3, its point at 15 needs about 4.2. Any code would have to interpolate between hand-picked points.
2. The formula is one Elixir function with a doctest, defined for every level, and it matches the table at both ends (0 and 10,000).
3. The table is marked "~" and reads as rounded milestones; the formula is what the doc calls the rule.

The cost is that the milestones stop being round: 156, 1,250 and 4,219 hours. The tier table in `priv/rules/skills.md` should show the formula's numbers.

**Practice hours means deliberate practice**, not years on the job. A journeyman who has worked six years may have far fewer hours of real, at-the-edge practice, which is why the default NPC levels below sit where they do.

The formula is the anchor for prices and for keeping NPC levels consistent. It is not a ledger: nobody counts a character's hours, and the GM is never handed "1,250 hours" as a fact to recite.

### 2.1 Narrative bands: what the GM and the player see

Levels stay exact where dice need them (the 1d20 roll-under check, PR #100's growth rolls). Everywhere else, the level and its hours are something to build a story from. The GM gets a band, rough hours and a line of flavour, and tells it in the world's terms ("she has spent years at the forge", "he has never held a sword in earnest").

| Band | Levels | Rough practice hours | Story flavour |
| --- | --- | --- | --- |
| **Novice** | 0-3 | none to a few dozen | Knows which end to hold. Has tried it, been shown once or twice, gets lucky sometimes. A farmhand with a borrowed spear, a child who has watched the herb wife. |
| **Apprentice** | 4-7 | a hundred or so to a few hundred | Learning under someone. Does the routine work well when nothing goes wrong; needs help when it does. Where a new character's best skills start. |
| **Journeyman** | 8-11 | several hundred to under two thousand | Earns a living by it and is trusted to work alone. The town's ordinary smith, a caravan guard who has seen a few fights, today's Tin Valley trainers. A level-10 journeyman is the price anchor. |
| **Expert** | 12-15 | two to four thousand | Others come to them with the hard cases. Runs a workshop, teaches, is known in the valley. A guild master by rank (`seniority.master`, 12) sits here. |
| **Master** | 16-20 | five to ten thousand and more | A name people travel to find. Rare in any one place; legends, the best in a kingdom. |

The band edges follow the formula (34, 80, 429, 640, 1,664, 2,160, 4,219 and 5,120 hours at levels 3, 4, 7, 8, 11, 12, 15 and 16) but are said in round words. The bands replace the old four tiers (Novice 1-5, Adept 6-10, Expert 11-15, Master 16-20; §5): five bands match the trade words players already know and the NPC seniority labels (apprentice 4, journeyman 8, master 12).

## 3. The one rule: day rate by level

`day_rate(level) = 10c + 30c × (level / 10)^1.5` (rounded to whole copper). The `(level / 10)^1.5` part is `sqrt(hours / 1,250)`: pay grows with the square root of practice hours. A master has 8× the hours of a level-10 worker but earns about 2.4× as much, which is close to how wages spread in real crafts.

Three fixed points set the curve:

- **Level 0, unskilled: 10c a day.** The top of the doc's "unskilled labour 5-10c" row. It buys two common meals (5c each) and not much more: hand-to-mouth.
- **Level 10, skilled: 40c a day.** A month of 25 working days is 1,000c = 2g = 1 oz of gold, the doc's anchor ("1 oz of gold is about one month of skilled craftsman labour"; in our coins 1 oz = 2g, and 1g = 50s = 500c, so 1s = 10c).
- **Level 15-20, expert: 65-95c a day**, the doc's "expert service 5-10s a day".

| Level | Practice hours | Who, in today's game | Day rate | Per hour (day / 8) | Month (25 days) |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | unskilled labour | 10c (1s) | 1.2c | 250c (25s) |
| 1 | 1 | | 11c | 1.4c | 275c |
| 2 | 10 | | 13c | 1.6c | 325c |
| 3 | 34 | class package top skill at creation | 15c | 1.9c | 375c |
| 4 | 80 | NPC apprentice (`seniority.apprentice`) | 18c | 2.2c | 450c |
| 5 | 156 | normal cap at creation | 21c (2s 1c) | 2.6c | 525c (1g 2s 5c) |
| 6 | 270 | | 24c | 3.0c | 600c |
| 7 | 429 | signature skill at creation | 28c | 3.5c | 700c |
| 8 | 640 | NPC journeyman (`seniority.journeyman`) | 31c | 3.9c | 775c |
| 9 | 911 | today's best trainers | 36c | 4.5c | 900c |
| 10 | 1,250 | **skilled worker: the anchor** | **40c (4s)** | 5.0c | **1,000c (2g)** |
| 11 | 1,664 | | 45c | 5.6c | 1,125c |
| 12 | 2,160 | NPC master (`seniority.master`) | 49c | 6.1c | 1,225c |
| 13 | 2,746 | | 54c | 6.8c | 1,350c |
| 14 | 3,430 | | 60c (6s) | 7.5c | 1,500c (3g) |
| 15 | 4,219 | expert, instructor | 65c | 8.1c | 1,625c |
| 16 | 5,120 | | 71c | 8.9c | 1,775c |
| 17 | 6,141 | | 76c | 9.5c | 1,900c |
| 18 | 7,290 | Summit Sight in the old doc | 82c | 10.2c | 2,050c |
| 19 | 8,574 | | 89c | 11.1c | 2,225c |
| 20 | 10,000 | world-class | 95c (9s 5c) | 11.9c | 2,375c (4g 37s 5c) |

Everything below uses this column to get the **anchor**. The only other inputs to the anchor are a few fixed factors in data (the job's danger label, intensity, materials), never a hand-typed price. The price actually paid is the anchor times the situational modifiers in §3.6.

### 3.1 NPC wages

Anchor: `monthly wage = day_rate(level in their trade) × 25`. A labourer (level 0-2) earns 250-325c a month, a journeyman miner (8) 775c, a master (12) about 1,225c. The Miners Guild board in the square ("wages in tin and coin") can quote these.

### 3.2 Hirelings and thugs

Anchor: `hire per day = day_rate(level in the skill hired for) × job danger`. The job's danger is one of three labels for the kind of work: **safe** ×1, **risky** ×1.5 (guard duty, escort, a dangerous road), **fight** ×2 (paid to fight: clearing the orc nest, a brawl). How dangerous this particular trip is, beyond its label, is the situational danger modifier (§3.6).

| Hired for | Level 10 | Level 15 |
| --- | --- | --- |
| Safe work (carry, guide, keep watch in town) | 40c (4s) | 65c |
| Risky (guard, escort) | 60c (6s) | 98c |
| Fight (thug, sellsword) | 80c (8s) | 130c (13s) |

Check against the doc: its "hired guard 3-5s a day" is a level-7 guard on risky work (28c × 1.5 = 42c). The Tinjacks fit too: Cobb (unarmed 8) would ask about 62c a day to break heads for you, Rusk (melee 8) the same.

### 3.3 Trainer fees

Anchor: `trainer fee per day = day_rate(trainer's level in the skill taught)`. One session is one day and one free +5 attempt (`TalesForge.Game.Train`). Today `fee_copper` is one number per NPC whatever they teach; under the rule the fee follows the skill.

| Trainer (Tin Valley) | Teaches (level) | Fee today | Fee by the rule |
| --- | --- | --- | --- |
| Herb wife | history 9 | 20c | 36c |
| Prospector | climbing 9 | 50c | 36c |
| Guild steward (Osric) | persuasion 9 | 80c | 36c |
| Innkeep (Brenna) | persuasion 8 (derived) | 50c | 31c |
| Smith (Hilde) | melee combat 6 | 40c | 24c |
| Drover | persuasion 7 | 30c | 28c |
| Stable lad | stealth 8 | 10c | 31c |

The rule column is the anchor. Some of today's spread can survive as modifiers: the guild steward may charge more because he is the only one who teaches persuasion to guild standard (scarcity, leverage); the stable lad less because he likes the player (relationship). What goes is a fee with no anchor and no recorded reason.

### 3.4 Expert services

Short work is billed by the hour, `day_rate / 8`, rounded up, at least 1c. Stitching a wound for an hour by a level-12 healer is 7c; a day of legal advice or tutoring from a level-15 expert is 65c. A night on the herb wife's sickbed (1s today) fits: about two hours of a level-9 carer's time (4.5c an hour).

### 3.5 Item prices

The doc's own formula, made concrete, as the anchor: `price = labour days × intensity × day_rate(maker's level) × (1 + materials)`.

- **Intensity:** 1 for constant attention (forging, tailoring), down to about 0.1 for things that mostly make themselves (ale, cheese).
- **Materials:** raw materials are also labour (mining, smelting, charcoal, spinning) further up the chain. A first version gives each item category one materials factor in data, for example 1 for iron goods (the iron and charcoal cost about as much as the forging). Open question 4.

At the smith, with Hilde at smithing 10:

| Item | Labour | Labour only | With materials (×2) | Today | Doc |
| --- | --- | --- | --- | --- | --- |
| Hunting knife | 5 hours | 25c | 50c | 15c | dagger 10s = 100c |
| Spearhead | 3 hours | 15c | 30c | 20c | (none) |
| Short sword | 3 days | 120c | 240c (24s) | 60c (6s) | common sword 1g = 500c |

### 3.6 Situational modifiers: the actual price

Like real life, supply and demand apply. The price paid is

`actual price = anchor × scarcity × demand × danger × leverage × relationship × haggling`, clamped to **0.5× to 3× the anchor**, rounded to whole copper.

Each modifier is 1.0 when nothing special is going on, has its own band, and is recorded with a short reason. Proposed bands:

| Modifier | Band | Low end, for example | High end, for example |
| --- | --- | --- | --- |
| **Scarcity:** how many others could do this or sell this | 0.8-2.0 | ×0.8: a quiet winter, six idle guards at the inn | ×1.6-2.0: the last two guards in town, the only smith for three days' ride |
| **Demand:** how many others want it now | 0.9-1.5 | ×0.9: nobody else is buying | ×1.2: another party is also asking; ×1.5: caravan season, every guard is spoken for |
| **Danger:** how dangerous this particular trip is, beyond the job's label (§3.2) | 1.0-1.5 | ×1.0: an ordinary risky road | ×1.25: word of orc raids on the pass; ×1.5: nobody has come back this month |
| **Leverage:** who needs the deal more | 0.7-1.5 | ×0.7: the seller needs coin by tonight | ×1.2: the buyer must leave at dawn and the seller knows it; ×1.5: a wounded friend needs the healer now |
| **Relationship:** the NPC's attitude to the buyer | 0.8-1.2 | ×0.8: a friend, kin, a fellow guild member, a debt owed | ×1.2: a disliked stranger (a hostile NPC refuses rather than overcharging) |
| **Haggling:** the result of the persuasion check, when the player haggles | 0.85-1.15 | ×0.85: a clear success | ×1.15: a bad failure, the NPC takes offence |

Each band is narrow enough that no single modifier carries a price out of the world, but together they could: every high end at once is about 9.3× (2.0 × 1.5 × 1.5 × 1.5 × 1.2 × 1.15) and every low end about 0.34×. The overall clamp is what really bounds the price. A price at 3× is something the GM can tell as a story ("they know they are the last two swords in town"); a price at 10× would break the economy.

**Worked example: the last guards for a dangerous journey.** The party must cross the pass to Crossroads, five days, and wants two guards. A caravan left yesterday and hired everyone else. The two who are left are melee 8 journeymen.

1. **Anchor (Elixir):** `day_rate(8)` = 31c; guard duty is **risky** ×1.5: 46.5c, so **47c per guard per day**. Range: 0.5× to 3×, that is **24c to 141c**.
2. **Situation (Jev reads the scene):**
   - scarcity ×1.6: they are the last two guards in town
   - demand ×1.2: a pedlar at the inn is also asking about guards
   - danger ×1.25: travellers report orc raids on the pass
   - leverage ×1.2: the party has said it must leave tomorrow
   - relationship ×1.0: strangers
   - Product: 1.6 × 1.2 × 1.25 × 1.2 = **2.88×**, about 135c a day.
3. **Haggling (Elixir rolls persuasion):** the player argues the guards will be paid for a full five days in a slow week. A success gives ×0.9: 2.88 × 0.9 = **2.59×**, so 47c × 2.59 = **122c per guard per day**. Two guards for five days: **1,220c (2g 22s)**, against an anchor of 470c (47s).
4. **If the haggle had failed** (×1.15): 2.88 × 1.15 = 3.31×, which Elixir clamps to 3×: **141c per guard per day**, 1,410c (2g 41s) for the trip. The clamp is what keeps the guards' pricing power from becoming extortion the economy can't absorb.
5. **The same two guards in a quiet week**, with six other guards idle (scarcity ×0.8) and the party known to the guild (relationship ×0.9): 0.72×, **34c per guard per day**.
6. **Elixir records** the anchor, each modifier with its reason, the clamp if it applied and the final price in the hire event, so the GM can narrate it ("the older one smiles: everyone else rode out with the caravan") and so a later price from the same NPC can be compared with it.

The same modifiers apply to wages offered to the player, trainer fees, services and item prices. The anchor makes prices consistent across the world; the modifiers make each deal a story.

## 4. Today's levels on the 0-20 scale, and how hours feed growth

### 4.1 Where today's characters sit

| Today's game | Level | Hours (anchor) | Band (§2.1) |
| --- | --- | --- | --- |
| Player character at creation (`creation.json`: cap 5, one or two signature skills at 7, free levels from class, race and past occupation) | about 0-7 | 0-429 | Novice to Apprentice |
| NPC apprentice / journeyman / master (`priv/characters/defaults.json` `seniority`: 4, 8, 12) | 4, 8, 12 | 80, 640, 2,160 | Apprentice, Journeyman, Expert |
| Tin Valley trainers (herb wife, prospector, steward) | 9 | 911 | Journeyman |
| Reflection needed (PR #100 `reflection_level`) | 10+ | 1,250+ | late Journeyman and up |

This fits the scale as it is: NPC apprentices are Apprentices, journeymen Journeymen, guild masters Experts, and the Master band (16-20) is left for legends. No numbers in the game need to move to adopt the scale. The skill check stays 1d20 roll-under (success if the roll is at most level plus the stat bonus).

### 4.2 Growth: PR #100's LP model stays the engine

PR #100: you learn only from failure; a failed or partial roll banks 1 LP for that skill; banked LP are resolved on a long rest; one improvement roll costs `ceil(level / 3)` LP and needs a d20 of at least 11 and at least the level; at most +1 per skill per night, then that skill's LP are cleared; from level 10 the character must have reflected on the skill, or its LP stay banked.

**Proposal: practice hours are a derived label, not a counter.** `hours(level)` anchors wages, prices and NPC levels, and the band (§2.1) gives the GM words ("years at the forge", "a journeyman's hand with a blade"). Player characters do not carry an hours total, and hours never cap a level.

Why not track hours and cap levels by them: player characters grow much faster than the hours scale. In PR #100's simulation, with 10 rolls a day a skill goes from 3 to 10 in a median of 9 nights, against 1,250 practice hours on the scale. Adventure is dense practice at the edge of failure, and a cap would stop the growth Fredrik just tuned. It would also be a second growth engine to keep in step with the first.

**Where hours do feed growth: downtime practice.** A character who spends hours deliberately practising (a new `practise` action, or `wait` with a skill named) gets Elixir-simulated rolls at a fixed rate, for example one roll per 2 hours of practice. Their failures bank LP like any other failure, and the practice counts as reflection for skills at 10+ (as `TalesForge.Game.Reflection` already does for the words "practise", "drill", "spar"). This keeps "growth only from failure", needs no new engine, and gets slower at high levels by itself, because a skilled character fails less often and each roll costs more LP. The rate is open question 7.

**Trainers** stay as in #100: a day with a trainer is one free attempt at +5, paid at the trainer's day rate (§3.3), and it counts as reflection.

## 5. What stays from the old skills design

| Old idea | In the game today | Proposal |
| --- | --- | --- |
| Tiers Novice 1-5, Adept 6-10, Expert 11-15, Master 16-20 | names only, in GM text; `core_mechanics.md` still mentions stat minima per tier, which no code applies | replaced by five narrative bands: Novice 0-3, Apprentice 4-7, Journeyman 8-11, Expert 12-15, Master 16-20 (§2.1) |
| Scaled LP thresholds (5/7/10/15 LP, harder rolls, trainer required at 16+) | only in the `baseline` variant (`Progression.Tiered`) | replaced by #100 (`ceil(level / 3)` LP per roll, roll at least 11 and the level) |
| Five domains and their skill lists | GM text only; the lists name skills the game doesn't have (smithing, medicine, cooking…) and miss two it has (survival, tracking) | redo the lists against the game's 17 skills (`Mechanics.skill_stat_map/0`) |
| Domain floors (2 at 10, 4 at 15, 6 at 18) | GM text only, no code | open question 8 |
| Summit Sight (18+) and Attribute Echo (+1 to +3 to stats) | GM text only, no code; the GM is told a level-15 fighter has +2 STR, DEX and CON that Elixir never applies | open question 8 |
| Trainer at least 5 levels above the student, +5 to the roll | in code (`Train.qualify/6`, `Progression.train/3`) | keep |

## 6. The drift to fix

| # | Drift | Numbers | Fix (later PR) |
| --- | --- | --- | --- |
| 1 | **The smith's short sword is about 8× under the doc.** | Hilde's stock has the short sword at `price_copper: 60` (6s; her hook text says the same). The doc's common sword is 1g = 500c: 8.3× more. But the doc is itself 4-6× over its own anchor (see 4), so matching it is not the fix. | By the rule: an anchor of 120c of labour, about 240c with materials (§3.5); the price on a given day moves with the modifiers (§3.6). Also give the smith a real level in a smithing or crafting skill: today she is derived as a `laborer` with melee 6 and history 5, and the game has no craft skill at all. |
| 2 | **Starting coins use the old table, not the budget model.** | `CharacterCreation.finalize/1` takes coins from `Defaults.derive/3`, which returns `standings.<standing>.coins`, the legacy `STARTING_WEALTH` table (commoner 0g 20s 300c = 500c). The kit (travel cloak, hunting knife) comes free on top. `priv/rules/economy.md` tells the GM the opposite: gear is paid out of the budget. The legacy totals equal the budgets for every class (26,000c, 5,700c, 4,000c, 500c, 50c), so the fix is small in coins but real: subtract the kit. | Starting coins = budget − kit value, in Elixir. Price the kit (the cloak has no price anywhere; the knife is 15c today, 50c by the rule). The legacy table was kept in the rules text on purpose until now ([decision 2026-10-08](decisions.md#2026-10-08-clarification-the-code-and-its-docs-stand-alone-where-the-code-came-from-is-recorded-here)); it can go with this fix. |
| 3 | **Trainer fees are hand-set.** | Seven non-zero `fee_copper` values in Tin Valley, from 10c to 80c, with no link to level. The three level-9 trainers charge 20c, 50c and 80c, a 4× spread for the same level. The stable lad (stealth 8) charges 10c, the smith (melee 6) 40c. One fee per NPC whatever skill they teach. | Anchor fee = `day_rate` of the trainer's level in the skill taught (§3.3), computed in Elixir; the actual fee is the anchor × modifiers (§3.6), recorded with reasons. Drop `fee_copper` from the pack files, or turn it into a standing modifier with a reason (for example "only persuasion teacher to guild standard", scarcity ×1.5). |
| 4 | **The economy doc contradicts itself on pay.** | Unskilled: the services table says 5-10c a day; "1c = about 20 minutes of unskilled work" makes it 24c for an 8-hour day; "1s = half a day unskilled" makes it 20c. That is 2-5× apart. Skilled: the anchor (2g a month) gives 40c a day, "1s = 3 hours" gives about 27c, the services table 20-30c. Items: the sword is "1g, 2-3 days of skilled work", but the same doc says 1g is 2 weeks; the dagger is "10s, 4-6 hours", but 4-6 hours at "1s = 3 hours" is 13-20c; boots are "15s, a full day". The item prices are 4-6× the doc's own labour anchor. | One wage curve (§3): unskilled 10c a day, so 1c is about an hour of unskilled work and 1s is a quarter of a skilled day (about 2 hours). Rewrite the coin-equivalent lines and the item tables from it. |
| 5 | **`priv/rules/skills.md` mixes the models.** | On `main` it has the hours table and the formula that disagree (§2), the 2026-10-07 "one LP, one attempt, spent every turn" section, domains, floors, Summit Sight and Attribute Echo that no code applies, and the old "+1 LP per roll" for Summit Sight. PR #100 rewrites the LP section and drops the "+1 LP" line but leaves the rest. `core_mechanics.md` still has tier stat minima and "20-30 skill points" next to the real 25-point budget. The same text is copied into `priv/adventures/tin_valley/rules/` and `priv/adventures/crossroads_ledger/rules/`. | After #100 merges: one rules text that says only what Elixir applies (hours formula, #100 growth, trainers, wage rule), with unimplemented ideas moved to [Future ideas](future-ideas.md) or implemented. Golden prompt fixtures change with it, so it is its own PR. |

## 7. Who does what: Elixir, Jev or the LLM

By the [call-type rule](call-types.md) (and the walkthrough on `/team`): known structure in and out is Elixir; free text in, typed answer out is Jev; prose out is the LLM.

| Work | Call type | Where |
| --- | --- | --- |
| `hours(level)`, the band for a level, `day_rate(level)`, monthly wage, hourly rate | **Elixir** | a new pure module, for example `TalesForge.Game.Economy`, with doctests for the tables in §2.1 and §3 |
| Anchor trainer fee from the trainer's level in the skill taught | **Elixir** | `Train.qualify/6` calls it instead of reading `fee_copper` |
| Anchor hire price: day rate × job danger label × days | **Elixir** | |
| Anchor item price from labour days, intensity, maker's level and materials | **Elixir** | at pack load, or as a test that fails when a pack's anchor drifts more than, say, 25% from the rule |
| The range for a deal: the anchor, each modifier's band, the overall 0.5×-3× clamp | **Elixir** | `Economy`; the bands are data, not code |
| Modifiers that come from known state: relationship from the NPC's attitude, haggling from the persuasion roll, scarcity when the world knows how many sellers are free | **Elixir** | from session and world state, not read from text |
| Modifiers that come from the scene: scarcity, demand, danger and leverage, each a value inside its band with a short reason | **Jev** | fields on the typed deal; the GM may propose them instead through a typed field (open question 6), never as a free price |
| Clamping each modifier to its band and the product to 0.5×-3×, computing and recording the final price (anchor, modifiers, reasons, clamp, price) | **Elixir** | in the hire, purchase or training event |
| Starting coins = budget − kit value | **Elixir** | `CharacterCreation.finalize/1` / `Defaults.derive/3` |
| Coin maths, affordability, paying | **Elixir** | already `TalesForge.Game.Inventory` |
| Growth: LP, rest rolls, downtime practice rolls | **Elixir** | `TalesForge.Game.Progression` (#100) |
| Reading a hire or a job offer from the player's words: which NPC, what job, safe/risky/fight, how many days, whether the player haggles | **Jev** | a field on the typed intent (`TalesForge.Game.JevIntent`) |
| Classifying an item the player asks for that has no price: category and size labels from a fixed list, never a number | **Jev** | Elixir then prices it |
| Which skill the player practises or reflects on | **Jev** later; the `Reflection` regex today | |
| Narrating the deal, the haggling, the trainer's lesson, and how skilled someone is | **LLM** | gets the final price and the modifiers' reasons in its per-turn facts, as it already does for stock ([world agents round 2](design-world-agents.md#round-2-results-2026-10-07)), and a band with flavour rather than an hours number; it never invents a price |
| Authoring labour days, intensity and materials for new pack items | author (human or a writing bot), checked by the Elixir drift test | not a turn call |

## 8. Open questions for Fredrik

Answered by the 2026-10-09 guidance and dropped or folded in: whether trainer fees can carry scarcity or standing (yes, as modifiers, §3.3), and how exact the hours scale is (a narrative band over an anchor formula, §2.1).

1. **Hours anchor and bands:** keep the formula `10,000 × (L/20)³` as the anchor behind the bands, and are the five bands and their edges right (Novice 0-3, Apprentice 4-7, Journeyman 8-11, Expert 12-15, Master 16-20)?
2. **Wage curve (the anchor):** `10c + 30c × (L/10)^1.5` (pay grows with the square root of practice hours): unskilled 10c, skilled 40c, master 95c a day. Right shape and right fixed points?
3. **Which level is the anchor's "skilled craftsman":** 10 (as proposed), or the NPC master at 12?
4. **Materials:** one materials factor per item category (×2 for iron goods), which puts the short sword's anchor at about 240c (24s), not the doc's 1g. Or should the old doc's item prices win and the wage curve move up to match them?
5. **Modifier bounds:** overall clamp 0.5× to 3× the anchor, with the per-modifier bands in §3.6 (scarcity 0.8-2.0, demand 0.9-1.5, danger 1.0-1.5, leverage 0.7-1.5, relationship 0.8-1.2, haggling 0.85-1.15). Right bounds? Should a trainer's teaching premium be a modifier or part of the anchor?
6. **Who picks the scene modifiers:** Jev only (typed, tested in the intent eval), or may the GM also propose them through a typed field that Elixir clamps the same way?
7. **Danger split:** the job's label stays in the anchor (safe ×1, risky ×1.5, fight ×2) and the trip's extra danger is a modifier (1.0-1.5). Or move all danger into the modifiers?
8. **Downtime practice:** feed growth through simulated rolls (one per 2 hours of practice?) that bank LP on failure, or keep hours purely a narrative band?
9. **Domains, floors, Summit Sight, Attribute Echo:** build them in Elixir, or take them out of the GM's rules text until they are built?
10. **Trainers for player characters:** the 5-level gap means today's level-9 trainers can only teach skills at 4 or lower, so nobody in Tin Valley can train a new character's 5-7 skills. Add trainers at 12-14?
11. **A craft skill:** the game's 17 skills have no smithing or crafting, so makers have no level to price their work by. Add one (crafting), or price makers by a derived occupation level?
12. **Starting kit:** subtract the kit from the starting budget (commoner 500c minus the cloak and knife), at anchor prices?
13. **Order of work:** after #100 merges, (a) the Elixir economy module (anchors, bands, modifier clamp) and the drift test, (b) starting coins, (c) pack prices and trainer fees, (d) Jev's modifier fields and their eval cases, (e) one clean rules text. Each its own PR with your OK?
