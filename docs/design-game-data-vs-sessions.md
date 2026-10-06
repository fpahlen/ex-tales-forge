---
title: "Design: Game data vs sessions"
updated: 2026-10-06
source: https://docs.google.com/document/d/1hAlHEBjoA3j4i4U8r58WAGHCULVxzkX8mftxsBbd59Y/edit
---

# Tales Forge – Design: Game data vs sessions

**Type:** Architecture Decision Record (ADR)
**Date:** 2026-10-05
**Status:** Accepted (direction)
**Repo:** whyse-ab/ex-tales-forge (Elixir / Phoenix / Ash / Ecto / Postgres)

---

## 1. Context

Tales Forge is an online RPG with an AI game master (GM). The engine has to work for any genre.

Two kinds of data matter here:

- **Game data** is the starting state of a world: rules, characters, NPCs, places and factions. Think of old-school rulebooks and modules. It is written once, read many times, and changes only when someone publishes a new version.
- **A session** is one running copy of a game world. It starts from game data and then changes as players and the AI GM interact with it: NPCs remember things, factions move forward, characters learn and get hurt.

Fredrik's idea: **store and distribute game data as Markdown plus images, and keep sessions in the database.** This ADR turns that idea into a direction for the team.

## 2. Decision: three layers (GURPS-style)

We copy the GURPS model: one core rulebook plus worldbooks.

**(a) Core system: small and guarded**
- Resolution: roll 1d20 ≤ skill.
- Learning by failure: you get better by failing.
- Skill transfer: practice in one skill helps related skills.
- Prices as effort: costs are expressed as effort, not a fixed currency.
- LP (learning points) come from failures.

The core changes rarely and only after review. When in doubt, a rule goes in a pack, not the core.

**(b) Genre packs**
Per-genre rules and lists on top of the core:
- Special systems: magic, cyberware, sanity.
- Skill lists and currency units.
- Death and revival rules, for example:
  - Fantasy: resurrection, with a price.
  - Space opera: a clone with memory gaps.
  - Victorian horror: you come back *wrong*.

**(c) Worlds / modules**
Content: for example Tin Valley, the Mining Guild, NPCs (with OCEAN personality traits and concerns), factions and fronts.
Each module declares which genre pack and which core version it depends on.

**Lesson from GURPS:** keep the core small and push optional rules out to packs.

## 3. Game data format

- **Markdown files with YAML front matter.**
  - Front matter (top): structured fields the engine relies on, such as stats, faction goals, prices and relationships.
  - Prose (below): free text for the AI GM, such as tone, history, secrets and how to play the character.
- **Kept in git.** We get diffs, reviews, version tags and pull requests. Bots and humans can write content the same way they write code.
- **Shareable and forkable** as a folder or package.
- **Images go in object storage, not git.** File names are content hashes (the same image always gets the same name, so no duplicates and safe caching). The Markdown refers to images through a manifest.
- **Import on publish, not per turn.** When a version is published, we import and validate it into Postgres (or memory) with Ash, extending the existing pack importer. Nothing is parsed from Markdown during a game turn.

### Example folder layout

```
core/
  core.md                      # core rules, version in front matter
genres/
  fantasy/
    genre.md                   # depends on core version
    skills.md
    magic.md
    death-and-revival.md
worlds/
  tin-valley/
    world.md                   # module manifest: id, version, genre + core deps
    factions/
      mining-guild.md
    npcs/
      old-mara.md
    locations/
      the-flooded-shaft.md
    images.yaml                # manifest: image key -> content-hash file in object storage
```

### Example NPC file (`worlds/tin-valley/npcs/old-mara.md`)

