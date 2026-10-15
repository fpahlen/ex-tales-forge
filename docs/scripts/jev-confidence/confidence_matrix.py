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

Added 2026-10-08 (decision "confidence-weighted headline"): --sharp-base FILE --sharp-post FILE (rescore.exs rows
with the sharpened Paul/Lotta borders, rubric 7862783 / 989546a) append a section with the confidence-weighted
headline, sum(score x confidence) / sum(confidence), for every persona, and Paul and Lotta on the #69 rubric vs
the sharpened one: unsure share (< 0.7), weighted headline, breakdown and post-rework-minus-baseline deltas with
bootstrap CIs over runs. Needs --rescore-conf (the #69 baseline pass with turn confidences). Own random stream.

Usage: python3 confidence_matrix.py BASELINE_DIR COMPARE_DIR [--rescore-conf FILE]
       [--sharp-base FILE --sharp-post FILE] [--json OUT.json] > out.md
Added 2026-10-08 (decision "Paul's level 5 needs a consequence of his own choice or discovery"): --paul-cons-base FILE
--paul-cons-post FILE (rescore.exs rows for Paul with rubric df3c861; needs --sharp-*) append a Paul-only section
comparing #69, the first sharp version and the consequence version: unsure share, weighted headline, breakdown,
deltas, most likely level and the mean level probabilities of sure and unsure turns. Bootstrap seed SEED + 3.
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
def opt(name):
    if name in args:
        i = args.index(name); v = args[i + 1]; del args[i:i + 2]; return v
sharp_b, sharp_p = opt("--sharp-base"), opt("--sharp-post")
cons_b, cons_p = opt("--paul-cons-base"), opt("--paul-cons-post")
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

# ---------------------------------------------------------------- added 2026-10-08: weighted headline, sharper borders
def wmean(sc, cf):
    sc, cf = np.asarray(sc, float), np.asarray(cf, float)
    return float((sc * cf).sum() / cf.sum()) if cf.sum() > 0 else np.nan


def wruns(t):
    a = t.assign(sw=t.score * t.conf).groupby("run_id").agg(sw=("sw", "sum"), w=("conf", "sum"), n=("score", "size"),
                                                             un=("conf", lambda c: (c < MAIN).sum()))
    return a


def wstat(a): return a.sw.sum() / a.w.sum() if a.w.sum() > 0 else np.nan
def ustat(a): return a.un.sum() / a.n.sum()


def sharp_frames(path, cohort_runs):
    """Turn and session frames from rescore.exs rows, keyed like turns.csv."""
    tr, sr = [], []
    for r in json.load(open(path)):
        ns = sorted(cohort_runs[r["run"]])
        assert len(ns) == len(r["turns"]), r["run"]
        for n, sc, cf in zip(ns, r["turns"], r["turn_conf"]):
            tr.append(dict(run_id=r["run"], persona=r["persona"], turn=n, score=sc, conf=cf))
        sr.append(dict(run_id=r["run"], persona=r["persona"], session_score=r["session"], session_conf=r["session_conf"]))
    return pd.DataFrame(tr), pd.DataFrame(sr)


if sharp_b and sharp_p:
    assert REPLACED, "--sharp-* needs --rescore-conf"
    rng3 = np.random.default_rng(SEED + 2)
    tb_all = TC[TC.cohort.str.startswith(BASE)]; ta_all = TC[TC.cohort.str.startswith(NEW)]
    rb_all = RC[RC.cohort.str.startswith(BASE)]; ra_all = RC[RC.cohort.str.startswith(NEW)]
    runs_turns = {k: list(v) for k, v in TC.groupby("run_id").turn}
    stb, ssb = sharp_frames(sharp_b, runs_turns)
    sta, ssa = sharp_frames(sharp_p, runs_turns)
    out["weighted"] = {}
    w("## Added 2026-10-08: confidence-weighted headline and sharper Paul/Lotta borders\n")
    w("Weighted headline = sum(score × confidence) / sum(confidence) over a persona's turns (sessions: over its sessions). "
      f"Unsure = confidence < {MAIN}. Paul and Lotta: '#69' = the stricter rubric (baseline: second pass with turn "
      "confidences; post-rework: stored scores), 'sharp' = the sharpened borders (rubric 7862783 / 989546a), "
      "re-scored on both sides. Deltas: post-rework minus baseline, bootstrap 95% CI over runs.\n")
    sets = []
    for p in PERS:
        sets.append((p, "#69" if p in ("paul", "lotta") else "stored", tb_all[tb_all.persona == p], ta_all[ta_all.persona == p],
                     rb_all[rb_all.persona == p], ra_all[ra_all.persona == p]))
        if p in ("paul", "lotta"):
            sets.append((p, "sharp", stb[stb.persona == p], sta[sta.persona == p], ssb[ssb.persona == p], ssa[ssa.persona == p]))
    rows, drows, brows = [], [], []
    for p, rub, tb_, ta_, rb_, ra_ in sets:
        key = f"{p}/{rub}"; W = out["weighted"][key] = {}
        for lab, t, r in (("base", tb_, rb_), ("post", ta_, ra_)):
            m = matrix(t.score, t.conf, MAIN)
            W[lab] = dict(n=len(t), plain=float(t.score.mean()), weighted=wmean(t.score, t.conf), unsure=m["unsure_share"],
                          hi=m["hi"], lo=m["lo"], mid=m["mid"], un=m["unsure"],
                          session_weighted=wmean(r.session_score, r.session_conf),
                          session_unsure=float((r.session_conf < MAIN).mean()))
            brows.append(dict(p=NAME[p], rub=rub, ds=lab, n=len(t), hi=f"{m['hi']} ({pc(m['hi']/m['n'])})",
                              lo=f"{m['lo']} ({pc(m['lo']/m['n'])})", mid=f"{m['mid']} ({pc(m['mid']/m['n'])})",
                              un=f"{m['unsure']} ({pc(m['unsure_share'])})"))
        A, B = wruns(ta_), wruns(tb_)
        dw = boot_delta(A, B, wstat, rng3); du = boot_delta(A, B, ustat, rng3)
        sa = pd.DataFrame(dict(sw=ra_.session_score.values * ra_.session_conf.values, w=ra_.session_conf.values))
        sb = pd.DataFrame(dict(sw=rb_.session_score.values * rb_.session_conf.values, w=rb_.session_conf.values))
        ds = boot_delta(sa, sb, wstat, rng3)
        A0, B0 = runs_arrays(ta_, MAIN), runs_arrays(tb_, MAIN)
        dp = boot_delta(A0, B0, run_mean_mean, rng3)
        W["delta"] = dict(weighted=dict(zip(("d", "lo", "hi"), dw[:3])), unsure=dict(zip(("d", "lo", "hi"), du[:3])),
                          session_weighted=dict(zip(("d", "lo", "hi"), ds[:3])), plain=dict(zip(("d", "lo", "hi"), dp[:3])))
        b, a = W["base"], W["post"]
        rows.append(dict(p=NAME[p], rub=rub, ub=pc(b["unsure"]), ua=pc(a["unsure"]), wb=f2(b["weighted"]), wa=f2(a["weighted"]),
                         pb=f2(b["plain"]), pa=f2(a["plain"]), sb=f2(b["session_weighted"]), sa=f2(a["session_weighted"])))
        drows.append(dict(p=NAME[p], rub=rub, dp=f"{sg(dp[0])} ({ci(dp[1], dp[2])})", dw=f"{sg(dw[0])} ({ci(dw[1], dw[2])})",
                          du=f"{pp(du[0])} pp ({ci(du[1], du[2], True)})", ds=f"{sg(ds[0])} ({ci(ds[1], ds[2])})"))
    w("### Per persona and dataset (turns; sessions in the last two columns)\n")
    w(table(rows, ["p", "rub", "ub", "ua", "wb", "wa", "pb", "pa", "sb", "sa"],
            ["Persona", "Rubric", "Unsure base", "Unsure post", "**Weighted base**", "**Weighted post**", "Plain base", "Plain post",
             "Session weighted base", "Session weighted post"]))
    w("### Deltas, post-rework minus baseline\n")
    w(table(drows, ["p", "rub", "dp", "dw", "du", "ds"],
            ["Persona", "Rubric", "Turn plain mean Δ (one mean per run)", "**Turn weighted Δ**", "Unsure share Δ", "Session weighted Δ"]))
    w(f"### Breakdown at {MAIN} (turns)\n")
    w(table(brows, ["p", "rub", "ds", "n", "hi", "lo", "mid", "un"],
            ["Persona", "Rubric", "Dataset", "Turns", "Confident-high", "Confident-low", "Confident-middle", "Unsure"]))
    w("### Baseline analysis score set (stored first pass; Paul and Lotta on the pre-#69 rubric)\n")
    rows = []
    for p in PERS:
        t, r = TB[TB.persona == p], RB[RB.persona == p]
        m = matrix(t.score, t.conf, MAIN)
        out["weighted"][f"{p}/stored-baseline"] = dict(weighted=wmean(t.score, t.conf), unsure=m["unsure_share"],
                                                       session_weighted=wmean(r.session_score, r.session_conf))
        rows.append(dict(p=NAME[p], n=len(t), pl=f2(t.score.mean()), wt=f2(wmean(t.score, t.conf)), un=pc(m["unsure_share"]),
                         sw=f2(wmean(r.session_score, r.session_conf))))
    w(table(rows, ["p", "n", "pl", "wt", "un", "sw"], ["Persona", "Turns", "Plain mean", "**Weighted**", "Unsure", "Session weighted"]))
    cost = sum(r["usage"]["cost"] for f in (sharp_b, sharp_p) for r in json.load(open(f)) if r.get("usage"))
    w(f"Sharpened re-score: {len(ssb)} + {len(ssa)} runs, Jev cost ${cost:.4f} (Jev's own usage figure).\n")

# ---------------------------------------------------------------- added 2026-10-08: Paul's level 5 = a consequence
def probs_frame(path):
    """Per-turn probability vectors (levels 1..5) and confidences from rescore.exs rows."""
    rows = []
    for r in json.load(open(path)):
        for cf, pr in zip(r["turn_conf"], r["turn_probs"]):
            rows.append([cf] + [pr[str(i)] for i in range(5)])
    return np.array(rows)


if cons_b and cons_p:
    assert sharp_b and sharp_p, "--paul-cons-* needs --sharp-*"
    rng4 = np.random.default_rng(SEED + 3)
    ctb, csb = sharp_frames(cons_b, runs_turns)
    cta, csa = sharp_frames(cons_p, runs_turns)
    psets = [("#69", tb_all[tb_all.persona == "paul"], ta_all[ta_all.persona == "paul"], rb_all[rb_all.persona == "paul"],
              ra_all[ra_all.persona == "paul"]),
             ("sharp", stb[stb.persona == "paul"], sta[sta.persona == "paul"], ssb[ssb.persona == "paul"], ssa[ssa.persona == "paul"]),
             ("consequence", ctb, cta, csb, csa)]
    out["paul_consequence"] = {}
    w("## Added 2026-10-08: Paul's level 5 needs a consequence of his own choice or discovery\n")
    w("Paul only. '#69' and 'sharp' as in the section above; 'consequence' = rubric df3c861 (a vivid answer or new fact "
      "is 4; 5 needs the world to react to his own choice or discovery), re-scored on both sides. "
      f"Unsure = confidence < {MAIN}. Deltas: post-rework minus baseline, bootstrap 95% CI over runs (seed + 3).\n")
    rows, drows, brows = [], [], []
    for rub, tb_, ta_, rb_, ra_ in psets:
        P = out["paul_consequence"][rub] = {}
        for lab, t, r in (("base", tb_, rb_), ("post", ta_, ra_)):
            m = matrix(t.score, t.conf, MAIN)
            P[lab] = dict(n=len(t), plain=float(t.score.mean()), weighted=wmean(t.score, t.conf), unsure=m["unsure_share"],
                          hi=m["hi"], lo=m["lo"], mid=m["mid"], un=m["unsure"],
                          session_weighted=wmean(r.session_score, r.session_conf),
                          session_unsure=float((r.session_conf < MAIN).mean()))
            brows.append(dict(rub=rub, ds=lab, n=len(t), hi=f"{m['hi']} ({pc(m['hi']/m['n'])})",
                              lo=f"{m['lo']} ({pc(m['lo']/m['n'])})", mid=f"{m['mid']} ({pc(m['mid']/m['n'])})",
                              un=f"{m['unsure']} ({pc(m['unsure_share'])})"))
        A, B = wruns(ta_), wruns(tb_)
        dw = boot_delta(A, B, wstat, rng4); du = boot_delta(A, B, ustat, rng4)
        sa = pd.DataFrame(dict(sw=ra_.session_score.values * ra_.session_conf.values, w=ra_.session_conf.values))
        sb = pd.DataFrame(dict(sw=rb_.session_score.values * rb_.session_conf.values, w=rb_.session_conf.values))
        ds = boot_delta(sa, sb, wstat, rng4)
        P["delta"] = dict(weighted=dict(zip(("d", "lo", "hi"), dw[:3])), unsure=dict(zip(("d", "lo", "hi"), du[:3])),
                          session_weighted=dict(zip(("d", "lo", "hi"), ds[:3])))
        b, a = P["base"], P["post"]
        rows.append(dict(rub=rub, ub=pc(b["unsure"]), ua=pc(a["unsure"]), wb=f2(b["weighted"]), wa=f2(a["weighted"]),
                         pb=f2(b["plain"]), pa=f2(a["plain"]), sb=f2(b["session_weighted"]), sa=f2(a["session_weighted"])))
        drows.append(dict(rub=rub, dw=f"{sg(dw[0])} ({ci(dw[1], dw[2])})", du=f"{pp(du[0])} pp ({ci(du[1], du[2], True)})",
                          ds=f"{sg(ds[0])} ({ci(ds[1], ds[2])})"))
    w("### Per dataset (turns; sessions in the last two columns)\n")
    w(table(rows, ["rub", "ub", "ua", "wb", "wa", "pb", "pa", "sb", "sa"],
            ["Rubric", "Unsure base", "Unsure post", "**Weighted base**", "**Weighted post**", "Plain base", "Plain post",
             "Session weighted base", "Session weighted post"]))
    w("### Deltas, post-rework minus baseline\n")
    w(table(drows, ["rub", "dw", "du", "ds"], ["Rubric", "**Turn weighted Δ**", "Unsure share Δ", "Session weighted Δ"]))
    w(f"### Breakdown at {MAIN} (turns)\n")
    w(table(brows, ["rub", "ds", "n", "hi", "lo", "mid", "un"],
            ["Rubric", "Dataset", "Turns", "Confident-high", "Confident-low", "Confident-middle", "Unsure"]))
    w("### Most likely level and mean level probabilities (Jev's turn vectors, levels 1–5)\n")
    rows = []
    for rub, fb, fp in (("sharp", sharp_b, sharp_p), ("consequence", cons_b, cons_p)):
        for lab, f in (("base", fb), ("post", fp)):
            X = probs_frame(f)
            if rub == "sharp":
                X = np.array([x for x, r in zip(X, [r for r in json.load(open(f)) for _ in r["turn_conf"]]) if r["persona"] == "paul"])
            am = np.bincount(X[:, 1:].argmax(1), minlength=5)
            sure, uns = X[X[:, 0] >= MAIN, 1:], X[X[:, 0] < MAIN, 1:]
            fmt = lambda Y: " / ".join("%.2f" % v for v in Y.mean(0)) if len(Y) else "—"
            out["paul_consequence"].setdefault("probs", {})[f"{rub}/{lab}"] = dict(
                argmax=am.tolist(), sure_mean=sure.mean(0).tolist() if len(sure) else None,
                unsure_mean=uns.mean(0).tolist() if len(uns) else None)
            rows.append(dict(rub=rub, ds=lab, am=" / ".join(str(v) for v in am), su=fmt(sure), un=fmt(uns)))
    w(table(rows, ["rub", "ds", "am", "su", "un"],
            ["Rubric", "Dataset", "Most likely level 1/2/3/4/5 (turns)", "Mean p, sure turns", "Mean p, unsure turns"]))
    cost = sum(r["usage"]["cost"] for f in (cons_b, cons_p) for r in json.load(open(f)) if r.get("usage"))
    w(f"Consequence re-score: {len(csb)} + {len(csa)} Paul runs, Jev cost ${cost:.4f} (Jev's own usage figure).\n")

if jout:
    def clean(o):
        if isinstance(o, dict): return {k: clean(v) for k, v in o.items()}
        if isinstance(o, (np.floating, float)): return None if np.isnan(o) else round(float(o), 4)
        if isinstance(o, (np.integer,)): return int(o)
        if isinstance(o, (np.bool_,)): return bool(o)
        return o
    json.dump(clean(out), open(jout, "w"), indent=1)
