# Notes: GameCharacter 10e BEFORE baseline, 2026-10-18

Playtest only. Session [edeac566](https://tales-forge-playtest.fly.dev/play/edeac566-19bd-453c-8adb-8abe941932ed), Tin Valley, quick start Elara Voss. Build "PLAYTEST fa7d6b5" (10d / #438 is in) for turns 1–21. Playtest redeployed to 9300b97 (docs-only #440) during turn 22, so turns 22–38 ran on 9300b97. Same game code. 38 script inputs, 40 game turns, 09:05:30 to 09:18:05 CEST. Script: `script.md`. Full turns: `transcript.md`. Screenshots: `admin-session.png`, `play-final.png`.

## What to compare in the AFTER run

1. **Memory recall fails.** At T2–T3 I told Brenna (innkeep) that my sister Wren makes lamps in Kestrel Ford and that I lost my grey mule Thistle on the cut road. In the same turns she repeated the details correctly. Thirty-three turns later (T35–T36) she made up different answers. She said my sister is "Mira Voss", a ledger keeper for the Guild steward who lives in a stone cottage with a blue door. She said the mule was a chestnut with a white blaze, lost from the inn yard while Tam watched it. She also mixed up identities: "Caldern's girl, Elara—wait, no, that's you". At T37 she said correctly that I had bought nothing from the drover, but she made up the salt cart being "torched in the yard". No 💭 thought appeared on any turn. Playtest runs with CHARACTER_MEMORY=shadow, and a manual session has no Character memory panel. The admin world-state JSON has no memory key.
2. **Trades and gifts mostly happen only in the prose.** Two transfers reached the sheet: the ale at T4 (−2c, Mug of Ale added) and the copper given to Pip at T12 (−1c). Four did not:
   - T17: Hilde "sold" a hunting knife, but no coins moved, no second knife appeared, and her stock stayed at 3.
   - T24: Maude accepted a coil of rope I never had and gave me a poultice pot that never reached the sheet.
   - T32: Maude charged "Four copper" for stitching wounds I didn't have. Nothing was deducted.
   - T33–T34: Brenna gave a free mug and free stew in the prose only.
   This breaks the rule that items and coins always change place in a trade.
3. **The fight never produced a wound.** At T27, after a failed persuasion roll, the prose says Cobb's club "catches you hard across the ribs", but wounds stayed 0/3 and no damage line appeared. At T28, "I attack the biggest toll man" was resolved against a newly spawned "a man (minor foe)" instead of Cobb. The prose describes Cobb swinging back, but the roll line says "No counterattack". T29 hit the right target (Cobb, miss, no counterattack). Melee went from 10 to 15 on a missed swing. The admin summary shows "melee_combat 10 / 15" (trained level 10, roll level 15).
4. **NPCs act a lot on their own, but only in the prose. All dispositions stayed 0.0.**
   - T5 (idle): Cobb and Rusk appeared in the inn and were added to PRESENT. Cobb cracked his knuckles as a warning, and Brenna pitched Osric's job to some miners.
   - T6 (idle): Caldern walked up unasked and mentioned the mule. He was never added to PRESENT.
   - T10b: Rusk demanded a two-silver toll inside the inn and Brenna warned him off.
   - T13 (idle): Pip pointed out lanterns heading to the adit.
   - T14: Osric spoke first. T25: Rusk demanded the toll. T29: Rusk gave a "last chance" warning. T33–T34: Brenna served food and drink unasked.
   - The admin NPC instances list shows disposition 0.0 for every NPC, including Hilde after I insulted her and Cobb and Rusk after the fight.
5. **Some NPCs are spoken for or contradict themselves.** The drover was never in PRESENT. At T7 Brenna answered for her. At T8 the drover answered in prose ("about twenty copper" for rope). At T9 she had "already packed her wagon and left", and Brenna quoted two silver for rope. At T37 Brenna answered for her again. Admin places the drover in inn_yard. At T19 Hilde refused the free sword loan even though the roll line read "Persuasion: d100 4 vs 25: success". The refusal is the right outcome, but the roll result was ignored.

## Movement and clock

- T10 "I go out to the inn yard." failed twice (T10b): the player stayed in the Valley Inn.
- T11, a talk input aimed at the stable lad, moved the player to the West road and put Pip in as the "lad". The time of day went back from night to evening.
- T22 "I go to Old Maude's cottage off the Market Square." got a clarify ("go to Maude's cottage, or do something else?") even though the target was clear. This turn overlapped the 9300b97 redeploy, which may explain it.
- T30, "back away and run toward the Valley Inn", took the player from the adit all the way into the inn in one turn.
- T38, "wait by the hearth until evening", jumped from pre-dawn to Day 2 · evening (world_tick 144). Meanwhile the prose describes Brenna closing up for the night.
- The per-turn admin view has no clock, tick, location or thought field. Time of day per turn comes from the play header and the prose.

## What each NPC did

- **Brenna Holt (innkeep):** warm. She pitched Osric's job and her own work offer again and again (T1–T5, T10, T33–T34). She answered for the absent drover (T7, T37), served food and drink unasked, and invented the memory answers at T35–T36.
- **Cobb and Rusk (Tinjacks):** showed up at the inn on the idle turn T5. They demanded tolls at the inn (T10b) and at the adit (T25–T26). Cobb hit the player in the prose only (T27). Rusk gave warnings (T29). Neither took any wounds.
- **Caldern (prospector):** approached unprompted at T6 about the mule. He never appeared in PRESENT and never came back.
- **Pip (lookout):** stood in for the stable lad. He took the copper (sheet correct), shared the lantern rumour, and warned the player on the idle turn T13.
- **Osric Vane (guild steward):** spoke first in the square (T14). PRESENT shows his raw slug "guild_steward".
- **Hilde Brask (smith):** gave correct prices (T16). The sale happened only in the prose (T17). She refused the buy-back (T18), the free loan (T19, despite the roll success) and the one-copper offer (T20). On the idle turn T21 she told the player to leave. Her stock count stayed at 3.
- **Old Maude (herb-wife):** explained the open hand (T23) and volunteered the "bring Pip home" hook. She accepted the phantom rope and gave a poultice in prose (T24), then stitched non-existent wounds and charged a fee that was never deducted (T32).
- **Mags (drover):** never in PRESENT. She was described as present at T8 and gone at T9.

## Timings

My slow-turn threshold is 20 s. No turn reached it. Measured turns took 5.2–9.4 s, with T10b at about 11 s. T1, T10 and T22 were not measured precisely: the agent's wait loop timed out, and each reply was on screen within 27, 35 and 28 s respectively. The first page load took about 1.0 s.

## Safety

No GM prompt or system text leaked. Nothing was attempted against prod.
