#!/usr/bin/env python3
"""Confidence-aware reading of Jev scores (decision 2026-10-08).

Re-reads EXISTING Jev scores as a score-by-confidence matrix. No new runs, no LLM calls, no database
writes. Inputs are the CSVs that jev-compare/compare.py wrote for the two analyses:

  BASELINE_DIR  /workspace/baseline/final  (docs/analysis-jev-baseline-2026-10-07.md; stored first-pass
                scores, i.e. Paul and Lotta on the rubric of that day)
  COMPARE_DIR   /workspace/compare/final   (docs/analysis-jev-post-rework-2026-10-08.md; baseline Paul and
                Lotta re-scored with the stricter #69 rubric, so both sides use the same rubric)

Definitions (score = Jev's expected level on 1-5, confidence = Jev's own 0-1 confidence):
  high      score >= 3.5  (nearest level 4 or 5: the persona's "works" levels)
  low       score <= 2.5  (nearest level 1 or 2: the persona's "broken" levels)
  middle    2.5 < score < 3.5 (nearest level 3, "Mixed" / Hawk "Closing in")
  confident confidence >= cutoff; headline cutoff 0.7, sensitivity at 0.6 and 0.8
  unsure    confidence < cutoff (= the low-confidence share)
  headline  mean score of the confident turns (pooled over the persona's runs)

Deltas are post-rework minus baseline. CIs: bootstrap over runs (5000 resamples, seed 7), resampling whole
runs and recomputing the statistic on the resampled turns, as the original analyses did.
A cell is flagged "too few" when a side has < 20 confident turns or < 3 runs with one (turn level),
or < 3 confident sessions (session level).

Added 2026-10-08: --rescore-conf FILE (jev-rescore/rescore.exs with RUBRICS=new, which keeps turn confidences)
replaces the compared baseline's Paul and Lotta session and turn scores and confidences with that pass, so
their turn-level reading is like for like. The "old" plain-average deltas stay on the scores the analysis used
(the earlier re-score); the plain delta on the new pass is shown next to them to separate Jev's run-to-run noise
from the change of reading.

Usage: python3 confidence_matrix.py BASELINE_DIR COMPARE_DIR [--rescore-conf FILE] [--json OUT.json] > out.md
"""
import json, sys
import numpy as np, pandas as pd

HI, LO = 3.5, 2.5
CUTS = (0.6, 0.7, 0.8)
MAIN = 0.7
PERS = ["paul", "lotta", "lars", "ronny", "hawk"]
NAME = {p: p.capitalize() for p in PERS}
BASE, NEW = "baseline-2026-10-07", "post-rework-2026-10-08"
NBOOT, SEED = 5000, 7
MIN_TURNS, MIN_RUNS, MIN_SESS = 20, 3, 3

args = [a for a in sys.argv[1:]]
jout = None
if "--json" in args:
    i = args.index("--json"); jout = args[i + 1]; del args[i:i + 2]
rconf = None
if "--rescore-conf" in args:
    i = args.index("--rescore-conf"); rconf = args[i + 1]; del args[i:i + 2]
BDIR, CDIR = args[0], args[1]
out = {}
w = print


def table(rows, cols, head=None):
    head = head or cols
    s = "| " + " | ".join(head) + " |\n|" + "---|" * len(head) + "\n"
    for r in rows:
        s += "| " + " | ".join(str(r.get(c, "")) for c in cols) + " |\n"
    return s


def f2(x): return "—" if x is None or (isinstance(x, float) and np.isnan(x)) else "%.2f" % x
def nz(x, k): return 0.0 if round(x, k) == 0 else x  # no "-0.00"
def sg(x): return "—" if x is None or (isinstance(x, float) and np.isnan(x)) else ("%+.2f" % nz(x, 2)).replace("+0.00", "0.00")
def pp(x): return "%+.0f" % nz(100 * x, 0) if round(100 * x) else "0"
def pc(x): return "—" if x is None or (isinstance(x, float) and np.isnan(x)) else "%.0f%%" % (100 * x)
def ci(lo, hi, pct=False):
    if lo is None or np.isnan(lo): return "—"
    return f"{pp(lo)}…{pp(hi)} pp" if pct else f"{sg(lo)}…{sg(hi)}"


def load(d):
    R, T = pd.read_csv(f"{d}/runs.csv"), pd.read_csv(f"{d}/turns.csv")
    return R, T


