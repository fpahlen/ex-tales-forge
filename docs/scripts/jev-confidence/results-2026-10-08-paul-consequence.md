## Baseline 2026-10-07 (65 runs; stored first-pass scores, as in that analysis)

#### Turns: baseline, stored scores (Paul and Lotta on the pre-#69 rubric)

| Persona | Turns | Plain mean | Headline ≥0.6 | **Headline ≥0.7** | Headline ≥0.8 | Low-conf share (<0.7) | Confident-high | Confident-low | Confident-middle | Unsure | High / low, any conf |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Paul | 130 (13 runs) | 4.70 | 4.80 (n=118) | 4.82 (n=108) | 4.85 (n=86) | 17% (22) | 108 (83%) | 0 (0%) | 0 (0%) | 22 (17%) | 96% / 1% |
| Lotta | 130 (13 runs) | 4.16 | 4.16 (n=129) | 4.15 (n=120) | 4.11 (n=70) | 8% (10) | 120 (92%) | 0 (0%) | 0 (0%) | 10 (8%) | 100% / 0% |
| Lars | 130 (13 runs) | 3.66 | 3.80 (n=85) | 3.92 (n=59) | 3.97 (n=33) | 55% (71) | 56 (43%) | 1 (1%) | 2 (2%) | 71 (55%) | 72% / 4% |
| Ronny | 130 (13 runs) | 4.44 | 4.75 (n=72) | 4.80 (n=54) | 4.85 (n=35) | 58% (76) | 54 (42%) | 0 (0%) | 0 (0%) | 76 (58%) | 95% / 1% |
| Hawk | 156 (13 runs) | 1.93 | 1.85 (n=136) | 1.85 (n=78) | 1.91 (n=37) | 50% (78) | 2 (1%) | 73 (47%) | 3 (2%) | 78 (50%) | 6% / 87% |

Headline = mean of turns with confidence ≥ cutoff (n = turns kept). Matrix columns at cutoff 0.7; shares are of all turns. ⚠ = fewer than 20 confident turns or 3 runs.

Low-confidence share at each cutoff (share of turns below it):

| Persona | < 0.6 | **< 0.7** | < 0.8 | Confidence exactly 0 |
|---|---|---|---|---|
| Paul | 9% | 17% | 34% | 1 |
| Lotta | 1% | 8% | 46% | 0 |
| Lars | 35% | 55% | 75% | 0 |
| Ronny | 45% | 58% | 73% | 6 |
| Hawk | 13% | 50% | 76% | 0 |

#### Sessions: baseline, stored scores (Paul and Lotta on the pre-#69 rubric)

| Persona | Sessions | Plain mean | Headline ≥0.6 | **Headline ≥0.7** | Headline ≥0.8 | Unsure (<0.7) | Confident-high | Confident-low | Confident-middle |
|---|---|---|---|---|---|---|---|---|---|
| Paul | 13 | 4.67 | 4.89 (n=11) | 4.89 (n=11) | 4.91 (n=10) | 15% (2) | 11 | 0 | 0 |
| Lotta | 13 | 4.40 | 4.40 (n=11) | 4.28 (n=2) ⚠ | — (n=0) ⚠ | 85% (11) | 2 | 0 | 0 |
| Lars | 13 | 4.04 | 4.00 (n=12) | 3.95 (n=7) | 4.10 (n=3) | 46% (6) | 6 | 0 | 1 |
| Ronny | 13 | 4.37 | 4.69 (n=5) | 4.71 (n=4) | — (n=0) ⚠ | 69% (9) | 4 | 0 | 0 |
| Hawk | 13 | 3.02 | 3.02 (n=13) | 3.05 (n=12) | 3.04 (n=9) | 8% (1) | 4 | 6 | 2 |

⚠ = fewer than 3 confident sessions.

Paul and Lotta baseline (stricter rubric): scores and confidences from `rescore-baseline-2026-10-08-conf.json` (26 runs, re-scored 2026-10-08 with turn confidences kept).

## Post-rework comparison (Paul and Lotta on the stricter #69 rubric on both sides)

#### Turns: baseline as compared (Paul and Lotta re-scored with the stricter rubric; second pass, turn confidences kept)

