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
