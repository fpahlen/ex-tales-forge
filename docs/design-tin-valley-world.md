---
title: "Design: the Tin Valley world around the inn, and its antagonist"
updated: 2026-10-08
---

# Design: the Tin Valley world around the inn, and its antagonist

**Status:** built, merged and deployed on 2026-10-08 (prod release v70 and playtest v59 run `9e7d447`, flags on for playtest only). It follows two decisions from 2026-10-07 ([build out the inn for every player type](decisions.md#2026-10-07-build-out-the-inn-and-its-surroundings-for-every-player-type-record-scene-changes), [Hawk gets an antagonist who acts on their own](decisions.md#2026-10-07-hawk-gets-real-conflict-a-minor-antagonist-who-acts-on-their-own)). The work is split into ex-tales-forge PRs:

- **PR A**, [#68](https://github.com/whyse-ab/ex-tales-forge/pull/68): leaving a place is recorded as a scene change, and the prompt says where the character is and who is there. This is a bug fix with no flag. Merged 2026-10-08 as `7b88dad`.
- **PR B**, [#72](https://github.com/whyse-ab/ex-tales-forge/pull/72): the new places and people (`INN_WORLD`). Merged 2026-10-08 as `9080cb1`.
- **PR C**, [#73](https://github.com/whyse-ab/ex-tales-forge/pull/73), stacked on #72: the antagonist (`WORLD_ANTAGONIST`). Retargeted to `main` after #72 and merged 2026-10-08 as `9e7d447`.
- **Fight rolls**, [#71](https://github.com/whyse-ab/ex-tales-forge/pull/71): more attack phrasings count as combat, so they roll. This is a bug fix with no flag (the goblin fight with no roll). Merged 2026-10-08 as `8bf10d3`.

This note is meant to be small enough to build now. Everything is pack data plus a few generic front moves, and **no new LLM call type**.

## Why

In the [Jev baseline](analysis-jev-baseline-2026-10-07.md), players try to leave the inn in 62% of runs. But the world has only the inn, the square, the mine and the orc cut, and leaving wasn't recorded (PR A fixes that). Each persona runs out of things it likes. Hawk gets chores (Brenna's "lend a hand" hook) and scores 2.54 without a fight roll against 4.61 with one. Lars's adventure gets put off, and Paul's speech to Osric gets answered by Brenna.

## Places

The base pack keeps its five places: Valley Inn, Market Square, Mine workings, the Cut above the nest (a checkpoint) and the Orc nest. `INN_WORLD` adds five more. Every new place is one or two exits from the inn, so a 10–12 turn session can reach them.

```
                 herb_cottage   smithy
                          \      /
 inn_yard ── valley_inn ── market_square ── orc_approach* ── orc_nest
     \______________________/   |    \
                         mine_workings  west_road ── old_adit
                                              (* checkpoint: travel stops there)
```

| id | Name | Exits | What is there |
| --- | --- | --- | --- |
| `inn_yard` | Inn yard | valley_inn, market_square | Stable, woodpile, well, drovers' wagons. The inn's back door. |
| `smithy` | Brask's forge | market_square | Forge, anvil, a rack of blades and tools. A back door onto the lane. |
| `herb_cottage` | Maude's cottage | market_square | Drying herbs, a cot for the sick, shelves of jars and old miners' keepsakes. |
| `west_road` | West road | market_square, old_adit | The drovers' road down-valley under the pines. Cart ruts, and the place where loads go missing. |
| `old_adit` | Old adit | west_road | An abandoned mine entrance in the pines, with old carvings. It's the Tinjacks' hideout (PR C). |

Each place has `aliases` so movement understands the ways players name it ("the yard", "the forge", "the old mine"…).

## People

| id | Name | Where | Who | Drives |
| --- | --- | --- | --- | --- |
| `innkeep` | Brenna Holt | Valley Inn | Innkeeper (unchanged) | talk, food and a room, leads |
| `guild_steward` | Osric Vane | Market Square | Miners Guild steward (unchanged) | orc contract, bounties, Guild standing |
| `prospector` | Caldern Voss | Mine workings | Guild pick (unchanged) | the hill, the mine, guide to the cut |
| `stable_lad` | Tam Holt | Inn yard | Brenna's nephew, 14. Quick, nosy, sees who comes and goes at night | sneak (back ways), chores, gossip, clues |
| `drover` | Mags Ferrow | Inn yard | A drover who lost a salt cart on the west road | trade (salt, rope, lamp oil, mule hire), a bounty to get her load back |
| `smith` | Hilde Brask | Brask's forge | The village smith, blunt and proud. She has been buying "cheap tin" and doesn't ask where it comes from | trade (blades, repairs), crafts (help at the forge), lore (stamps on ingots and old tools) |
| `herb_wife` | Old Maude | Maude's cottage | Herb-wife and healer, the village's memory | healing, lore (old miners, the thing below, orc ways), talk |

The `WORLD_ANTAGONIST` flag adds three more (PR C):

| id | Name | Where (start) | Who |
| --- | --- | --- | --- |
| `rusk` | Rusk | Old adit | A deserter from the levy who leads the Tinjacks. Cold, patient, smiles a lot |
| `cobb` | Cobb | Old adit | Rusk's brute. Slow to talk, quick with a club |
| `pip` | Pip | West road | The gang's lookout, 15, and Maude's grandson. Scared, and in too deep |

## Activities by player type

Each activity type has a real hook: a place, a person who carries it, and (where it fits) a skill that rolls.

| Activity | Where | Driven by | Rolls |
| --- | --- | --- | --- |
| Talk | inn, yard, square, forge, cottage | Brenna, Tam, Mags, Osric, Hilde, Maude, Pip; Jev reactions when `NPC_REACTIONS=on` | persuasion, insight, deception (only when the outcome is uncertain) |
| Trade | inn, yard, forge, cottage | Brenna (food, room), Mags (supplies), Hilde (blades, repairs), Maude (salves); prices from world-agent facts when `WORLD_AGENTS=on` | none (prices from the server) |
| Explore | west road, old adit, mine, cut | the places themselves; tracks on the west road | survival, tracking, climbing |
| Sneak | yard (back door), smithy lane, old adit | Tam shows the back ways; Pip watches the road (PR C) | stealth (an enter trigger at the old adit) |
| Fight | inn or old adit (Tinjacks), cut and nest (orcs) | the Tinjacks front (PR C), the orc nest front | melee, ranged and unarmed combat; failure wounds (server) |
| Lore | cottage, forge, old adit carvings | Maude, Hilde, Caldern | history, arcana |
| Crafts and chores | forge, yard | Hilde (work the bellows, sharpen), Tam (mend harness, muck out) | none (everyday work earns a meal, coin and gossip) |
| Heal and rest | cottage, inn | Maude (stitches and salves), Brenna (room) | none |

How each persona finds what they like:

- **Hawk (hard mode):** the Tinjacks come to the inn for their "road toll" on their own, so a fight finds him even if he stays put. He can also hunt them on the west road or storm the old adit. These are real combat rolls, and failing one costs a wound.
- **Lars (adventurer):** quests he can finish and get paid for: Osric's orc contract, Mags's bounty for her salt cart, and the Guild's ingots. Osric's growing regard is his visible progress.
- **Paul (role play):** talking Pip out of the gang for Maude's sake, facing Rusk down with words, preaching to the square. Persuasion, not swords.
- **Lotta (identification):** a lived-in village. She can work the forge with Hilde, muck out with Tam, hear Maude's old stories, and earn a name with the people she helps.
- **Ronny (win):** haggling with Mags and Hilde, the Tinjacks' stash, and Rusk offering him a cut, which he can take or betray.

Brenna's own hooks stay as they are (another change owns how the GM plays Brenna). The new people carry the new hooks. The new hooks give action players a lead other than chores.

## The antagonist: Rusk and the Tinjacks (PR C, #73)

- **Who:** Rusk, a deserter from the levy, with his brute Cobb and the boy Pip as lookout. They call themselves the Tinjacks and hide in the old adit off the west road.
- **Goal:** get rich on the valley's fear. They rob drovers on the west road and let the orcs take the blame, sell the loads through Hilde's back door, and squeeze the village for a "road toll" while the Guild's men are busy with the cut.
- **How they act on world time:** a front, `tinjacks`, with a clock called `trouble`. The clock advances with every world tick that passes (every turn is at least one 15-minute tick; waiting and sleeping are more), whether or not the player engages. No LLM is involved: the move happens in `WorldSim.tick/1` during the turn.

| `trouble` | Stage | What happens in the world | Who perceives it |
| --- | --- | --- | --- |
| 0 | rumour | Another salt cart vanished on the west road. Folk blame the orcs, but orcs never come down that far. | inn, yard, square |
| 3 (~45 min) | incident | Someone clubbed the Guild's night watchman and took tin ingots from the weighing shed. Boot prints lead west, and there's no orc sign. | square, inn, yard, forge |
| 6 (~1.5 h) | confrontation | Rusk and Cobb come down to the Valley Inn and collect a "road toll" from Brenna and her guests: coin or a beating. They are **present** at the inn. | inn, yard, square |
| 12 (~3 h) | escalation | They burn Mags's wagon in the inn yard as a warning, then go back to the old adit. | whole village |

Each stage fires once, even when a long wait or sleep passes several of them. The confrontation is skipped if the player is on the west road or at the old adit, and the escalation is skipped if the player is at the inn, in the yard, on the west road or at the old adit.

- **How the player meets them:** the rumour from the first turn, then the incident (with clues from Tam, Hilde and Mags). Rusk and Cobb walk into the inn at the confrontation stage. Or the player goes to them: the west road, then the old adit. Entering the old adit without a successful stealth check means Pip whistles, and the Tinjacks stand ready.
- **Fights use the real combat rules:** an attack on Rusk or Cobb is a `combat` action, so it always rolls ([#71](https://github.com/whyse-ab/ex-tales-forge/pull/71) widens the attack phrasings that count as combat). Two successes break the gang. A failed combat roll wounds the character through the existing server harm.
- **Other ways to win:** talking Pip round (a persuasion, intimidation or insight success aimed at Pip) sends him home to Maude, and he gives up the hideout: where the loot is and when Rusk sleeps. It does not slow the clock. Bargaining with Rusk (he offers a cut) is left to the GM; it has no mechanics.
- **How the outcome feeds back:**
  - **Broken:** the front stops. A village-wide perceived fact says the Tinjacks are broken and where the stolen goods are. Osric and Brenna remember who helped (memory moves), so Osric's regard and Brenna's welcome follow.
  - **Ignored:** the clock runs on to escalation, the village is poorer and more afraid, and the facts say so.
  - **Lost:** wounds, and the front remembers the stranger who tried them and bled for it.

## How it is built

- **Pack extensions:** `priv/adventures/tin_valley/extensions/<name>/` holds `world/`, `npcs/`, `fronts/` and an optional `extension.json`. The extension's new exits are added to base places in both directions, and it can append hooks to base NPCs. `Pack.load/3` merges an extension only when its feature is on for the session.
- **Features are fixed per session:** when a session is created, its features (`inn_world`, `antagonist`) are written into `world_state["features"]` from the env flags. Turning a flag on or off changes new sessions only, the same way `variant` works.
- **Fronts (PR C), generic additions:**
  - clock `stages` (the value at which a stage fires, its public fact, and which people move where);
  - generic pack moves (public fact, memory, move people, set status);
  - `combat` and `check` triggers on fronts (target, skill, outcome → event);
  - presence recomputed after the tick, so people who arrive this turn are present this turn.
- **The baseline variant** loads no extensions and keeps its old prompts.

## Flags

These are env vars, read when a session is created. They are not secrets: they go in `fly.playtest.toml` `[env]`, not in `fly secrets`.

| Flag | Default | Production (`tales-forge`) | Playtest (`tales-forge-playtest`) | What it does |
| --- | --- | --- | --- | --- |
| `INN_WORLD` | off | off (checked 2026-10-08) | on (in `fly.playtest.toml` since #72; checked on release v59) | Adds the five places and four people above to new Tin Valley sessions |
| `WORLD_ANTAGONIST` | off | off (checked 2026-10-08) | on (in `fly.playtest.toml` since #73; checked on release v59) | Adds the Tinjacks front and Rusk, Cobb and Pip; it needs `INN_WORLD` (it is ignored without it) |

Existing flags are unchanged: `WORLD_AGENTS` is off on both apps, and `NPC_REACTIONS` is on on playtest and off on production ([Fly secrets](fly-secrets.md)).

## Cost per turn

- **PR A:** no new call type. Moves phrased as a plan ("I'll head to the square at first light") now go to the Tier 1 intent call, about 6–7% of turns in the replay, at about $0.0003–0.0005 and 0.5–3 s each.
- **`INN_WORLD`:** no LLM calls. The prompt grows only when new people are present, by a few lines.
- **`WORLD_ANTAGONIST`:** no LLM calls (the front is Elixir). When Rusk and Cobb are present on playtest, `NPC_REACTIONS` makes up to 2 extra Jev calls (~$0.00004 each). Perceived facts add 1–3 lines to the per-turn prompt.

## Open questions

- Should the front also tick between sessions (an Oban cron, as in [living world](design-world-agents.md#living-world-design-to-try))? This first case ticks only during turns.
- Companions don't follow the character yet (Caldern "walk with me").
- On a move turn, the GM narrates the arrival and then the scene step describes the place again.
