# Notes: GameCharacter 10e AFTER run, 2026-10-18

Playtest only. Session [3705591b](https://tales-forge-playtest.fly.dev/play/3705591b-f2f8-4f03-8114-fca1368b6ff1), Tin Valley, quick start Elara Voss. Build "PLAYTEST 4a2b01e" (10e / #445 is in) for every turn; checked at the start, after T9, after T21 and after T38. #446 (sell fix) and #448 (NPC tick delta) merged at 10:48 CEST during T22 but were not on playtest during the run, so neither affects these results. 38 script inputs, 42 entries with sub-turns, 10:41:49 to 10:51:10 CEST. Script: `../2026-10-18-10e-before/script.md`, replayed word for word. Full turns: `transcript.md`. Item-by-item comparison: `comparison.md`. Screenshots: `admin-session.png`, `play-final.png` (both include the browser frame; the admin one shows only the top of the page).

The expectation was no behaviour change from 10e. The run mostly matches that, but the LLM's prose varies a lot run to run, and a few engine-side differences showed up (clarify boxes, a counterattack line, no Melee gain, a new `npc_moods` map).

## Main findings

1. **Memory recall still fails.** At T2–T3 Brenna echoed Wren, Kestrel Ford, Thistle and the cut road, but already added things I never said ("Wren Voss", tin lanterns, a white blaze, Caldern as kin). At T35 my sister became "Caldern Voss", a miner at the tin shaft behind a blue door. At T36 the mule became "Daisy", grey with a notched ear, lost two nights back near the yard. Only "grey" is right. At T37 Brenna said she hasn't seen a drover since last week, although she herself placed Mags in the yard at T7b–T9. She did correctly list the two ales as my only purchases. No 💭 thought on any turn; no memory or thought data anywhere in admin.
2. **The drover can't be reached.** T7 and T8 now raise clarify boxes whose options leave Mags out as a person to talk to: "talk to Brenna Holt, or go to Mags Ferrow?" and "talk to Brenna Holt, or buy Mug of Ale?". Brenna answered for her both times. At T9 "I buy a coil of rope from the drover" became a second ale from Brenna (−2c, Mug of Ale ×2). Brenna quoted the rope at 12 silver (T8b) and then 4 silver (T9).
3. **Hilde refused a valid knife purchase.** At T17 she said I offered no coin ("I don't hand over steel for nothing") while I had 2g 9s 5c. Prose and sheet agree that nothing moved, which is better than the before run's prose-only sale. But at T18 she said "I just sold you that knife fresh from the rack", which contradicts T17.
4. **Gifts and free food still happen only in the prose.** Maude accepted the rope I never had and gave a tool pouch and two poultices that never reached the sheet (T24). Brenna gave free ale, bread or stew on T1, T2, T7b, T10, T10b, T11, T30, T35 and T36, all prose only. At T20 Hilde dropped my copper on her anvil in the prose; the sheet kept it.
5. **Combat still produces no wounds, and T28 still hits the wrong target.** T27 was a Persuasion critical failure (98 vs 25) with a prose rib crack and wounds 0/3. T28 "attack the biggest toll man" rolled against a newly spawned "a man (minor foe)" while the prose had me fighting Cobb and Cobb's club hitting me ("No counterattack" in the roll line). T29 rolled against Cobb and, new this time, printed a counterattack line: `Counterattack: d100 64 vs 20 (unarmed_combat 40, Elara Voss's Parry 70): miss.` Two questions: Cobb swings a club in the prose but the line uses unarmed_combat, and Elara's Parry 70 doesn't match anything on her sheet (Melee combat 10%). Melee stayed at 10 (before: 10 to 15 on a miss). Cobb's Parry read 52 (before: 57).
6. **NPCs still act a lot on their own; disposition still 0.0 everywhere, but a new mood map exists.** Cobb and Rusk joined PRESENT on idle T5 again. At T13 they walked out of the inn in the prose but stayed in PRESENT. Brenna pitched Osric's job on nearly every turn and repeated her opening greeting word for word at T1. Admin: all ten NPC instances show disposition 0.0. New in the world state: `npc_moods` with stance, emotion and intensity for six NPCs (Cobb hostile/irritated 0.95, Rusk hostile/wary 0.63, smith cool/irritated 0.76, herb_wife warm/calm 0.4, innkeep warm/calm 0.28, guild_steward neutral/irritated 0.19). The PRESENT tags still say "troubled" for everyone.
7. **Stitching (T32) is now consistent with the sheet.** The input raised a clarify "talk to Old Maude, or pay?" that splits one sentence into two actions. On "talk", Maude said "There's not a mark on you worth the needle", which matches 0/3 wounds (but not the rib prose of T27–T29), and nothing was charged.
8. **Engine word in the prose.** T34: "At the fourth tick the innkeep wipes her palms…". Not a prompt leak, but "tick" is engine vocabulary.

## Movement and clock

- T10 "I go out to the inn yard." failed twice again (T10b). The GM now says the door "doesn't budge" and is "for coming in".
- T11 (talk to the stable lad) no longer moves the player. Brenna said the lad, Pip, "is not here tonight", yet at T12 a stable lad took my copper (−1c) and left for the yard. Admin has Tam the stable lad in inn_yard and Pip on west_road.
- The clock went evening (T6–T12) to night (T13–T21) to late night to witching hour with no step backwards. The T14 arrival text says "evening settles" while the header says night.
- T22 moved straight to Maude's cottage with no clarify. T25, T31 and T33 all moved correctly the first time.
- T30 still goes from the adit into the inn in one turn.
- T38 "wait by the hearth until evening" again jumped to Day 2 · evening (world_tick 144), and the prose reads like the same night.

## Admin snapshot after T38 (read only)

world_tick 144, world_clock "Day 2 · evening". NPC locations: cobb and rusk old_adit, innkeep valley_inn, smith smithy (stock 3), herb_wife herb_cottage, drover inn_yard (stock 3), pip west_road, guild_steward market_square, prospector mine_workings, stable_lad inn_yard. The spawned "a man" is in `npc_state` at old_adit (0/1 wounds) but not in the NPC instances list. `combat_last` holds the T29 line. Outcomes: critical_failure on admin turn 28, partial_success on 29 and 30, none elsewhere.

## Timings

My slow-turn threshold is 20 s. No turn reached it. Measured turns took 5.0–7.5 s (T1–T9) and 5.4–7.4 s (T23–T38). Block B–C (T10–T21) logged only a range of about 2–10 s per turn. Clarify boxes came back in 0.8–1.7 s. The first page load took about 0.5 s.

## Safety

No GM prompt or system text leaked. Nothing was attempted against prod.
