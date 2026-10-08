---
title: Future ideas
updated: 2026-10-08
---

# Future ideas

Ideas we may pick up later. They are not decisions and nobody is building them yet. Each entry says where it came from, what it is, the constraints, and when to pick it up. When an idea is picked up, it gets a design note and an entry in the [decision log](decisions.md), and the entry here links to them.

## Speculative intent while typing

- **From:** Fredrik, 2026-10-08 (via Case).
- **Idea:** after a typing pause of about 300–400 ms, run the Jev intent and safety call on the draft in the input box. On send, reuse that result if the text is unchanged; otherwise run the call again on the sent text.
- **Bigger win:** also start the work that follows intent early: the roll, the NPC reactions, the prices and a warm-up of the GM prompt cache. That might take 1–2 s off a turn of about 7 s.
- **Constraints:**
  - The turn always uses the exact text the player sent, never a stale draft. Anything computed from a draft is thrown away unless the sent text matches it exactly.
  - Speculative calls are capped per turn, so a slow typist can't run up cost.
- **When:** after the Jev intent path is live (PR 2 of the intent plan).
- **Related:** [Design: player intent as one Jev call](design-jev-intent.md), [Design: persistent world state](design-stateful-world.md#8-cost-and-latency) (the turn's cost and latency).

## Memory consolidation and attitude drift

*Fredrik, 2026-10-08. A later layer on top of the [stateful world](design-stateful-world.md).*

- **Consolidation on the world clock.** On a world-clock tick (about hourly in game time), memories nobody has touched since the last tick merge into a gist and lose detail. The merge is plain Elixir or a Jev call, never an LLM.
- **Strong moments stay sharp.** Memories with strong emotion keep their detail longer.
- **Personality sets the pace.** OCEAN traits decide how fast things fade: high neuroticism holds on to slights, and high agreeableness forgives sooner.
- **Meeting again refreshes.** Seeing someone again refreshes the gist and starts a new detailed layer on top of it.
- **Attitudes drift toward neutral.** Feelings slowly drift back toward neutral over world time, and grudges fade more slowly than warmth.
- **NPCs and PCs alike.** The same rules apply to both, since they share the unified character type.

Fits the per-world process: consolidation and drift are pure functions run on world ticks, stored as data, so restarts and replays give the same result.