| Persona | Turns | Plain mean | Headline ≥0.6 | **Headline ≥0.7** | Headline ≥0.8 | Low-conf share (<0.7) | Confident-high | Confident-low | Confident-middle | Unsure | High / low, any conf |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Paul | 130 (13 runs) | 4.37 | 4.40 (n=101) | 4.37 (n=64) | 4.34 (n=39) | 51% (66) | 64 (49%) | 0 (0%) | 0 (0%) | 66 (51%) | 99% / 0% |
| Lotta | 130 (13 runs) | 3.91 | 3.91 (n=86) | 3.92 (n=33) | 4.21 (n=7) ⚠ | 75% (97) | 28 (22%) | 0 (0%) | 5 (4%) | 97 (75%) | 90% / 0% |
| Lars | 130 (13 runs) | 3.66 | 3.80 (n=85) | 3.92 (n=59) | 3.97 (n=33) | 55% (71) | 56 (43%) | 1 (1%) | 2 (2%) | 71 (55%) | 72% / 4% |
| Ronny | 130 (13 runs) | 4.44 | 4.75 (n=72) | 4.80 (n=54) | 4.85 (n=35) | 58% (76) | 54 (42%) | 0 (0%) | 0 (0%) | 76 (58%) | 95% / 1% |
| Hawk | 156 (13 runs) | 1.93 | 1.85 (n=136) | 1.85 (n=78) | 1.91 (n=37) | 50% (78) | 2 (1%) | 73 (47%) | 3 (2%) | 78 (50%) | 6% / 87% |

Headline = mean of turns with confidence ≥ cutoff (n = turns kept). Matrix columns at cutoff 0.7; shares are of all turns. ⚠ = fewer than 20 confident turns or 3 runs.

Low-confidence share at each cutoff (share of turns below it):

| Persona | < 0.6 | **< 0.7** | < 0.8 | Confidence exactly 0 |
|---|---|---|---|---|
| Paul | 22% | 51% | 70% | 1 |
| Lotta | 34% | 75% | 95% | 0 |
| Lars | 35% | 55% | 75% | 0 |
| Ronny | 45% | 58% | 73% | 6 |
| Hawk | 13% | 50% | 76% | 0 |

#### Sessions: baseline as compared (Paul and Lotta re-scored with the stricter rubric; second pass, turn confidences kept)

| Persona | Sessions | Plain mean | Headline ≥0.6 | **Headline ≥0.7** | Headline ≥0.8 | Unsure (<0.7) | Confident-high | Confident-low | Confident-middle |
|---|---|---|---|---|---|---|---|---|---|
| Paul | 13 | 4.74 | 4.84 (n=12) | 4.84 (n=12) | 4.85 (n=11) | 8% (1) | 12 | 0 | 0 |
| Lotta | 13 | 4.30 | 4.32 (n=6) | 4.76 (n=2) ⚠ | 4.89 (n=1) ⚠ | 85% (11) | 2 | 0 | 0 |
| Lars | 13 | 4.04 | 4.00 (n=12) | 3.95 (n=7) | 4.10 (n=3) | 46% (6) | 6 | 0 | 1 |
| Ronny | 13 | 4.37 | 4.69 (n=5) | 4.71 (n=4) | — (n=0) ⚠ | 69% (9) | 4 | 0 | 0 |
| Hawk | 13 | 3.02 | 3.02 (n=13) | 3.05 (n=12) | 3.04 (n=9) | 8% (1) | 4 | 6 | 2 |

⚠ = fewer than 3 confident sessions.

#### Turns: post-rework 2026-10-08 (23 completed runs)

| Persona | Turns | Plain mean | Headline ≥0.6 | **Headline ≥0.7** | Headline ≥0.8 | Low-conf share (<0.7) | Confident-high | Confident-low | Confident-middle | Unsure | High / low, any conf |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Paul | 50 (5 runs) | 4.24 | 4.29 (n=35) | 4.29 (n=27) | 4.23 (n=18) ⚠ | 46% (23) | 27 (54%) | 0 (0%) | 0 (0%) | 23 (46%) | 100% / 0% |
| Lotta | 50 (5 runs) | 3.84 | 3.86 (n=30) | 4.23 (n=7) ⚠ | 4.52 (n=5) ⚠ | 86% (43) | 6 (12%) | 0 (0%) | 1 (2%) | 43 (86%) | 78% / 0% |
| Lars | 40 (4 runs) | 3.70 | 3.85 (n=28) | 3.89 (n=24) | 3.90 (n=17) ⚠ | 40% (16) | 23 (57%) | 1 (2%) | 0 (0%) | 16 (40%) | 80% / 5% |
| Ronny | 40 (4 runs) | 4.33 | 4.71 (n=19) ⚠ | 4.78 (n=12) ⚠ | 4.86 (n=7) ⚠ | 70% (28) | 12 (30%) | 0 (0%) | 0 (0%) | 28 (70%) | 90% / 0% |
| Hawk | 60 (5 runs) | 2.10 | 2.13 (n=57) | 2.17 (n=44) | 2.22 (n=29) | 27% (16) | 1 (2%) | 34 (57%) | 9 (15%) | 16 (27%) | 2% / 78% |