def matrix(scores, confs, c):
    """Counts for one persona/dataset/cutoff. confs may be all-NaN (unknown)."""
    s, k = np.asarray(scores, float), np.asarray(confs, float)
    n = len(s)
    if n == 0 or np.isnan(k).all():
        return dict(n=n, known=False)
    conf = k >= c
    nc = int(conf.sum())
    return dict(n=n, known=True, n_conf=nc,
                headline=float(s[conf].mean()) if nc else np.nan,
                unsure=int((~conf).sum()), unsure_share=float((~conf).mean()),
                hi=int((conf & (s >= HI)).sum()), lo=int((conf & (s <= LO)).sum()),
                mid=int((conf & (s > LO) & (s < HI)).sum()))


def runs_arrays(T, c):
    """Per run: sum of confident scores, n confident, n turns, sum of all scores, n unsure."""
    g = T.assign(cf=(T.conf >= c), cs=np.where(T.conf >= c, T.score, 0.0)).groupby("run_id")
    a = g.agg(cs=("cs", "sum"), cn=("cf", "sum"), n=("score", "size"), s=("score", "sum"))
    a["mean"] = a.s / a.n
    return a


def boot_delta(A, B, stat, rng):
    """A, B: per-run frames; stat(frame) -> value. Returns (point, lo, hi, share of resamples undefined)."""
    pt = stat(A) - stat(B)
    d, bad = [], 0
    ia, ib = np.arange(len(A)), np.arange(len(B))
    for _ in range(NBOOT):
        v = stat(A.iloc[rng.choice(ia, len(ia))]) - stat(B.iloc[rng.choice(ib, len(ib))])
        if np.isnan(v): bad += 1
        else: d.append(v)
    if len(d) < NBOOT * 0.5:
        return pt, np.nan, np.nan, bad / NBOOT
    lo, hi = np.percentile(d, [2.5, 97.5])
    return pt, lo, hi, bad / NBOOT


def pooled_conf_mean(a): return a.cs.sum() / a.cn.sum() if a.cn.sum() else np.nan
def run_mean_mean(a): return a["mean"].mean()
def unsure_share(a): return 1 - a.cn.sum() / a.n.sum()
def share_band(a): return a.band.sum() / a.n.sum()


