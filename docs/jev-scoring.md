---
title: "Jev persona-affect scoring"
updated: 2026-10-07
status: decided-first-cut
---

# Jev persona-affect scoring

**Status:** first-cut decision, 2026-10-07 (Fredrik via Case). Not built yet.

Use [TypeSafe](https://docs.typesafe.ai) **Jev** (System One) for **numeric persona-feeling scores** in the playtest loop. It is not a drop-in for the current LLM rubric judge with quoted evidence.

See also [Design: playtest loop](design-playtest-loop.md) (step 6 / Cost controls).

## Decision (first cut)

- **What Jev scores:** how frustrated (1) → delighted (5) would **this** persona be, from (a) the **whole session** and (b) a **single interaction/turn**.
- **Store:** the scale value and **confidence** (and preferably per-level probabilities) as part of the score.
- **Persona-grounded:** the same event reads differently per persona. Example: Paul can be delighted that his effort was thwarted if it felt real and natural; other personas feel differently. Each Score question is grounded in that persona's preferences from [personas](personas.md), not a generic player.
- **Rubric / Score levels:** rewrite as **concrete situation-level wording** of that affect scale for each persona (TypeSafe requires descriptive levels, not bare 1–5). See the [score primitive](https://docs.typesafe.ai).
- **Quoted LLM rationale / evidence:** **deferred**. Confidence is the interesting second signal for now.
- **Current path:** LLM `Playtest.Scorer` + `playtest_scores` evidence fields stay until this ships. Plan: add Jev affect scores (session + per-turn) and **replace the numeric judge path**; evidence fields optional/null until a later hybrid.

## Proposed Score question shape

*(For Case/Fredrik to confirm before build.)*

- One Score question per scoring unit: `persona_session_affect` (whole run) and optionally `persona_turn_affect` per turn (or a batch of turn questions in one Jev call).
- Five descriptive levels, low→high, e.g. for Paul: L0 "Left cold — the session felt mechanical or broke immersion" … L4 "Delighted — the world answered his play as real and natural, even when he failed". Levels are persona-specific copy derived from [personas](personas.md).
- `state` = session transcript (player-visible + optional GM notes — open: whether GM notes go to TypeSafe).
- Response mapping: Jev 0-indexed fractional score → store as 1–5 scale (`score+1`) or store 0–4 and label clearly; store confidence; store probabilities JSON.

## Open before build

1. Confirm Score question shape above (session + turn).
2. TypeSafe API key for Whyse (ask Fredrik when ready).
3. Hex [`jev`](https://hex.pm/packages/jev) vs raw HTTP (Bobby prefers Hex if solid; Dockerfile already Elixir 1.18 / OTP 27).
4. Whether GM notes are included in `state` sent to TypeSafe.
5. Pin model `jev-1.13.0`.

## Links and cost

- [docs.typesafe.ai](https://docs.typesafe.ai)
- Score primitive (ordered descriptive levels, fractional score, confidence, probabilities)
- Hex [`jev`](https://hex.pm/packages/jev)
- Cost note: ~$0.042/1M input tokens — much cheaper than the current LLM scorer
