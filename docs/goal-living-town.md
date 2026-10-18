# Goal: a living town

- Owner: Fredrik Pahlén (founder)
- Written: 2026-10-18 by Case (architect)
- Status: long-term technical goal. Not scheduled. No build cards.

## Why this document exists

This goal is a yardstick. Use it to find gaps in the system when you review a design or a PR. Ask: "Would this work for the living town?"

## The goal

One player session lasts 100 hours of play. It takes place in one large town. The town has 1,000 GameCharacters. They live a simulation:

- Concerns grow and fade.
- Moods change.
- Routines go on.

This happens whether or not the player is present.

## What it builds on

- One GameCharacter. A PC and an NPC differ only at intention input. See the [refactoring plan](https://github.com/whyse-ab/ex-tales-forge/blob/main/docs/plan-tf-refactor-2026-10-17.md) (GameCharacter 10a–10f).
- Concerns with intensity and growth rate on every GameCharacter. For a GM-controlled character, concerns feed the Intention. For a human-controlled character, they feed a GM hint.
- One World.Instance process per session. See [Design: GC 10f, one process](https://github.com/whyse-ab/ex-tales-forge/blob/main/docs/design-gc-10f-one-process.md).
- State in Postgres. Process state is a cache. See [Design: persistent world state](https://github.com/whyse-ab/ex-tales-forge/blob/main/docs/design-stateful-world.md).
- Trade conservation. Items and coins always change place. Nothing is created or destroyed.

These follow the [principles](https://github.com/whyse-ab/ex-tales-forge/blob/main/docs/principles.md), mainly "pure core, effects at the edges".

## Key design idea: cheap rules for everyone, AI only near the player

- The town ticks as pure functions over structs: concerns, moods, routines.
- The LLM is called only in two cases:
  - for characters in the player's scene;
  - when a threshold crossing becomes a story event.
- Off-screen characters may tick coarser, for example once per game hour. They catch up lazily when the player arrives.

## Riskiest assumptions

1. AI cost per game hour. CPU is not the main risk.
2. Storage growth and memory over 100 hours.
3. Consistency between story and state. Today's playtests show the GM's prose drifting from the sheet. A living town makes this worse.

## Gap questions for any design

Ask these of every design and PR:

- [ ] Does it work for 1,000 characters? Or does it loop over all of them each turn with an LLM call?
- [ ] Is the state in the database, not only in the prose?
- [ ] Is every change conserved? No item or coin is created or lost.
- [ ] Can an off-screen character catch up from stored state?
- [ ] Does memory stay bounded, and does recall stay correct, over 100 hours?
- [ ] Can time pass without the player (ticks, catch-up)?
- [ ] Is the cost per turn independent of town size?
- [ ] Is position one fact (`location_id`) that presence is derived from?

## Known gaps today

From the 2026-10-18 playtests ([before](https://github.com/whyse-ab/ex-tales-forge/blob/main/docs/playtests/2026-10-18-10e-before/notes.md), [after](https://github.com/whyse-ab/ex-tales-forge/blob/main/docs/playtests/2026-10-18-10e-after/notes.md)):

- Trades, gifts and wounds exist only in the prose.
- NPC presence exists only in the prose.
- Dispositions stay at 0.
- Memory recall invents facts.
- Buy-intent gap.
- An absent trader's stock is not in the prompt.
- The clock and movement drift.

### Space

What exists:

- A place graph with exits (pack locations).
- `GameCharacter.location_id`.
- Behind the flag `HIERARCHICAL_LOCATIONS`: a place tree. Each place has a parent, a position (at `[x, y]`), a scale (building, settlement or region) and `cell_m`. Travel time comes from distance (`Game.Travel`, `Game.Movement`, `Game.WorldClock` with 15-minute ticks).

Gaps:

- Places live as a JSON map in `world_state`, copied from the pack. They are not their own data.
- The place tree is behind a flag.
- Only the player moves. NPCs have no routines that move them.
- There is no "who is near" query.
- The scene PRESENT list is separate from the characters' `location_id`. The two drift: NPCs leave in the prose but stay present.

## First experiment (when picked up, not now)

A script runs 1,000 generated characters through 100 game hours. Rules only, no LLM. Measure:

- ticks per second;
- database size;
- the number of threshold-crossing events per game hour. This number sets the AI bill.
