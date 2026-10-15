---
title: "Plan: Jev baseline and A/B measurement"
updated: 2026-10-07
status: plan (nothing run yet)
---

# Plan: Jev baseline and A/B measurement

**Goal:** get a new Jev reference after the roll and Brenna rework, in the same shape as the [2026-10-07 analysis](analysis-jev-scores-2026-10-07.md), and compare it with the 44 Elara runs. Optionally, also measure the rework's own effect with an A/B on one deploy.

**Status:** ready, not run. The runs need the PRs below merged first, and only Fredrik approves those.

## What has to land first

| PR | What it gives the measurement |
|---|---|
| [#56](https://github.com/whyse-ab/ex-tales-forge/pull/56) | Roll rules, plus the behaviour variant (`default` = rework, `baseline` = old behaviour, opt-in per session) |
| [#58](https://github.com/whyse-ab/ex-tales-forge/pull/58) | Brenna, hooks and prose (stacked on #56; retarget it to `main` after #56 merges) |
| [#57](https://github.com/whyse-ab/ex-tales-forge/pull/57) | Hawk's and Ronny's Jev levels and questions. It must land **before** the runs, so every new run uses the same rubric |
| [#55](https://github.com/whyse-ab/ex-tales-forge/pull/55) | The git SHA and flags (variant, NPC_REACTIONS, WORLD_AGENTS, models, Jev rubric) stored on each run and shown on the run report |
| [#59](https://github.com/whyse-ab/ex-tales-forge/pull/59) | `Playtest.Series`: an unattended, interleaved and resumable batch runner |

Persona-chosen characters ([#60](https://github.com/whyse-ab/ex-tales-forge/pull/60): each persona plays a character it created instead of Elara; see [the picks](playtest-persona-characters.md)) come after the rework merges, at lower priority. If they land before the baseline, the baseline uses them (`character: :default` would still play Elara). Either way, the export records which character was played.

## Design

- **Runs:** 13 per persona, for Paul, Lotta, Lars, Hawk and Ronny, in Tin Valley, with `turn_limit: 10` (the 8–12 range recommended in the analysis; one fixed length keeps runs comparable). That is **65 runs**.
- **Why 13:** Paul's session-score SD was about 0.36. With 13 runs per group, a Mann-Whitney test has about 80% power to detect a difference of about 1 SD (≈0.4 points) per persona, and pooling the four non-Ronny personas detects about 0.5 SD.
- **Optional A/B arm:** also run `variant: "baseline"` (the old rolls, old Brenna and old prompts) in the same series. That is 65 more runs. Baseline and the rework then share one deploy, one model and the same hours, so the difference is the rework alone. Comparing against the Elara runs instead mixes in the rework, the character, the run length and Hawk's and Ronny's rubric change.
- **Interleaving:** each round of the series plays every persona once in every variant, and the variant order flips each round.
- **Tagging:** each run's notes carry `series=NAME variant=V`; #55 adds the git SHA and flags. A series that was stopped resumes without repeating runs.
- **Ronny** is an anti-persona (high = the game resisted him). He is scored for exploit coverage and kept out of the delight averages.

```elixir
# On tales-forge-playtest, after the merges (one series per measurement):
TalesForge.Playtest.Series.start("jev-baseline-1",
  personas: ~w(paul lotta lars hawk ronny), variants: ~w(default), runs: 13, turn_limit: 10)
# With the A/B arm: variants: ~w(baseline default)
TalesForge.Playtest.Series.progress("jev-baseline-1")
```

## Cost and time

These figures are estimated from the playtest AI calls on 2026-10-07 (20 runs, 103 turns, current models):
- GM: about $0.0065–0.0086 per turn (turn 1 about $0.012);
- scene: about $0.0085 per run;
- persona bot: about $0.0016 per turn;
- Jev: about $0.0003 per scoring pass and $0.00004 per NPC-reaction call.

The rework prompts add a few hundred mostly cached tokens per GM call, which is under a few percent.

| Per 10-turn run | USD |
|---|---|
| Game (scene + GM + intent) | 0.075–0.11 (≈0.09) |
| Persona bot | 0.016–0.02 |
| Jev (scoring + NPC reactions) | ≈0.001 |
| **Total** | **≈0.11** |

| Batch | Game | Persona | Jev | Total |
|---|---|---|---|---|
| Baseline, 65 runs × 10 turns | $4.9–7.2 | $1.0–1.3 | ≈$0.07 | **$6–8.5** |
| Same at 12 turns | $5.8–8.6 | $1.2–1.6 | ≈$0.08 | $7–10 |
| Baseline + A/B arm, 130 runs × 10 turns | $9.8–14.3 | $2.1–2.6 | ≈$0.13 | **$12–17** |

- **$1 session cap** (game only): about $0.09 per run, so it never binds. The **$0.50 persona-per-run cap** is not reached either (about $0.02).
- **$10 day cap** (all calls on playtest, Europe/Stockholm day):
  - The baseline alone fits in a day, but tightly at the high end, and it competes with any other playtesting that day.
  - **Recommendation:** spread it over **2 days** (about 33 runs a day, about $3.5–4.5 a day).
  - The series pauses at the first spend-cap stop and continues when started again with the same name, so no cap raise is needed.
  - The baseline plus the A/B arm needs 2–3 days, or a temporary day cap of **$20** for one day.
- **Time:** about 7 s per turn, so a 10-turn run takes about 1.5–2 minutes with scene and scoring. The 65 runs take about 2–2.5 hours; 130 runs about 4.5–5 hours.

## Analysis

The scripts are [`scripts/jev-compare/`](scripts/jev-compare/):
- `export.exs`: a read-only export of all runs (scores, turns, AI calls, character, variant, SHA and flags);
- `compare.py`: redoes the analysis per cohort and compares each cohort with the Elara runs.

1. Copy `export.exs` to the playtest machine (`flyctl ssh sftp shell -a tales-forge-playtest`, then put it at `/tmp/export.exs`). Run `/app/bin/ex_tales_forge rpc 'Code.eval_file("/tmp/export.exs")'`, then fetch `/tmp/jev_export.json`.
2. Run `python3 compare.py jev_export.json --out report.md --csv out/`. It needs pandas, scipy and tabulate. Add older export files if runs have since been deleted; runs are de-duplicated by id.
3. Write `analysis-jev-baseline-<date>.md` in the same shape as the 2026-10-07 analysis, using the report as the source. Read the lowest turns before quoting causes, because the script's cause markers are automatic.

The report contains:
- **0.** Cohorts with their git SHAs, rubric hashes and characters (a rubric that differs between cohorts is flagged).
- **1.** Per persona: session and turn scores, confidence, and turns with confidence < 0.3.
- **2.** By turn index: raw scores, within-run demeaned scores and confidence; turn 1 vs the rest.
- **3.** Correlations: length, echo, repetition, checks and failures, brush-off and stock phrases, third person, hooks and latency.
- **4.** The lowest 10 turns per cohort with a cause tally, and the low-confidence turns.
- **5.** Versus the Elara runs:
  - per persona and pooled: difference, bootstrap 95% CI, Cliff's delta and Mann-Whitney p, for whole sessions and for turns 1–5 (the like-for-like window, since the Elara runs were about 5 turns long);
  - game behaviour per cohort: check rate, Insight share, fail rate, brush-off rate, stock phrases, third person, echo, repetition, a hook by turn 2, and the share of runs with "eyes narrow";
  - cost per run, with game, persona and Jev kept apart.

The script was checked against the 2026-10-07 export (with a fake split for the new cohorts). It reproduces that analysis's numbers: Insight on about 70% of turns, "eyes narrow" in about 90% of the runs, and turn confidence falling over the turns.

## Caveats

- **Hawk and Ronny:** their levels changed in #57, so their Elara scores used the old rubric. Compare them within the new runs (or within the A/B), not against Elara, or re-score the Elara transcripts with the new rubric first. That costs about $0.0001 per call.
- **Hawk needs danger:** Tin Valley's danger (the nest, the cut) may not arrive within 10 turns. If Hawk's runs stay in the inn, consider a separate Hawk series at 12 turns.
- **Fewer rolls means fewer improvement marks:** the rework rolls less often, so characters improve more slowly. This is not measured here, but it is worth watching.