def per_dataset(label, R, T):
    """Matrix tables for one dataset; returns a dict for JSON."""
    res = {}
    w(f"#### Turns: {label}\n")
    rows = []
    for p in PERS:
        t = T[T.persona == p]
        m7 = matrix(t.score, t.conf, MAIN)
        r = dict(p=NAME[p], n=f"{len(t)} ({t.run_id.nunique()} runs)", plain=f2(t.score.mean()))
        res[p] = {"turns": {"n": len(t), "runs": int(t.run_id.nunique()), "plain_mean": float(t.score.mean()),
                            "high_share_any_conf": float((t.score >= HI).mean()), "low_share_any_conf": float((t.score <= LO).mean())}}
        if not m7["known"]:
            r.update(h6="no conf", h7="no conf", h8="no conf", lc="unknown", hi="—", lo="—", mid="—", un="—")
            r["band"] = f"{pc((t.score >= HI).mean())} / {pc((t.score <= LO).mean())}"
            res[p]["turns"]["confidence"] = None
            rows.append(r); continue
        for c in CUTS:
            m = matrix(t.score, t.conf, c)
            nr = t[t.conf >= c].run_id.nunique()
            few = m["n_conf"] < MIN_TURNS or nr < MIN_RUNS
            r[f"h{int(c*10)}"] = f"{f2(m['headline'])} (n={m['n_conf']}){' ⚠' if few else ''}"
            res[p]["turns"][f"cut_{c}"] = dict(m, runs_with_conf=int(nr), too_few=bool(few))
        r["lc"] = f"{pc(m7['unsure_share'])} ({m7['unsure']})"
        r["hi"] = f"{m7['hi']} ({pc(m7['hi']/m7['n'])})"
        r["lo"] = f"{m7['lo']} ({pc(m7['lo']/m7['n'])})"
        r["mid"] = f"{m7['mid']} ({pc(m7['mid']/m7['n'])})"
        r["un"] = f"{m7['unsure']} ({pc(m7['unsure']/m7['n'])})"
        r["band"] = f"{pc((t.score >= HI).mean())} / {pc((t.score <= LO).mean())}"
        rows.append(r)
    w(table(rows, ["p", "n", "plain", "h6", "h7", "h8", "lc", "hi", "lo", "mid", "un", "band"],
            ["Persona", "Turns", "Plain mean", "Headline ≥0.6", "**Headline ≥0.7**", "Headline ≥0.8",
             "Low-conf share (<0.7)", "Confident-high", "Confident-low", "Confident-middle", "Unsure", "High / low, any conf"]))
    w(f"Headline = mean of turns with confidence ≥ cutoff (n = turns kept). Matrix columns at cutoff 0.7; shares are of all turns. "
      f"⚠ = fewer than {MIN_TURNS} confident turns or {MIN_RUNS} runs.\n")

    w("Low-confidence share at each cutoff (share of turns below it):\n")
    rows = []
    for p in PERS:
        t = T[T.persona == p]
        if t.conf.isna().all():
            rows.append(dict(p=NAME[p], a="unknown", b="unknown", c="unknown", z="unknown")); continue
        rows.append(dict(p=NAME[p], a=pc((t.conf < 0.6).mean()), b=pc((t.conf < 0.7).mean()), c=pc((t.conf < 0.8).mean()),
                         z=f"{int((t.conf == 0).sum())}"))
        res[p]["turns"]["conf_zero"] = int((t.conf == 0).sum())
    w(table(rows, ["p", "a", "b", "c", "z"], ["Persona", "< 0.6", "**< 0.7**", "< 0.8", "Confidence exactly 0"]))

    w(f"#### Sessions: {label}\n")
    rows = []
    for p in PERS:
        r_ = R[R.persona == p]
        r = dict(p=NAME[p], n=len(r_), plain=f2(r_.session_score.mean()))
        res[p]["sessions"] = {"n": len(r_), "plain_mean": float(r_.session_score.mean())}
        for c in CUTS:
            m = matrix(r_.session_score, r_.session_conf, c)
            few = m["n_conf"] < MIN_SESS
            r[f"h{int(c*10)}"] = f"{f2(m['headline'])} (n={m['n_conf']}){' ⚠' if few else ''}"
            res[p]["sessions"][f"cut_{c}"] = dict(m, too_few=bool(few))
        m = matrix(r_.session_score, r_.session_conf, MAIN)
        r.update(lc=f"{pc(m['unsure_share'])} ({m['unsure']})", hi=m["hi"], lo=m["lo"], mid=m["mid"])
        rows.append(r)
    w(table(rows, ["p", "n", "plain", "h6", "h7", "h8", "lc", "hi", "lo", "mid"],
            ["Persona", "Sessions", "Plain mean", "Headline ≥0.6", "**Headline ≥0.7**", "Headline ≥0.8",
             "Unsure (<0.7)", "Confident-high", "Confident-low", "Confident-middle"]))
    w(f"⚠ = fewer than {MIN_SESS} confident sessions.\n")
    return res


# ---------------------------------------------------------------- baseline analysis (stored scores)
w("## Baseline 2026-10-07 (65 runs; stored first-pass scores, as in that analysis)\n")
RB, TB = load(BDIR)
RB, TB = RB[RB.cohort.str.startswith(BASE)], TB[TB.cohort.str.startswith(BASE)]
out["baseline_stored"] = per_dataset("baseline, stored scores (Paul and Lotta on the pre-#69 rubric)", RB, TB)

# ---------------------------------------------------------------- post-rework comparison (like for like)
RC, TC = load(CDIR)
RC0, TC0 = RC.copy(), TC.copy()  # the scores the analysis used (old plain deltas)
REPLACED = set()
if rconf:
    rows_ = [r for r in json.load(open(rconf)) if r["rubric"] == "new"]
    for r in rows_:
        mb = RC.cohort.str.startswith(BASE) & (RC.run_id == r["run"])
        assert mb.sum() == 1, r["run"]
        RC.loc[mb, ["session_score", "session_conf"]] = [r["session"], r["session_conf"]]
        mt = TC.cohort.str.startswith(BASE) & (TC.run_id == r["run"])
        ns = sorted(TC.loc[mt, "turn"])
        assert len(ns) == len(r["turns"]) == len(r["turn_conf"]), r["run"]
        for n, sc, cf, pr in zip(ns, r["turns"], r["turn_conf"], r["turn_probs"]):
            m = mt & (TC.turn == n)
            TC.loc[m, ["score", "conf"]] = [sc, cf]
            TC.loc[m, "probs"] = json.dumps(pr)
        REPLACED.add(r["persona"])
    w(f"Paul and Lotta baseline (stricter rubric): scores and confidences from `{rconf.split('/')[-1]}` "
      f"({len(rows_)} runs, re-scored 2026-10-08 with turn confidences kept).\n")
