#!/usr/bin/env python3
"""Extra numbers for the 2026-10-07 baseline write-up (docs/analysis-jev-baseline-2026-10-07.md).

Reads the CSVs that compare.py writes (--csv DIR) plus the export JSON, and prints Markdown:
per-persona session means with bootstrap CIs, Hawk/Ronny against the Elara runs re-scored with
today's rubric, story location (does the run leave the inn?), persona-bot repetition, GM
verbatim echo, turn trends, the runs-per-arm estimate, recurring GM phrases, LP growth,
Hawk with and without a fight, cost totals and the run conditions (SHA, flags).

Usage: python3 baseline_extra.py DIR export.json [SERIES]
Read-only. Heuristics are regexes; read the turns before quoting them.
"""
import json, re, sys
import numpy as np, pandas as pd
from scipy import stats

D, EXPORT = sys.argv[1], sys.argv[2]
SERIES = sys.argv[3] if len(sys.argv) > 3 else "baseline-2026-10-07"
R, T = pd.read_csv(f"{D}/runs.csv"), pd.read_csv(f"{D}/turns.csv")
B = R[R.cohort.str.startswith(SERIES)]; BT = T[T.cohort.str.startswith(SERIES)]
E = R[R.cohort == "elara"]; ET = T[T.cohort == "elara"]
rng = np.random.default_rng(7)
def ci(a, n=5000):
    a = np.asarray(a, float)
    if len(a) < 2: return "—"
    m = [rng.choice(a, len(a)).mean() for _ in range(n)]
    return "%.2f…%.2f" % tuple(np.percentile(m, [2.5, 97.5]))
def md(df, f=2): return df.round(f).to_markdown()
w = print

w("### A. Session score per persona (series), bootstrap 95% CI of the mean\n")
rows = []
for p, g in B.groupby("persona"):
    t = BT[BT.persona == p]
    rows.append(dict(persona=p, runs=len(g), session=g.session_score.mean(), ci95=ci(g.session_score), sd=g.session_score.std(),
                     min=g.session_score.min(), max=g.session_score.max(), session_conf=g.session_conf.mean(),
                     turn_mean=t.score.mean(), turn_conf=t.conf.mean(), turns_conf_lt_03=(t.conf < 0.3).sum(), turns=len(t)))
w(md(pd.DataFrame(rows).set_index("persona")))

w("\n### B. Session score vs mean turn score (series)\n")
mt = BT.groupby("run_id").score.mean()
j = B.set_index("run_id").join(mt.rename("mean_turn"))
rho, p = stats.spearmanr(j.session_score, j.mean_turn)
w(f"Spearman {rho:.2f} (p={p:.3g}, n={len(j)}), mean session − mean turn {(j.session_score - j.mean_turn).mean():+.2f}.")

w("\n### C. Hawk and Ronny against the Elara runs re-scored with today's rubric\n")
def resc(x):
    try: return json.loads(x.replace("'", '"'))["overall"]
    except Exception: return np.nan
E2 = E.assign(new=E.rescore.dropna().map(resc) if "rescore" in E else np.nan)
for p in ["hawk", "ronny"]:
    a = B[B.persona == p].session_score; ref = E2[(E2.persona == p)].new.dropna()
    w(f"- {p}: series {a.mean():.2f} (n={len(a)}, CI {ci(a)}); Elara re-scored {', '.join('%.2f' % v for v in ref)} (n={len(ref)}).")

w("\n### D. Where the story is (series; regex on GM text)\n")
INN = r"brenna|the bar\b|counter|hearth|common room|valley inn"
LEAVE = r"\b(head (out|to|for|toward)|leave the inn|set out|step (outside|out|into the square)|make (my|our) way|go to the|walk to|out the door|to(ward)? the square|seek (out )?osric|find osric)\b"
X = [x for x in json.load(open(EXPORT)) if f"series={SERIES} " in (x["run"].get("notes") or "")]
rows = []
for x in X:
    ts = x["turns"]
    if not ts: continue
    inn = [bool(re.search(INN, (t["gm"] or "").lower())) for t in ts]
    tries = [t["n"] for t in ts if re.search(LEAVE, (t["player"] or "").lower())]
    stuck = [n for n in tries if n + 1 <= len(ts) and inn[min(n, len(ts) - 1)]]
    rows.append(dict(persona=x["run"]["persona"], turns=len(ts), inn_share=np.mean(inn), last_turn_in_inn=inn[-1],
                     leave_tries=len(tries), still_in_inn_after_try=len(stuck)))
