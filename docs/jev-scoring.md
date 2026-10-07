---
title: "Jev persona-affect scoring"
updated: 2026-10-07
status: in-review
---

# Jev persona-affect scoring

**Status:** building / in review, 2026-10-07 (Fredrik via Case). App branch `jev-persona-affect`.

Use [TypeSafe](https://docs.typesafe.ai) **Jev** (System One) for **numeric persona-feeling scores** in the playtest loop. It is not a drop-in for the current LLM rubric judge with quoted evidence.

See also [Design: playtest loop](design-playtest-loop.md) (step 6 / Cost controls).

## Decision (first cut)

- **What Jev scores:** how frustrated (1) → delighted (5) would **this** persona be, from (a) the **whole session** and (b) a **single interaction/turn**.
- **Store:** the scale value and **confidence** (and preferably per-level probabilities) as part of the score.
- **Persona-grounded:** the same event reads differently per persona. Example: Paul can be delighted that his effort was thwarted if it felt real and natural; other personas feel differently. Each Score question is grounded in that persona's preferences from [personas](personas.md), not a generic player.
- **Rubric / Score levels:** rewrite as **concrete situation-level wording** of that affect scale for each persona (TypeSafe requires descriptive levels, not bare 1–5). See the [score primitive](https://docs.typesafe.ai).
- **Quoted LLM rationale / evidence:** **deferred**. Confidence is the interesting second signal for now.
- **Current path:** When `TYPESAFE_API_KEY` is set, `Playtest.Scorer` calls `Playtest.JevScorer` (primary). When unset, it falls back to the LLM rubric judge. Jev rows use `source=jev`, `kind=session_affect|turn_affect`; LLM rows keep `source=llm`, `kind=rubric` with evidence.

## Proposed Score question shape

*(For Case/Fredrik to confirm before build.)*

- One Score question per scoring unit: `persona_session_affect` (whole run) and optionally `persona_turn_affect` per turn (or a batch of turn questions in one Jev call).
- Five descriptive levels, low→high, e.g. for Paul: L0 "Left cold — the session felt mechanical or broke immersion" … L4 "Delighted — the world answered his play as real and natural, even when he failed". Levels are persona-specific copy derived from [personas](personas.md).
- `state` = player-visible transcript only: opening scene + per-turn player action and GM narration. **No** gm_notes, gm_reasoning, or `player_aware=false` events (locked 2026-10-07).
- Response mapping: Jev 0-indexed fractional score → store as 1–5 scale (`score+1`) or store 0–4 and label clearly; store confidence; store probabilities JSON.

## Implementation notes (2026-10-07)

- Hex [`jev`](https://hex.pm/packages/jev) `~> 0.2`, model pinned to `jev-1.13.0`.
- `TYPESAFE_API_KEY` set on `tales-forge-playtest` (2026-10-07); not on production yet.
- Levels live in `TalesForge.Playtest.AffectLevels` (editable copy per persona).
- Scale stored as **1–5** (`jev_fractional + 1`); confidence and probabilities on the row.
- `playtest_scores` extended with `source`, `kind`, `turn_number`, `confidence`, `probabilities`.
- Req was bumped to `~> 0.7` (`override: true`) so Hex jev can resolve beside `jido_action`.

## Closed decisions

1. Score shape: session + per-turn in one Jev call — confirmed.
2. TypeSafe API key on playtest — set 2026-10-07.
3. Hex jev — yes.
4. GM notes excluded from state — confirmed.
5. Model `jev-1.13.0` — pinned.

## Links and cost

- [docs.typesafe.ai](https://docs.typesafe.ai)
- Score primitive (ordered descriptive levels, fractional score, confidence, probabilities)
- Hex [`jev`](https://hex.pm/packages/jev)
- Cost note: ~$0.042/1M input tokens — much cheaper than the current LLM scorer
