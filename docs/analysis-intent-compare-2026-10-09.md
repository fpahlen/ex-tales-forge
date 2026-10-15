# Intent comparison: INTENT_JEV on vs off (playtest, 2026-10-09)

Persona batch on tales-forge-playtest, 5 personas × 4 sessions per arm (20 + 20 scored runs, 12-turn limit). Total spend $4.14. Raw output: `/workspace/intent-compare/analysis.txt` on the box.

## Results per arm

| Metric | off (LLM intent) | on (Jev intent) |
|---|---|---|
| Jev session score, all | 3.96 ± 0.81 | 3.98 ± 0.87 |
| Jev session score, excl. Ronny | 3.84 ± 0.82 | 3.99 ± 0.82 |
| Turn score mean / weighted | 3.55 / 3.60 | 3.54 / 3.57 |
| Clarifying questions per turn | 0.038 (8/208) | 0.000 (0/207) |
| Intent latency median / p95 / max | 1 / 1641 / 5762 ms (93.5% within 1.5 s) | 249 / 308 / 531 ms (100% within 1.5 s) |
| GM LLM latency median / p95 | 6168 / 10511 ms | 5776 / 9393 ms |
| Intent to persist median / p95 / max | 6.7 / 11.6 / 48.1 s | 6.4 / 10.1 / 16.1 s |
| Game cost (incl. intent) | $1.567 (LLM intent $0.040) | $1.557 (Jev intent $0.027) |
| Game cost per run / per turn | $0.078 / $0.0075 | $0.078 / $0.0075 |
| Persona bot cost | $0.513 | $0.489 |
| Scorer cost | $0.0052 | $0.0051 |

Session Δ (on − off), stratified bootstrap: all +0.02 (CI −0.38..0.41); excl. Ronny +0.15 (CI −0.26..0.53). Per persona: Paul +0.19, Lotta −0.53 (CI −1.09..0.03; turn-level −0.21, CI −0.40..−0.04), Lars +0.05, Ronny −0.49 (very noisy, sd 1.18), Hawk +0.89 (CI −0.56..2.11). No difference is significant at session level; Lotta's turn-level dip is the only CI excluding zero.

Jev on arm: 207/207 calls ok, all `jev` source, bands act 200 / best_guess 7, no fallbacks, all benign, quote used every time.

## Watch items

1. **Generous calibration lifts.** 61 of 207 reads lifted ≥0.3 (max 0.41); 52 raw <0.6 and 14 raw <0.45, yet only 7 ended calibrated <0.7. Example: Lotta turn 7, raw 0.41 → 0.815 `act` on speak/guild_steward for "I nod once, already turning toward the western edge of the square. 'I'll bring back that tooth.'" — the player was really leaving (move). Calibration is likely why the on arm asked zero clarifying questions.
2. **Jev-only deferred moves.** 31 of 207 reads carried a deferred action (move 25, speak 3, wait/spend/buy 1 each). Example: Lotta turn 3, "Point me to this Osric after I've eaten, then" read as use_item now with move→market_square later (raw 0.50, cal 0.87). The GM doesn't act on the deferred part yet.

## Failed and excluded runs

- Paul/on `1d85967b`: stopped by timeout at turn 5 (the turn-5 stall), re-run.
- Paul/on `f4b1bb3f`: failed with 0 turns (xAI 429 rate limiting), re-run.
- Hawk/on `fbc300cf`: failed at turn 6 (xAI 429), re-run.
- One on-arm scored run ended `dead` instead of turn limit.

## Recommendation

`on` does **not** clearly win on quality: scores are a tie (+0.02 overall, +0.15 without Ronny, all CIs straddle zero), with a possible Lotta regression. It does win clearly on latency (intent p95 1.6 s → 0.3 s, worst intent-to-persist 48 s → 16 s) and is cost-neutral. Recommend keeping playtest on `shadow`, not flipping prod yet, and **not** retiring the baseline until a holdout confirms.

Next steps:
1. Tighten calibration (cap lift or raise the ask threshold) so low-raw reads can still trigger a clarifying question; recheck the Lotta case.
2. Decide whether GM should use deferred moves.
3. Freeze tuning, then run a holdout batch (fresh seeds, same 5 personas, ≥4 per arm) before switching to `on` and retiring baseline.

Playtest INTENT_JEV was `shadow` at the end of the run (runner check 10:25). Nothing merged, deployed or reconfigured.
