# Comparison: 10e BEFORE (fa7d6b5/9300b97, session edeac566) vs AFTER (4a2b01e, session 3705591b)

Same script, same world, same quick-start character, same window size. The GM's prose is generated, so wording always differs; this file compares behaviour. Labels: **same**, **better**, **worse**, from the player's point of view and against the house rules (items and coins always change place in a trade; nothing is created or destroyed).

Expectation for 10e: no behaviour change. Most items are the same. The differences below are worth a look because some come from the engine (clarify, combat lines, the mood map), not only from the prose.

## Memory recall of Wren and Thistle

| Item | Before | After | Mark |
|---|---|---|---|
| Planting (T2–T3) | Echoed Wren, lamps, Kestrel Ford, Thistle, cut road; nothing invented. | Echoed them, but added "Wren Voss", tin lanterns, a white blaze, Caldern as kin. | worse |
| Sister recall (T35) | "Mira Voss", ledger keeper for the Guild, blue door. | "Caldern Voss", a miner at the tin shaft, blue door past the weighing shed. | same (fail) |
| Mule recall (T36) | Chestnut with a white blaze, lost from the inn yard. | "Daisy", grey with a notched ear, lost near the yard two nights back. | same (fail) |
| Drover purchase recall (T37) | Correct: nothing bought from her; invented a torched cart. | Correct that I bought only two ales; but says no drover since last week, contradicting her own T7b–T9. | same |
| 💭 thoughts | None. | None. | same |

## Trades and gifts reaching the sheet

| Item | Before | After | Mark |
|---|---|---|---|
| Ale from Brenna (T4) | −2c, Mug of Ale added. | −2c, Mug of Ale added. | same |
| Rope from the drover (T7–T9) | No clarify; drover "packed and left"; no charge. | Clarify boxes with no "talk to Mags" option; the rope buy became a second ale (−2c, Mug of Ale ×2). | worse |
| Copper to the stable lad (T12) | −1c to Pip (on the west road). | −1c to a lad Brenna said "is not here tonight". | same on the sheet |
| Hilde's knife (T17–T18) | Prose sale, no coins or knife moved. | Refused: "no coin offered" while I had 2g 9s 5c. Sheet and prose agree. T18 then says "I just sold you that knife". | worse (a valid buy is refused), though no longer prose-only |
| Maude's rope gift and poultice (T24) | Phantom rope accepted; poultice in prose only. | Phantom rope accepted; tool pouch and two poultices in prose only. | same |
| Maude's stitching fee (T32) | Stitched non-existent wounds; 4c fee never deducted. | Clarify "talk or pay?"; on "talk" she says there's no wound to stitch and charges nothing. | better (prose matches the sheet) |
| Brenna's free food | Free mug and stew at T33–T34, prose only. | Free ale, bread or stew on nine turns (T1, T2, T7b, T10, T10b, T11, T30, T35, T36), prose only. | worse |
| Hilde and the copper (T20) | Refused. | Refused; the prose leaves my copper on her anvil, the sheet keeps it. | same (minor new mismatch) |

## Combat: wounds, target choice, counterattack lines

| Item | Before | After | Mark |
|---|---|---|---|
| T27 laugh | Persuasion 80 vs 25 failure; prose club hit; wounds 0/3. | Persuasion 98 vs 25 critical failure; prose rib crack; wounds 0/3. | same |
| T28 target | Rolled against a new "a man (minor foe)", not Cobb. | Same: new "a man (minor foe)"; prose says Cobb. | same |
| T28 counterattack | "No counterattack"; prose has Cobb swing. | "No counterattack"; prose has Cobb's club hit. | same |
| T29 | Cobb, miss, "No counterattack". | Cobb, miss, and a counterattack line: `d100 64 vs 20 (unarmed_combat 40, Elara Voss's Parry 70): miss`. | better (counterattack resolved), but the line uses unarmed_combat while Cobb has a club, and Parry 70 isn't on Elara's sheet |
| Skill gain | Melee 10 to 15 on a missed swing. | Melee stayed 10. | better |
| Cobb's Parry | 57. | 52. | new difference, unexplained |
| Wounds ever | 0/3 the whole run. | 0/3 the whole run. | same |

## NPC initiative, PRESENT and disposition

| Item | Before | After | Mark |
|---|---|---|---|
| Cobb and Rusk join on idle T5 | Yes. | Yes. | same |
| Caldern approaches on idle T6 | Yes, not in PRESENT. | No. | different |
| Rusk demands a toll inside the inn (T10b) | Yes. | No; only a remark. | different |
| NPCs leaving | n/a | Cobb and Rusk walk out at T13 but stay in PRESENT. | worse (new) |
| Brenna's job pitch | Repeated often. | On nearly every turn; T1 repeats the opening greeting word for word. | same |
| Disposition | 0.0 for every NPC. | 0.0 for every NPC. | same |
| Mood data | None found. | New `npc_moods` map (stance, emotion, intensity) for six NPCs, e.g. Cobb hostile 0.95, smith cool 0.76. Not shown in PRESENT tags. | better (new data) |
| Drover in PRESENT | Never. Admin: inn_yard. | Never. Admin: inn_yard. | same |
| Osric's tag | Raw slug "guild_steward". | Raw slug "guild_steward". | same |
| Spawned foe | "a man" in PRESENT. | "a man" in PRESENT and `npc_state`, but not in the NPC instances list. | same |

## Hilde's refusal

| Item | Before | After | Mark |
|---|---|---|---|
| Buy-back (T18) | Refused. | Refused. | same |
| Free sword loan (T19) | Persuasion 4 vs 25 success, refused anyway. | Persuasion 12 vs 25 success, refused anyway. | same (right outcome, roll ignored) |
| One copper for a sword (T20) | Refused, no roll. | Refused, no roll. | same |
| Unasked offer | Bellows work for a silver (T17). | Bellows work for two silver, plus the Rusk tin worry (T19). | same |

## Movement and clock

| Item | Before | After | Mark |
|---|---|---|---|
| T10 inn yard | Failed twice. | Failed twice ("door doesn't budge"). | same |
| T11 talk moves player | Moved to the West road; clock went back night to evening. | No move; no clock regression. | better |
| T22 Maude's cottage | Clarify despite a clear target. | Moved directly. | better |
| T25, T31, T33 travel | Correct. | Correct. | same |
| T30 adit to inn in one turn | Yes. | Yes. | same |
| T38 wait until evening | Day 2 · evening, tick 144; prose same night. | Day 2 · evening, tick 144; prose same night. | same |
| Arrival text vs header | n/a | T14 arrival says "evening settles" under a night header. | minor new |

## Anything new

- **Clarify boxes with poor options (worse).** T7, T8 and T32 now raise clarifies. None offers "talk to Mags"; T8 offers "buy Mug of Ale" for a rope question; T32 splits "stitch and pay" into "talk" or "pay".
- **Engine word in the prose (new).** T34: "At the fourth tick the innkeep…".
- **Price drift (new).** Rope 12 silver (T8b) then 4 silver (T9). Guild wage 2 silver a day (Brenna, T7b) then 3 silver (Osric, T14).
- **Timings (same or better).** Every measured turn was 5.0–7.5 s; before 5.2–9.4 s with one ~11 s. Threshold 20 s. No slow turns.
- **Safety (same).** No GM prompt or system text leaked.