L = pd.DataFrame(rows)
w(md(L.groupby("persona").agg(runs=("turns", "size"), inn_share=("inn_share", "mean"), last_turn_in_inn=("last_turn_in_inn", "mean"),
                              runs_with_leave_try=("leave_tries", lambda s: (s > 0).sum()),
                              leave_tries=("leave_tries", "sum"),
                              tries_followed_by_inn_turn=("still_in_inn_after_try", "sum"))))
w(f"\nAll: {L.last_turn_in_inn.mean():.0%} of runs end with the GM still describing the inn/Brenna; "
  f"{(L.leave_tries > 0).mean():.0%} of runs have the player try to leave at least once.")

w("\n### E. Repetition: persona bot repeating itself, GM quoting the player\n")
def ng(s, n): ws = re.findall(r"[a-z']+", (s or "").lower()); return set(tuple(ws[i:i + n]) for i in range(len(ws) - n + 1))
rows = []
for x in X:
    ts = x["turns"]; prev = None
    for t in ts:
        p3 = ng(t["player"], 3)
        rep = len(p3 & prev) / max(1, len(p3)) if prev is not None else np.nan
        quote = bool(ng(t["player"], 8) & ng(t["gm"], 8))
        rows.append(dict(persona=x["run"]["persona"], player_repeat=rep, gm_quotes_player_8gram=quote))
        prev = p3
P = pd.DataFrame(rows)
w(md(P.groupby("persona").agg(player_repeat_vs_prev_turn=("player_repeat", "mean"), gm_quotes_player_8gram=("gm_quotes_player_8gram", "mean")), 3))

w("\n### F. Turn trend within run (series), Spearman of turn index vs score / within-run score / confidence, per persona\n")
rows = []
for p, g in BT.groupby("persona"):
    for tgt in ["score", "dm", "conf"]:
        r_, pv = stats.spearmanr(g.turn, g[tgt]); rows.append(dict(persona=p, target=tgt, rho=r_, p=pv, n=len(g)))
w(md(pd.DataFrame(rows).pivot(index="persona", columns="target", values=["rho", "p"]), 3))

w("\n### G. Runs per arm for an A/B (two-sided α=0.05, 80% power), from the series' between-run SD\n")
for p, g in B.groupby("persona"):
    sd = g.session_score.std()
    if not sd or np.isnan(sd): continue
    if sd < 0.15:
        w(f"- {p}: SD {sd:.2f}: scores sit on one level (ceiling); a runs-per-arm figure would be meaningless"); continue
    n = lambda d: int(np.ceil(2 * ((1.96 + 0.84) * sd / d) ** 2))
    w(f"- {p}: SD {sd:.2f} → Δ0.3: {n(0.3)} runs/arm, Δ0.5: {n(0.5)} runs/arm")

w("\n### H. Recurring GM phrases (series): 4-grams in the most runs\n")
STOPW = set("the a an and of to in on at your you her his it is with as for from that".split())
cnt = {}
for x in X:
    seen = set()
    for t in x["turns"]:
        for g in ng(t["gm"], 4):
            if sum(w_ in STOPW for w_ in g) <= 2: seen.add(g)
    for g in seen: cnt[g] = cnt.get(g, 0) + 1
top = sorted(cnt.items(), key=lambda kv: -kv[1])[:20]
w(", ".join(f"\"{' '.join(g)}\" {n}" for g, n in top) + f" (of {len(X)} runs)")

w("\n### I. LP growth per run (series; playtest_runs.growth, ex-tales-forge #66)\n")
rows = []
for x in X:
    gr = x["run"].get("growth") or {}; sk = gr.get("skills") or {}
    rows.append(dict(persona=x["run"]["persona"], turns=len(x["turns"]), rolls=gr.get("rolls", 0), lp=gr.get("lp_gained", 0.0),
                     top_skill_lp=max([v.get("lp_gained", 0) for v in sk.values()] or [0]), skills=len(sk),
                     attempts=gr.get("attempts", 0), improvements=gr.get("improvements", 0)))
G = pd.DataFrame(rows)
gg = G.groupby("persona").agg(runs=("lp", "size"), rolls=("rolls", "mean"), lp=("lp", "mean"), lp_sd=("lp", "std"),
                              top_skill_lp=("top_skill_lp", "mean"), runs_with_roll=("rolls", lambda s: (s > 0).sum()),
                              runs_skill_ge5=("top_skill_lp", lambda s: (s >= 5).sum()), attempts=("attempts", "sum"),
                              improvements=("improvements", "sum"))
