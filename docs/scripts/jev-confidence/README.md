# jev-confidence: a confidence-aware reading of Jev scores

Re-reads existing Jev scores as a score-by-confidence matrix ([decision 2026-10-08](../../decisions.md#2026-10-08-jev-scores-are-read-as-a-score-by-confidence-matrix-not-a-plain-average)). No new runs, no Jev calls, nothing written to any database.

- **high** = score ≥ 3.5 (nearest level 4–5), **low** = score ≤ 2.5 (nearest level 1–2), **middle** = in between (level 3).
- **confident** = Jev's confidence ≥ the cutoff (headline 0.7; sensitivity 0.6 and 0.8); **unsure** = below it (the low-confidence share).
- **headline** = mean score of the confident turns (or sessions). Deltas: post-rework minus baseline, bootstrap 95% CIs over runs (5000 resamples, seed 7).
- "Too few" (⚠): a side has < 20 confident turns or < 3 runs with one, or < 3 confident sessions.

Rerun (about 90 s; inputs are the CSVs `jev-compare/compare.py` wrote for the two analyses, on the box):

```bash
python3 docs/scripts/jev-confidence/confidence_matrix.py /workspace/baseline/final /workspace/compare/final \
  --json docs/scripts/jev-confidence/results-2026-10-08.json > docs/scripts/jev-confidence/results-2026-10-08.md
```

`results-2026-10-08.md` / `.json` are the output used in the two analyses' "Update 2026-10-08" sections. Paul's and Lotta's baseline re-scores with the stricter #69 rubric (`jev-rescore/rescore-baseline-2026-10-07-main.json`) kept the session confidence but not the turn confidences, so their turn-level comparison is marked n/a.

*Added 2026-10-08:* Paul's and Lotta's baseline runs were re-scored again with the stricter rubric, keeping turn confidences. That was 26 Jev calls for $0.0067, run from the box with `mix run --no-start`, so the app and its database never started. The rows are in `jev-rescore/rescore-baseline-2026-10-08-conf.json`. `--rescore-conf` reads them and fills the Paul and Lotta turn-level cells. The output is `results-2026-10-08-conf.md` / `.json`; the cells that were already there are unchanged (they use their own random stream).

```bash
# re-score (Jev only), from an ex-tales-forge checkout of main with TYPESAFE_API_KEY set
RUBRICS=new EXPORT=/workspace/baseline/final/jev_export.json OUT=rescore-baseline-2026-10-08-conf.json \
  mix run --no-start docs/scripts/jev-rescore/rescore.exs
python3 docs/scripts/jev-confidence/confidence_matrix.py /workspace/baseline/final /workspace/compare/final \
  --rescore-conf docs/scripts/jev-rescore/rescore-baseline-2026-10-08-conf.json \
  --json docs/scripts/jev-confidence/results-2026-10-08-conf.json > docs/scripts/jev-confidence/results-2026-10-08-conf.md
```
