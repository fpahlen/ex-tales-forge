# Jev intent shadow mode: first day (2026-10-09)

Playtest (`tales-forge-playtest`, v72 after #84), `INTENT_JEV=shadow` since 2026-10-08 ~16:09 CEST. Data: `turn.intent_shadow` and Jev `intent_shadow` ai_calls since 2026-10-08T14:00Z, read-only.

## Volume
- 125 shadow reads over 13 sessions (4–12 turns each). None from verification run 2b1db488; the sessions look like the overnight persona runs. Today's path was heuristic on 119 turns, LLM on 6.

## Agreement with today's path
- Action 57/125 (46%), class 83/125 (66%), target 44/125 (35%), skill 73/125 (58%), later 101/125 (81%).
- Material difference: 41/125 (33%). Examples:
  - "Good folk, the Light teaches that even the fiercest storm may be calmed with patient words..." : today `combat`, Jev `speak` to innkeep (Jev right).
  - "I dig out seven coppers and slide them across the counter... Where exactly is this nest?" : today `pickup`, Jev `speak` to innkeep (Jev right).
  - "I drain the last of my ale, stand... Then I'll head up now" : today `other`, Jev `move` to mine_workings (Jev right).
- Much of the low action/target agreement is the heuristic path being wrong rather than Jev.

## Asking, bands, safety, quote
- Jev would ask 0/125; today's path asked 3/125.
- Bands: act 122, best_guess 3.
- Safety: benign 120, prompt_injection 5; would-decline 0.
- Quote used on 120, summary on 5.

## Latency and cost
- All 125 within the 1500 ms live timeout. p50 255 ms, p95 340 ms, max 729 ms.
- Jev cost $0.016 total (~$0.00013/turn).

## Watch items
- Calibration lift: 36 turns had raw confidence below 0.6; 40 turns were lifted by 0.3 or more (max +0.41, e.g. raw 0.42 to 0.83). Combined with zero would-asks, calibration looks too generous and should be checked against the eval set.
- Deferred moves: Jev added deferred actions on 22 turns where today's path had none (today's path had deferred on 2). Needs a spot check for moves the player didn't actually say.

## Recommendation
Enough data and latency/cost are fine, so the persona comparison (5 personas x 4 runs per arm, ~$5) is worth running once Fredrik OKs it. Spot-check the calibration lift and the 22 Jev-only deferred moves alongside it.
