---
title: "Jev persona-affect scoring"
updated: 2026-10-08
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
- Levels live in `TalesForge.Playtest.AffectLevels` (editable copy per persona). Editing a persona's levels changes its rubric hash and so its `rubric_version`; see the stricter top below.
- Scale stored as **1–5** (`jev_fractional + 1`); confidence and probabilities on the row.
- `playtest_scores` extended with `source`, `kind`, `turn_number`, `confidence`, `probabilities`.
- Req was bumped to `~> 0.7` (`override: true`) so Hex jev can resolve beside `jido_action`.

## Stricter top for Paul and Lotta (2026-10-07)

Decision: [A stricter Jev rubric before the next A/B](decisions.md#2026-10-07-a-stricter-jev-rubric-before-the-next-ab-the-personas-stay-as-they-are). PR: [ex-tales-forge #69](https://github.com/whyse-ab/ex-tales-forge/pull/69), merged 2026-10-08 as `cb6a5f6` (prod v64, playtest v53).

In the 65-run baseline, Paul's most likely turn level was 5 on 124 of 130 turns and Lotta's was 4 on 130 of 130. That ceiling hid any change. The levels in `AffectLevels` now read as follows (the questions and personas are unchanged):

- **Level 3:** also covers *smooth and polite but generic* play (Lotta: *pleasant but interchangeable*).
- **Level 4:** the world answered something specific to *their* character, not just a polite guest.
- **Level 5:** all of level 4 plus **concrete evidence of at least two of**: a surprise; a choice of theirs with a consequence; an NPC or the world calling back to earlier play; an NPC acting on their own goals; for Lotta also care when stakes hurt. "A pleasant but uneventful stretch is never this level."

**Rubric versions.** The hash covers the levels, so only Paul's and Lotta's versions change:

| persona | before | after |
|---|---|---|
| paul | `jev-affect-v1-dfec71a` | `jev-affect-v1-fd84ebb` |
| lotta | `jev-affect-v1-4545d3b` | `jev-affect-v1-ce84a1a` |
| lars / hawk / ronny | `fc771be` / `129f728` / `e8f0786` | unchanged |

**Comparisons.** Never compare scores across rubric versions. For an A/B against the 2026-10-07 baseline, first re-score the baseline's Paul and Lotta runs with the new rubric. The stored transcripts and the same Jev model are enough, and no game calls are needed. Use [`scripts/jev-rescore/rescore.exs`](scripts/jev-rescore/rescore.exs).

**Pilot** (all 26 baseline Paul and Lotta runs, scored with both rubrics, jev-1.13.0; raw rows in [`scripts/jev-rescore/rescore-2026-10-07.json`](scripts/jev-rescore/rescore-2026-10-07.json)):

| | session mean (sd) | turn mean (sd) | turn argmax counts (130 turns) |
|---|---|---|---|
| Paul old | 4.67 (0.58) | 4.70 (0.40) | 3: 5, 4: 1, 5: 124 |
| Paul new | 4.73 (0.36) | 4.36 (0.29) | 2: 1, 4: 75, 5: 54 |
| Lotta old | 4.41 (0.07) | 4.17 (0.10) | 4: 130 |
| Lotta new | 4.29 (0.29) | 3.91 (0.31) | 3: 24, 4: 94, 5: 12 |

- **Turn scores** now spread, and Lotta's run-to-run spread grew.
- **Paul's session score did not drop.** Over 10 turns, Jev still finds two kinds of evidence somewhere, so for Paul the turn means are the more sensitive A/B signal. If the session score must move too, a follow-up could scope level 5 to "most of the session".

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