Headline = mean of turns with confidence ≥ cutoff (n = turns kept). Matrix columns at cutoff 0.7; shares are of all turns. ⚠ = fewer than 20 confident turns or 3 runs.

Low-confidence share at each cutoff (share of turns below it):

| Persona | < 0.6 | **< 0.7** | < 0.8 | Confidence exactly 0 |
|---|---|---|---|---|
| Paul | 30% | 46% | 64% | 1 |
| Lotta | 40% | 86% | 90% | 0 |
| Lars | 30% | 40% | 57% | 0 |
| Ronny | 52% | 70% | 82% | 4 |
| Hawk | 5% | 27% | 52% | 0 |

#### Sessions: post-rework 2026-10-08 (23 completed runs)

| Persona | Sessions | Plain mean | Headline ≥0.6 | **Headline ≥0.7** | Headline ≥0.8 | Unsure (<0.7) | Confident-high | Confident-low | Confident-middle |
|---|---|---|---|---|---|---|---|---|---|
| Paul | 5 | 4.77 | 4.77 (n=5) | 4.77 (n=5) | 4.84 (n=3) | 0% (0) | 5 | 0 | 0 |
| Lotta | 5 | 4.21 | 4.51 (n=3) | 4.85 (n=1) ⚠ | 4.85 (n=1) ⚠ | 80% (4) | 1 | 0 | 0 |
| Lars | 4 | 4.05 | 4.05 (n=4) | 4.03 (n=3) | 4.18 (n=1) ⚠ | 25% (1) | 3 | 0 | 0 |
| Ronny | 4 | 4.09 | 4.72 (n=1) ⚠ | 4.72 (n=1) ⚠ | — (n=0) ⚠ | 75% (3) | 1 | 0 | 0 |
| Hawk | 5 | 3.34 | 3.34 (n=5) | 3.34 (n=5) | 3.12 (n=2) ⚠ | 0% (0) | 1 | 0 | 4 |

⚠ = fewer than 3 confident sessions.

## Deltas, post-rework minus baseline

### Session score

| Persona | Old: plain mean Δ (95% CI) | Confident only ≥0.6 | **Confident only ≥0.7** | Confident only ≥0.8 |
|---|---|---|---|---|
| Paul | +0.04 (-0.15…+0.31); 2nd pass +0.03 (-0.14…+0.28) | -0.07 (-0.16…+0.03) n=5/12 | -0.07 (-0.16…+0.03) n=5/12 | -0.02 (-0.11…+0.09) n=3/11 |
| Lotta | -0.10 (-0.50…+0.34); 2nd pass -0.09 (-0.50…+0.32) | +0.19 (-0.30…+0.64) n=3/6 | +0.08 (-0.04…+0.21) n=1/2 ⚠ | -0.04 (—) n=1/1 ⚠ |
| Lars | +0.01 (-0.27…+0.28) | +0.05 (-0.25…+0.32) n=4/12 | +0.08 (-0.30…+0.48) n=3/7 | +0.08 (+0.03…+0.18) n=1/3 ⚠ |
| Ronny | -0.28 (-0.77…+0.20) | +0.03 (-0.01…+0.06) n=1/5 ⚠ | +0.01 (-0.02…+0.05) n=1/4 ⚠ | — (—) n=0/0 ⚠ |
| Hawk | +0.32 (-0.38…+1.04) | +0.32 (-0.39…+1.03) n=5/13 | +0.29 (-0.49…+1.06) n=5/12 | +0.08 (-0.83…+0.90) n=2/9 ⚠ |

n = confident sessions new/base. ⚠ = fewer than 3 on a side.

### Turn score

