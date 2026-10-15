# Starting State

> The "New Game" snapshot for Merovingia — what's happening when play begins.

*Last updated: 2026-01-18*

---

## Purpose

This folder contains the **Starting State** for the Merovingia module — the canonical "current events" snapshot representing the world at the moment a new game begins.

Think of it like the "Current Events" section in a pen-and-paper RPG module: not history or geography (which never change), but the living situation players enter.

## Relationship to Other Content

| Content Type | Location | Nature |
|-------------|----------|--------|
| **Eternal Canon** | `modules/merovingia/*.md` | Geography, history, core personalities — immutable |
| **Starting State** | `modules/merovingia/starting-state/` | Current positions, active concerns — the "New Game" snapshot |
| **Player Timeline** | `campaigns.world_state` (DB) | Player's divergent reality — mutable during play |

The Starting State is **read-only during play** — it serves as the template that gets copied to a player's timeline when they begin.

## Contents

### `schema.ts`

TypeScript interfaces defining the structure of Starting State data. Used by the game engine to validate and process the starting configuration.

### `starting-state.json`

Machine-readable snapshot containing:
- All 12 baron/baroness starting positions and concerns
- 3 guild ambassador positions and agendas
- Court figures (Malaric, Queen Mother, Sir Percival)
- Active tensions at starting intensity
- Initial rumor pool

### `starting-state.md`

Human-readable narrative version — "When play begins..." — describing the world situation in prose. Useful for GMs and for understanding the "why" behind the JSON data.

## Design Principles

### What's Included

- **NPC positions**: Where key figures are at game start
- **Active concerns**: What's driving NPC behavior right now
- **Tension levels**: Which rivalries are currently "hot"
- **Rumors**: What's being whispered at tick 0
- **World time**: Day, hour, phase when play begins

### What's NOT Included (stays in Eternal Canon)

- Geography and climate
- History and legends
- Core NPC personalities (OCEAN, Maslow levels)
- Alliances and tensions (the *existence* of these is canon; their *intensity* is starting state)

### Granularity

- **Named NPCs**: All barons, ambassadors, court figures (~25 NPCs)
- **Template NPCs**: Generic guards, merchants generated per-location at runtime
- **Concerns**: Only active concerns, not all possible concerns
- **Tensions**: Only tensions currently "warm" at game start

## Usage by Game Engine

When a player starts a new timeline:

1. Engine loads `starting-state.json`
2. Validates against `schema.ts` interfaces
3. Copies to player's `campaigns.world_state`
4. References `docs/merovingia/*.md` for Eternal Canon lookups
5. Player's timeline diverges from this baseline

## Module Portability

The Starting State is part of the **Merovingia module**, not the game engine. Different campaign modules could have different Starting States, but the engine loads them the same way.

This allows:
- Multiple "eras" of Merovingia (different starting years)
- Alternate history scenarios
- Other worlds entirely with their own starting states