gg["runs_to_5lp_top_skill"] = (5 / gg.top_skill_lp).replace([np.inf], np.nan)
w(md(gg))
w(f"\nAll: {G.lp.mean():.2f} LP/run (CI {ci(G.lp)}), {G.rolls.mean():.2f} rolls/run, {(G.rolls > 0).mean():.0%} of runs roll at least once, "
  f"{(G.top_skill_lp >= 5).sum()} runs bring one skill to the 5-LP Novice threshold, {G.attempts.sum()} improvement attempts, {G.improvements.sum()} improvements.")

w("\n### J. Hawk: session score with and without a combat roll\n")
hk = []
for x in X:
    if x["run"]["persona"] != "hawk": continue
    sk = ((x["run"].get("growth") or {}).get("skills") or {})
    fight = any(k in sk for k in ("melee_combat", "ranged_combat", "unarmed_combat", "dodge"))
    s0 = sorted([s for s in x["scores"] if s["source"] == "jev" and s["kind"] == "session_affect"], key=lambda s: s["inserted_at"])
    if s0: hk.append(dict(run=x["run"]["id"][:8], fight=fight, rolls=(x["run"].get("growth") or {}).get("rolls", 0), session=s0[0]["overall"], conf=s0[0]["confidence"]))
H = pd.DataFrame(hk)
if len(H):
    w(md(H.groupby("fight").agg(runs=("session", "size"), session=("session", "mean"), min=("session", "min"), max=("session", "max"), conf=("conf", "mean"))))
    w("\n" + ", ".join(f"{r.run} {'fight' if r.fight else 'no fight'} {r.session:.2f}" for r in H.sort_values("session").itertuples()))

w("\n### K. Cost (series, USD)\n")
c = B[["game_usd", "persona_usd", "jev_usd"]]
w(md(pd.DataFrame({"per_run_mean": c.mean(), "total": c.sum()}).T.assign(all=lambda d: d.sum(axis=1)), 4))
w(f"\nRuns: {len(B)}; per turn: game ${B.game_usd.sum() / BT.groupby('run_id').size().sum():.4f}.")

w("\n### L. Run conditions (series)\n")
w("git SHA: " + ", ".join(sorted({x["run"].get("git_sha") or "?" for x in X})) + "; build: " + ", ".join(sorted({x["run"].get("build") or "?" for x in X})))
fl = {}
for x in X:
    for k, v in (x["run"].get("flags") or {}).items(): fl.setdefault(k, set()).add(str(v))
w("\nFlags: " + "; ".join(f"{k}={'/'.join(sorted(v))}" for k, v in sorted(fl.items())))
w("\nCharacters: " + ", ".join(sorted({f"{x['run']['persona']}: {(x.get('character') or {}).get('name')} ({(x.get('character') or {}).get('race')} {(x.get('character') or {}).get('class')})" for x in X})))
w("\nWindow (UTC): " + min(x["run"]["started_at"] for x in X) + " … " + max((x["run"].get("finished_at") or "") for x in X))
w("\nStatus/stop: " + ", ".join(f"{k} {v}" for k, v in pd.Series([f"{x['run']['status']}/{x['run']['stop_reason']}" for x in X]).value_counts().items()))

w("\n### M. Versus Elara, persona-balanced (Paul and Lotta only: the personas with ≥5 Elara runs)\n")
w("The pooled 'all (no Ronny)' row in compare.py mixes personas in different proportions (Hawk is 25% of the series but 5% of the Elara runs), so it is confounded. Here each persona's difference is taken first, then averaged with equal weight; CIs bootstrap runs within persona.\n")
rows = []
for what, Rs, Re in [("session", B, E), ("turns 1-5 (per-run mean)",
                      BT[BT.turn <= 5].groupby(["run_id", "persona"]).score.mean().rename("session_score").reset_index(),
                      ET[ET.turn <= 5].groupby(["run_id", "persona"]).score.mean().rename("session_score").reset_index())]:
    ds, boots = [], []
    for p in ["paul", "lotta"]:
        a = Rs[Rs.persona == p].session_score.to_numpy(); b = Re[Re.persona == p].session_score.to_numpy()
        ds.append(a.mean() - b.mean())
        boots.append([rng.choice(a, len(a)).mean() - rng.choice(b, len(b)).mean() for _ in range(5000)])
    bm = np.mean(boots, axis=0)
    rows.append(dict(measure=what, paul=ds[0], lotta=ds[1], balanced=np.mean(ds), ci95="%+.2f…%+.2f" % tuple(np.percentile(bm, [2.5, 97.5]))))
w(md(pd.DataFrame(rows).set_index("measure")))