| Persona | Old: turn mean Δ, one mean per run (95% CI) | Confident only ≥0.6 | **Confident only ≥0.7** | Confident only ≥0.8 |
|---|---|---|---|---|
| Paul | -0.12 (-0.21…-0.03); 2nd pass -0.13 (-0.21…-0.03) | -0.11 (-0.19…-0.03) n=35/101 | -0.08 (-0.17…+0.01) n=27/64 | -0.11 (-0.27…+0.07) n=18/39 ⚠ |
| Lotta | -0.07 (-0.28…+0.14); 2nd pass -0.07 (-0.28…+0.13) | -0.05 (-0.27…+0.14) n=30/86 | +0.31 (-0.51…+0.69) n=7/33 ⚠ | +0.32 (-0.27…+0.58) n=5/7 ⚠ |
| Lars | +0.04 (-0.22…+0.25) | +0.06 (-0.22…+0.26) n=28/85 | -0.03 (-0.27…+0.16) n=24/59 | -0.07 (-0.36…+0.13) n=17/33 ⚠ |
| Ronny | -0.11 (-0.55…+0.28) | -0.04 (-0.16…+0.02) n=19/72 ⚠ | -0.02 (-0.14…+0.03) n=12/54 ⚠ | +0.01 (-0.05…+0.03) n=7/35 ⚠ |
| Hawk | +0.17 (-0.06…+0.38) | +0.28 (+0.10…+0.45) n=57/136 | +0.32 (+0.15…+0.47) n=44/78 | +0.32 (+0.07…+0.51) n=29/37 |

n = confident turns new/base. ⚠ = fewer than 20 confident turns or 3 runs with one on a side.

### Low-confidence share of turns (new vs base, Δ in percentage points)

| Persona | < 0.6 | **< 0.7** | < 0.8 |
|---|---|---|---|
| Paul | 30% vs 22%: +8 pp (-5…+19 pp) | 46% vs 51%: -5 pp (-13…+4 pp) | 64% vs 70%: -6 pp (-17…+6 pp) |
| Lotta | 40% vs 34%: +6 pp (-13…+24 pp) | 86% vs 75%: +11 pp (-10…+31 pp) | 90% vs 95%: -5 pp (-25…+9 pp) |
| Lars | 30% vs 35%: -5 pp (-15…+5 pp) | 40% vs 55%: -15 pp (-27…-2 pp) | 57% vs 75%: -17 pp (-29…-4 pp) |
| Ronny | 52% vs 45%: +8 pp (-29…+38 pp) | 70% vs 58%: +12 pp (-24…+42 pp) | 82% vs 73%: +9 pp (-20…+33 pp) |
| Hawk | 5% vs 13%: -8 pp (-15…0 pp) | 27% vs 50%: -23 pp (-36…-12 pp) | 52% vs 76%: -25 pp (-39…-7 pp) |

### Score bands without confidence (share of turns ≥ 3.5 and ≤ 2.5; available for every persona)

| Persona | High (≥ 3.5) | Low (≤ 2.5) |
|---|---|---|
| Paul | 100% vs 99%: +1 pp (0…+2 pp) | 0% vs 0%: 0 pp (0…0 pp) |
| Lotta | 78% vs 90%: -12 pp (-25…+1 pp) | 0% vs 0%: 0 pp (0…0 pp) |
| Lars | 80% vs 72%: +8 pp (-8…+23 pp) | 5% vs 4%: +1 pp (-6…+11 pp) |
| Ronny | 90% vs 95%: -5 pp (-25…+9 pp) | 0% vs 1%: -1 pp (-2…0 pp) |
| Hawk | 2% vs 6%: -4 pp (-11…+2 pp) | 78% vs 87%: -8 pp (-18…+3 pp) |

## Added 2026-10-08: confidence-weighted headline and sharper Paul/Lotta borders

Weighted headline = sum(score × confidence) / sum(confidence) over a persona's turns (sessions: over its sessions). Unsure = confidence < 0.7. Paul and Lotta: '#69' = the stricter rubric (baseline: second pass with turn confidences; post-rework: stored scores), 'sharp' = the sharpened borders (rubric 7862783 / 989546a), re-scored on both sides. Deltas: post-rework minus baseline, bootstrap 95% CI over runs.

### Per persona and dataset (turns; sessions in the last two columns)