w("## Post-rework comparison (Paul and Lotta on the stricter #69 rubric on both sides)\n")
out["compare_baseline"] = per_dataset("baseline as compared (Paul and Lotta re-scored with the stricter rubric" +
                                      ("; second pass, turn confidences kept)" if REPLACED else "; their turn confidences were not kept)"),
                                      RC[RC.cohort.str.startswith(BASE)], TC[TC.cohort.str.startswith(BASE)])
out["compare_new"] = per_dataset("post-rework 2026-10-08 (23 completed runs)",
                                 RC[RC.cohort.str.startswith(NEW)], TC[TC.cohort.str.startswith(NEW)])

w("## Deltas, post-rework minus baseline\n")
rng = np.random.default_rng(SEED)
# Cells added on 2026-10-08 (Paul/Lotta turn level, second-pass plain deltas) draw from their own stream, so the
# CIs published before them stay exactly reproducible.
rng2 = np.random.default_rng(SEED + 1)
out["deltas"] = {}
srows, trows, lrows, brows = [], [], [], []
for p in PERS:
    D = out["deltas"][p] = {}
    ra, rb = RC[RC.cohort.str.startswith(NEW) & (RC.persona == p)], RC[RC.cohort.str.startswith(BASE) & (RC.persona == p)]
    ta, tb = TC[TC.cohort.str.startswith(NEW) & (TC.persona == p)], TC[TC.cohort.str.startswith(BASE) & (TC.persona == p)]
    # sessions: one row per run
    sa = pd.DataFrame(dict(cs=np.where(ra.session_conf >= 0, ra.session_score, 0.0), n=1.0, s=ra.session_score.values,
                           conf=ra.session_conf.values)).reset_index(drop=True)
    sb = pd.DataFrame(dict(n=1.0, s=rb.session_score.values, conf=rb.session_conf.values)).reset_index(drop=True)
    rb0 = RC0[RC0.cohort.str.startswith(BASE) & (RC0.persona == p)]
    sb0 = pd.DataFrame(dict(n=1.0, s=rb0.session_score.values)).reset_index(drop=True)
    pt, lo, hi, _ = boot_delta(sa, sb0, lambda a: a.s.mean(), rng)
    D["session_plain"] = dict(d=pt, lo=lo, hi=hi)
    r = dict(p=NAME[p], old=f"{sg(pt)} ({ci(lo, hi)})")
    if p in REPLACED:
        pt, lo, hi, _ = boot_delta(sa, sb, lambda a: a.s.mean(), rng2)
        D["session_plain_pass2"] = dict(d=pt, lo=lo, hi=hi)
        r["old"] += f"; 2nd pass {sg(pt)} ({ci(lo, hi)})"
    for c in CUTS:
        st = lambda a, c=c: a.s[a.conf >= c].mean() if (a.conf >= c).any() else np.nan
        na, nb = int((sa.conf >= c).sum()), int((sb.conf >= c).sum())
        pt, lo, hi, bad = boot_delta(sa, sb, st, rng)
        few = na < MIN_SESS or nb < MIN_SESS
        D[f"session_conf_{c}"] = dict(d=pt, lo=lo, hi=hi, n_new=na, n_base=nb, too_few=few, undefined_resamples=bad)
        r[f"c{int(c*10)}"] = f"{sg(pt)} ({ci(lo, hi)}) n={na}/{nb}{' ⚠' if few else ''}"
    srows.append(r)

    # turns
    known_b = not tb.conf.isna().all()
    tb0 = TC0[TC0.cohort.str.startswith(BASE) & (TC0.persona == p)]
    A0, B0 = runs_arrays(ta, MAIN), runs_arrays(tb0, MAIN)
    pt, lo, hi, _ = boot_delta(A0, B0, run_mean_mean, rng)
    D["turn_plain"] = dict(d=pt, lo=lo, hi=hi)
    r = dict(p=NAME[p], old=f"{sg(pt)} ({ci(lo, hi)})")
    if p in REPLACED:
        pt, lo, hi, _ = boot_delta(A0, runs_arrays(tb, MAIN), run_mean_mean, rng2)
        D["turn_plain_pass2"] = dict(d=pt, lo=lo, hi=hi)
        r["old"] += f"; 2nd pass {sg(pt)} ({ci(lo, hi)})"
    for c in CUTS:
        if not known_b:
            r[f"c{int(c*10)}"] = "n/a: baseline turn conf not kept"
            D[f"turn_conf_{c}"] = None; continue
        A, B = runs_arrays(ta, c), runs_arrays(tb, c)
        pt, lo, hi, bad = boot_delta(A, B, pooled_conf_mean, rng2 if p in REPLACED else rng)
        na, nb = int(A.cn.sum()), int(B.cn.sum())
        few = na < MIN_TURNS or nb < MIN_TURNS or (A.cn > 0).sum() < MIN_RUNS or (B.cn > 0).sum() < MIN_RUNS
        D[f"turn_conf_{c}"] = dict(d=pt, lo=lo, hi=hi, n_new=na, n_base=nb, too_few=bool(few), undefined_resamples=bad)
        r[f"c{int(c*10)}"] = f"{sg(pt)} ({ci(lo, hi)}) n={na}/{nb}{' ⚠' if few else ''}"
    trows.append(r)

    # low-confidence share
    r = dict(p=NAME[p])
    for c in CUTS:
        if not known_b:
            r[f"c{int(c*10)}"] = "n/a"; D[f"lowconf_{c}"] = None; continue
        A, B = runs_arrays(ta, c), runs_arrays(tb, c)
        pt, lo, hi, _ = boot_delta(A, B, unsure_share, rng2 if p in REPLACED else rng)
        D[f"lowconf_{c}"] = dict(d=pt, lo=lo, hi=hi, new=unsure_share(A), base=unsure_share(B))
        r[f"c{int(c*10)}"] = f"{pc(unsure_share(A))} vs {pc(unsure_share(B))}: {pp(pt)} pp ({ci(lo, hi, True)})"
    lrows.append(r)

    # score bands, no confidence (works for every persona, including Paul and Lotta)
    r = dict(p=NAME[p])
    for band, f in (("high", lambda s: s >= HI), ("low", lambda s: s <= LO)):
        A = ta.assign(band=f(ta.score)).groupby("run_id").agg(band=("band", "sum"), n=("score", "size"))
        B = tb.assign(band=f(tb.score)).groupby("run_id").agg(band=("band", "sum"), n=("score", "size"))
        pt, lo, hi, _ = boot_delta(A, B, share_band, rng)
        D[f"share_{band}_any_conf"] = dict(d=pt, lo=lo, hi=hi, new=share_band(A), base=share_band(B))
        r[band] = f"{pc(share_band(A))} vs {pc(share_band(B))}: {pp(pt)} pp ({ci(lo, hi, True)})"
    brows.append(r)

