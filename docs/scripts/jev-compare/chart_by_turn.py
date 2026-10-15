#!/usr/bin/env python3
"""Score and confidence by turn, per persona, series vs the Elara runs.

Usage: python3 chart_by_turn.py DIR OUT.png [SERIES]   (DIR = compare.py --csv output)
"""
import sys
import pandas as pd, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D, OUT = sys.argv[1], sys.argv[2]
SERIES = sys.argv[3] if len(sys.argv) > 3 else "baseline-2026-10-07"
T = pd.read_csv(f"{D}/turns.csv")
T["src"] = T.cohort.where(T.cohort == "elara", "series")
fig, ax = plt.subplots(1, 2, figsize=(12, 4.5))
for i, (val, lab) in enumerate([("score", "Jev turn score (1–5)"), ("conf", "Jev confidence")]):
    for p, col in zip(["paul", "lotta", "lars", "hawk", "ronny"], ["C0", "C1", "C2", "C3", "C7"]):
        s = T[(T.src == "series") & (T.persona == p)].groupby("turn")[val].mean()
        ax[i].plot(s.index, s.values, "-o", color=col, ms=3, label=f"{p} (series)")
        e = T[(T.src == "elara") & (T.persona == p) & (T.turn <= 5)].groupby("turn")[val]
        if e.size().min() >= 5:
            ax[i].plot(e.mean().index, e.mean().values, "--", color=col, alpha=.6, label=f"{p} (Elara)")
    ax[i].set_xlabel("turn"); ax[i].set_ylabel(lab); ax[i].grid(alpha=.3)
ax[0].legend(fontsize=7, ncol=2)
fig.suptitle(f"{SERIES}: by turn (dashed = Elara runs, only personas with ≥5 Elara runs per turn)")
fig.tight_layout(); fig.savefig(OUT, dpi=110)
print(OUT)