| Persona | Rubric | Unsure base | Unsure post | **Weighted base** | **Weighted post** | Plain base | Plain post | Session weighted base | Session weighted post |
|---|---|---|---|---|---|---|---|---|---|
| Paul | #69 | 51% | 46% | 4.39 | 4.26 | 4.37 | 4.24 | 4.82 | 4.78 |
| Paul | sharp | 72% | 74% | 4.44 | 4.34 | 4.37 | 4.21 | 4.89 | 4.86 |
| Lotta | #69 | 75% | 86% | 3.92 | 3.86 | 3.91 | 3.84 | 4.32 | 4.27 |
| Lotta | sharp | 39% | 30% | 3.28 | 3.28 | 3.33 | 3.34 | 3.73 | 3.65 |
| Lars | stored | 55% | 40% | 3.73 | 3.76 | 3.66 | 3.70 | 4.04 | 4.06 |
| Ronny | stored | 58% | 70% | 4.62 | 4.58 | 4.44 | 4.33 | 4.46 | 4.29 |
| Hawk | stored | 50% | 27% | 1.90 | 2.12 | 1.93 | 2.10 | 3.00 | 3.34 |

### Deltas, post-rework minus baseline

| Persona | Rubric | Turn plain mean Δ (one mean per run) | **Turn weighted Δ** | Unsure share Δ | Session weighted Δ |
|---|---|---|---|---|---|
| Paul | #69 | -0.13 (-0.21…-0.04) | -0.12 (-0.20…-0.05) | -5 pp (-14…+4 pp) | -0.04 (-0.15…+0.08) |
| Paul | sharp | -0.16 (-0.30…-0.01) | -0.10 (-0.22…-0.01) | +2 pp (-12…+13 pp) | -0.03 (-0.13…+0.09) |
| Lotta | #69 | -0.07 (-0.28…+0.13) | -0.06 (-0.29…+0.18) | +11 pp (-11…+31 pp) | -0.05 (-0.52…+0.38) |
| Lotta | sharp | +0.01 (-0.25…+0.30) | 0.00 (-0.22…+0.30) | -9 pp (-36…+19 pp) | -0.08 (-0.74…+0.77) |
| Lars | stored | +0.04 (-0.22…+0.25) | +0.03 (-0.22…+0.23) | -15 pp (-26…-2 pp) | +0.02 (-0.26…+0.28) |
| Ronny | stored | -0.11 (-0.54…+0.28) | -0.04 (-0.22…+0.14) | +12 pp (-23…+42 pp) | -0.17 (-0.68…+0.19) |
| Hawk | stored | +0.17 (-0.06…+0.39) | +0.22 (+0.01…+0.41) | -23 pp (-35…-12 pp) | +0.34 (-0.42…+1.05) |

### Breakdown at 0.7 (turns)

| Persona | Rubric | Dataset | Turns | Confident-high | Confident-low | Confident-middle | Unsure |
|---|---|---|---|---|---|---|---|
| Paul | #69 | base | 130 | 64 (49%) | 0 (0%) | 0 (0%) | 66 (51%) |
| Paul | #69 | post | 50 | 27 (54%) | 0 (0%) | 0 (0%) | 23 (46%) |
| Paul | sharp | base | 130 | 36 (28%) | 0 (0%) | 0 (0%) | 94 (72%) |
| Paul | sharp | post | 50 | 13 (26%) | 0 (0%) | 0 (0%) | 37 (74%) |
| Lotta | #69 | base | 130 | 28 (22%) | 0 (0%) | 5 (4%) | 97 (75%) |
| Lotta | #69 | post | 50 | 6 (12%) | 0 (0%) | 1 (2%) | 43 (86%) |
| Lotta | sharp | base | 130 | 5 (4%) | 0 (0%) | 74 (57%) | 51 (39%) |
| Lotta | sharp | post | 50 | 3 (6%) | 0 (0%) | 32 (64%) | 15 (30%) |
| Lars | stored | base | 130 | 56 (43%) | 1 (1%) | 2 (2%) | 71 (55%) |
| Lars | stored | post | 40 | 23 (57%) | 1 (2%) | 0 (0%) | 16 (40%) |
| Ronny | stored | base | 130 | 54 (42%) | 0 (0%) | 0 (0%) | 76 (58%) |
| Ronny | stored | post | 40 | 12 (30%) | 0 (0%) | 0 (0%) | 28 (70%) |
| Hawk | stored | base | 156 | 2 (1%) | 73 (47%) | 3 (2%) | 78 (50%) |
| Hawk | stored | post | 60 | 1 (2%) | 34 (57%) | 9 (15%) | 16 (27%) |