w("### Session score\n")
w(table(srows, ["p", "old", "c6", "c7", "c8"], ["Persona", "Old: plain mean Δ (95% CI)", "Confident only ≥0.6", "**Confident only ≥0.7**", "Confident only ≥0.8"]))
w(f"n = confident sessions new/base. ⚠ = fewer than {MIN_SESS} on a side.\n")
w("### Turn score\n")
w(table(trows, ["p", "old", "c6", "c7", "c8"], ["Persona", "Old: turn mean Δ, one mean per run (95% CI)", "Confident only ≥0.6", "**Confident only ≥0.7**", "Confident only ≥0.8"]))
w(f"n = confident turns new/base. ⚠ = fewer than {MIN_TURNS} confident turns or {MIN_RUNS} runs with one on a side.\n")
w("### Low-confidence share of turns (new vs base, Δ in percentage points)\n")
w(table(lrows, ["p", "c6", "c7", "c8"], ["Persona", "< 0.6", "**< 0.7**", "< 0.8"]))
w("### Score bands without confidence (share of turns ≥ 3.5 and ≤ 2.5; available for every persona)\n")
w(table(brows, ["p", "high", "low"], ["Persona", "High (≥ 3.5)", "Low (≤ 2.5)"]))

if jout:
    def clean(o):
        if isinstance(o, dict): return {k: clean(v) for k, v in o.items()}
        if isinstance(o, (np.floating, float)): return None if np.isnan(o) else round(float(o), 4)
        if isinstance(o, (np.integer,)): return int(o)
        if isinstance(o, (np.bool_,)): return bool(o)
        return o
    json.dump(clean(out), open(jout, "w"), indent=1)
