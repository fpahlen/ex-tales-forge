---
title: "Character creation: persona preferences (hybrid ideas)"
updated: 2026-10-07
status: research
related: character-creation-port.md (PR #15), personas.md
---

# Character creation: persona preferences (hybrid ideas)

**Status:** research note, 2026-10-07. No game code changed. Complements the port plan in [character-creation-port.md](character-creation-port.md) (merged in tales-forge-docs PR #15).

## Why

The old app's rationale was "get me a capable character fast" so play can start, plus fascination with AI backstory. That suits some personas, not all. Before locking a UX for the Elixir port, we ran two hybrid ideas past Hawk, Paul, Lotta, Lars and Ronny.

**Idea 1.** Player picks race and class, then chooses a path: fast AI-assisted, or detailed (move stats up/down and skills).

**Idea 2.** For every section (stats, background, social class, origin), the player chooses either their own input or AI assist.

## Method

- One short interview call per persona on `tales-forge-playtest` (machine `801e9ef6136178`), via app Config / xAI key.
- Purpose recorded as `persona` (bot bucket; off session/game caps).
- Model: `xai/grok-4.20-0309-non-reasoning`, temperature 0.7, max_tokens 400.
- System: persona notes from `docs/personas.md` / `priv/playtest/personas.md`; answer in first person as that persona.
- User: the two hybrid ideas plus three questions (preferred style; insist on choosing vs AI; what puts them off).
- Raw answers: `/workspace/bobby/verify/charcreate-persona-answers.md` (worker machine; not in this repo).

**Total AI cost:** about **$0.0053** (5,255 micro-USD across five successful calls; no retries needed).

## Per persona (short)

**Hawk (hard mode)** — Prefers **Idea 2**. Wants granular control: insists on stats, class features, core personality/flaws, and origin beats that matter; happy for AI on minor skills, gear packages, flavour. Put off by uneditable AI output, cute/cheese tone that breaks hard-but-fair, and anything that hides mechanical consequences.

**Paul (role playing)** — Prefers **Idea 1**. Race/class/path first feels like choosing a dramatic entrance; Idea 2 feels piecemeal and breaks character mid-build. Insists on race, class, and core concept/voice; AI may fill exact numbers and filler skills. Put off by spreadsheets/sliders, "chosen one" tropes overwriting his concept, and visible dice once play starts.

**Lotta (identification)** — Prefers **Idea 2**. Needs section-by-section control for the Ugly Duckling arc. Insists on background, origin, and social class; will tweak AI stats/skills; wants to co-write backstory. Put off by loss of identity control, generic tragic-orphan cheese, and too many correction clicks.

**Lars (adventurer)** — Prefers **Idea 2**. Control where impact matters (stats, combat features, world-tied hooks); AI for name, appearance, flavour. Put off by losing control over gameplay/impact, cheese tropes, and too many screens before the adventure.

**Ronny (anti-persona)** — Prefers **Idea 2** to cherry-pick power. Insists on race, class, and min-maxed stats; AI for flavour he ignores. Put off by anything that blocks bending numbers or slows the path to top-tier loot. (Useful as a red-team signal: do not optimise the creation UX for him.)

## Takeaway for Fredrik

1. **Four of five lean Idea 2** (per-section own-input vs AI). Only **Paul** prefers Idea 1's single path choice, for immersion.
2. A **fast default still matters** (Lars, and the old "get playing" goal), but it should not be the only mode: Lotta and Hawk need editable ownership of identity and mechanics.
3. **Common insist-self:** race/class/concept (Paul), stats/features when they affect fairness or impact (Hawk, Lars), background/origin/social for identity (Lotta).
4. **Common put-offs:** uneditable AI, orphan/chosen-one cheese, friction/correction loops, and (for Paul) visible mechanics.
5. Practical UX sketch: **defaults to fast AI assist**, with **per-section "I'll choose / AI assist"** (Idea 2), plus an optional **"detailed path"** shortcut for Paul-style players who want one decision then play — and always allow edit after AI fill.
6. Keep **Ronny** as anti-persona: resist min-max exploits in generation; do not design the happy path around him.
7. Feed this into the port plan's creation screen and playtest "character creation" scenario once PR #15 lands or in parallel.