### Baseline analysis score set (stored first pass; Paul and Lotta on the pre-#69 rubric)

| Persona | Turns | Plain mean | **Weighted** | Unsure | Session weighted |
|---|---|---|---|---|---|
| Paul | 130 | 4.70 | 4.77 | 17% | 4.81 |
| Lotta | 130 | 4.16 | 4.16 | 8% | 4.40 |
| Lars | 130 | 3.66 | 3.73 | 55% | 4.04 |
| Ronny | 130 | 4.44 | 4.62 | 58% | 4.46 |
| Hawk | 156 | 1.93 | 1.90 | 50% | 3.00 |

Sharpened re-score: 26 + 10 runs, Jev cost $0.0120 (Jev's own usage figure).

## Added 2026-10-08: Paul's level 5 needs a consequence of his own choice or discovery

Paul only. '#69' and 'sharp' as in the section above; 'consequence' = rubric df3c861 (a vivid answer or new fact is 4; 5 needs the world to react to his own choice or discovery), re-scored on both sides. Unsure = confidence < 0.7. Deltas: post-rework minus baseline, bootstrap 95% CI over runs (seed + 3).

### Per dataset (turns; sessions in the last two columns)

| Rubric | Unsure base | Unsure post | **Weighted base** | **Weighted post** | Plain base | Plain post | Session weighted base | Session weighted post |
|---|---|---|---|---|---|---|---|---|
| #69 | 51% | 46% | 4.39 | 4.26 | 4.37 | 4.24 | 4.82 | 4.78 |
| sharp | 72% | 74% | 4.44 | 4.34 | 4.37 | 4.21 | 4.89 | 4.86 |
| consequence | 33% | 48% | 4.41 | 4.27 | 4.37 | 4.21 | 4.88 | 4.86 |

### Deltas, post-rework minus baseline

| Rubric | **Turn weighted Δ** | Unsure share Δ | Session weighted Δ |
|---|---|---|---|
| #69 | -0.12 (-0.20…-0.05) | -5 pp (-14…+5 pp) | -0.04 (-0.15…+0.07) |
| sharp | -0.10 (-0.21…0.00) | +2 pp (-13…+13 pp) | -0.03 (-0.12…+0.08) |
| consequence | -0.14 (-0.24…-0.03) | +15 pp (+2…+28 pp) | -0.01 (-0.09…+0.08) |

### Breakdown at 0.7 (turns)

| Rubric | Dataset | Turns | Confident-high | Confident-low | Confident-middle | Unsure |
|---|---|---|---|---|---|---|
| #69 | base | 130 | 64 (49%) | 0 (0%) | 0 (0%) | 66 (51%) |
| #69 | post | 50 | 27 (54%) | 0 (0%) | 0 (0%) | 23 (46%) |
| sharp | base | 130 | 36 (28%) | 0 (0%) | 0 (0%) | 94 (72%) |
| sharp | post | 50 | 13 (26%) | 0 (0%) | 0 (0%) | 37 (74%) |
| consequence | base | 130 | 87 (67%) | 0 (0%) | 0 (0%) | 43 (33%) |
| consequence | post | 50 | 26 (52%) | 0 (0%) | 0 (0%) | 24 (48%) |

### Most likely level and mean level probabilities (Jev's turn vectors, levels 1–5)

| Rubric | Dataset | Most likely level 1/2/3/4/5 (turns) | Mean p, sure turns | Mean p, unsure turns |
|---|---|---|---|---|
| sharp | base | 0 / 1 / 4 / 54 / 71 | 0.00 / 0.01 / 0.03 / 0.26 / 0.70 | 0.01 / 0.03 / 0.10 / 0.42 / 0.45 |
| sharp | post | 0 / 0 / 0 / 21 / 29 | 0.00 / 0.01 / 0.05 / 0.35 / 0.58 | 0.01 / 0.06 / 0.15 / 0.36 / 0.42 |
| consequence | base | 0 / 0 / 3 / 75 / 52 | 0.00 / 0.00 / 0.02 / 0.51 / 0.47 | 0.01 / 0.03 / 0.07 / 0.47 / 0.43 |
| consequence | post | 0 / 0 / 0 / 30 / 20 | 0.00 / 0.01 / 0.03 / 0.63 / 0.34 | 0.01 / 0.06 / 0.11 / 0.42 / 0.40 |

Consequence re-score: 13 + 5 Paul runs, Jev cost $0.0062 (Jev's own usage figure).