```markdown
---
id: old-mara
type: npc
name: Old Mara
faction: mining-guild
location: the-flooded-shaft
portrait: old-mara-portrait      # key in images.yaml
ocean:
  openness: low
  conscientiousness: high
  extraversion: low
  agreeableness: medium
  neuroticism: medium
concerns:
  - Keep her grandson out of the deep shafts
  - Expose who sabotaged the pumps
skills:
  mining: 15
  haggling: 11
  lore-tin-valley: 14
relationships:
  guild-master: distrusts
  hawk: unknown
prices:
  map-of-old-tunnels: "a day of hard work"
---

Old Mara has worked the Tin Valley mines for fifty years and talks like
she is still paying for every word. She knows the old tunnels better than
the Guild's maps do.

**How to play her:** short answers, long silences. Warms up only to people
who do real work. If insulted, she remembers it and the price of her help
goes up.

**Secret (GM only):** she saw who left the pump room the night it flooded,
but she is afraid of what the Guild will do to her family if she talks.
```

## 4. Sessions

Sessions live in Postgres.

- **Pinned versions.** Each session records the module, genre pack and core versions it started from.
- **Copy on write.** A session stores only its changes, not a full copy of the module.
- **Recommendation: event log plus snapshots.**
  - Events are small facts in order, for example "guild master's plan advanced" or "Hawk insulted Old Mara".
  - Snapshots save the full current state now and then, so we don't replay from the start every time.

**Benefits**
- **Replay:** rebuild any session at any point.
- **Debugging:** find out why a turn went bad or turned into gibberish.
- **"Previously on…" summaries** generated from recent events.
- **The character museum:** a record of a character's whole life.
- **Reproducible self-play runs:** load module X v1.3, run the Hawk bot, then compare with v1.4.

### Main tables (high level)

| Table | Purpose |
|---|---|
| `modules` | One row per module (e.g. Tin Valley): id, name, owner. |
| `module_versions` | A published, imported version: version tag, git commit, genre and core dependencies, validated content. |
| `sessions` | One running game: pinned module / genre / core versions, players, status. |
| `session_events` | Append-only log: session, sequence number, event type, payload, actor (player, AI GM, bot), timestamp. |
| `session_snapshots` | Full state at a given event sequence number, for fast loading. |
| `characters` | Player characters and their current state; linked to sessions and reachable from the character museum. |

## 5. Versioning

Policy question: should module updates flow into live sessions?

**Proposal:** no, not by default. A session stays on the versions it started from. Fixes (typos, broken stats, rule bugs) can be shipped as **opt-in migrations** that a session owner chooses to apply.

## 6. Pros, cons and risks

**Pros**
- Content is readable and editable by anyone, with normal git review.
- Clear split: game data is static and versioned, sessions are dynamic.
- Event log gives us replay, debugging, summaries and testing almost for free.
- Genre packs let one engine serve many genres without growing the core.

**Cons and risks, with mitigations**
- **Prose too loose for the rules.** Fixed by putting anything the engine needs in front matter and validating it against a schema on import.
- **Version drift.** Many sessions on many old versions, plus packs and modules moving at different speeds. Mitigate with pinned versions, declared dependencies and opt-in migrations.
- **Import cost.** Parsing and validating takes time. Do it once per publish, never per turn.
- **Image hosting.** Object storage, access control and cleanup of unused images need to be set up. Content-hash names make caching and deduplication simple.
- **Schema evolution.** Front matter fields and event types will change over time. We need schema versions and a way to read old events and old modules.

## 7. Extras

Export a finished session back to Markdown:
- as a **readable chronicle** of what happened, or
- as the **seed for a new module** (the world after the players changed it).

## 8. Open questions for the team

1. Where does the line go between core and genre pack? Who approves core changes?
2. One git repo for all content, or one repo per world / pack?
3. Which object storage do we use for images, and who can upload?
4. Do imported modules live in Postgres, in memory, or both?
5. What does an event look like? Which event types do we start with, and how do we version them?
6. How often do we take snapshots?
7. Who can apply an opt-in migration to a live session: the GM, the players, or an admin?
8. Can players publish and share their own modules and forks? If so, how do we moderate them?
9. Does the AI GM write events directly, or does it propose changes that the engine validates first?
10. How much of the existing pack importer can we reuse, and what needs rewriting?
