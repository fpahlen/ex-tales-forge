#!/usr/bin/env python3
"""Off vs on analysis for INTENT_CALL_EVERY_TURN. Usage: analyze.py intent_export.json > out.md"""
import json, sys, re, math, random
from datetime import datetime
import numpy as np
from scipy import stats

data = json.load(open(sys.argv[1]))
STOP = set("the a an and or of to in on at for with your you his her their it its is was are be as by from that this into but not no so if then than there here i me my we our he she they them what do does did have has had just about can will would could i'm it's".split())
def ts(s): return datetime.fromisoformat(s.replace("Z", "+00:00"))
def arm(r): return "on" if "intent-on" in r["run"]["notes"] else "off"
def ci_t(xs):
    xs = [x for x in xs if x is not None]
    n = len(xs)
    if n == 0: return (float("nan"),)*3 + (0,)
    m = float(np.mean(xs))
    if n < 2: return m, float("nan"), float("nan"), n
    h = stats.t.ppf(0.975, n-1) * np.std(xs, ddof=1) / math.sqrt(n)
    return m, m-h, m+h, n
def boot_diff(a, b, B=10000, seed=1):
    rng = np.random.default_rng(seed); a = np.array(a); b = np.array(b)
    d = [rng.choice(b, len(b)).mean() - rng.choice(a, len(a)).mean() for _ in range(B)]
    return float(b.mean()-a.mean()), float(np.percentile(d, 2.5)), float(np.percentile(d, 97.5))
def wilson(k, n):
    if n == 0: return (float("nan"),)*2
    z = 1.96; p = k/n; d = 1+z*z/n; c = p+z*z/(2*n); h = z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))
    return (c-h)/d, (c+h)/d
def words(t): return {w for w in re.findall(r"[a-z']+", (t or "").lower()) if len(w) > 3 and w not in STOP}

rows = []   # per run
trows = []  # per turn
for r in data:
    run = r["run"]; a = arm(r); p = run["persona"]
    sess = [s for s in r["scores"] if s["kind"] == "session_affect"]
    sess_primary = [s for s in sess if s["source"] in ("primary", "jev", None)] or sess
    tsc = [s for s in r["scores"] if s["kind"] == "turn_affect"]
    srcs = sorted({s["source"] for s in tsc})
    prim = srcs[0] if srcs else None
    if "primary" in srcs: prim = "primary"
    tsc = [s for s in tsc if s["source"] == prim]
    tscore = {s["turn_number"]: s["overall"] for s in tsc}
    tconf = {s["turn_number"]: s["confidence"] for s in tsc}
    calls = r["calls"]
    persona_c = sum(c["cost_micro_usd"] or 0 for c in calls if c["purpose"] == "persona")
    scorer_c = sum(c["cost_micro_usd"] or 0 for c in calls if c["purpose"] == "scorer")
    game_c = sum(c["cost_micro_usd"] or 0 for c in calls if c["purpose"] not in ("persona", "scorer"))
    intent_llm_c = sum(c["cost_micro_usd"] or 0 for c in calls if c["purpose"] not in ("persona", "scorer") and c["call_type"] == "llm" and "intent" in c["purpose"])
    byturn = {}
    for c in calls: byturn.setdefault(c["turn_number"], []).append(c)
    turns = {t["n"]: t for t in r["turns"]}
    for n, t in sorted(turns.items()):
        cs = byturn.get(n, [])
        steps_ = [c for c in cs if c["purpose"] == "turn.intent"]
        clar = sum(1 for c in steps_ if c.get("meta") is None)
        step = next((c for c in reversed(steps_) if c.get("meta") is not None), steps_[-1] if steps_ else None)
        pers = next((c for c in cs if c["purpose"] == "turn.persist"), None)
        gm = next((c for c in cs if c["purpose"] == "turn.gm"), None)
        lat = None
        if step and step.get("started_at") and pers and pers.get("started_at"):
            lat = (ts(pers["started_at"]) - ts(step["started_at"])).total_seconds() + (pers["latency_ms"] or 0)/1000
        meta = (step or {}).get("meta") or {}
        first = steps_[0] if steps_ else None
        flat = None
        if first and first.get("started_at") and pers and pers.get("started_at"):
            flat = (ts(pers["started_at"]) - ts(first["started_at"])).total_seconds() + (pers["latency_ms"] or 0)/1000
        api_err = any(c["status"] != "ok" for c in cs)
        trows.append(dict(arm=a, persona=p, run=run["id"][:8], n=n, player=t["player"], gm=t["gm"], lat=lat,
            intent_ms=(step or {}).get("latency_ms"), gm_ms=(gm or {}).get("latency_ms"), llm_intent=bool(meta) and not str(meta.get("reason")).startswith("no_intent_call"), clar=clar, flat=flat, api_err=api_err, conf_turn=tconf.get(n),
            used=meta.get("used"), reason=meta.get("reason"), label=meta.get("label"), conf=meta.get("confidence"),
            score=tscore.get(n), overlap=len(words(t["player"]) & words(t["gm"])) / max(1, len(words(t["player"])))))
    rows.append(dict(arm=a, persona=p, run=run["id"][:8], status=run["status"], stop=run["stop_reason"], turns=run["turns_played"],
        limit=run["turn_limit"], sha=(run.get("git_sha") or "")[:7], session=(sess_primary[0]["overall"] if sess_primary else None),
        rubric=(sess_primary[0]["rubric_version"] if sess_primary else None),
        turn_mean=(float(np.mean(list(tscore.values()))) if tscore else None),
        turn_wmean=(sum(tscore[k]*(tconf[k] or 0) for k in tscore)/sum((tconf[k] or 0) for k in tscore) if tscore and sum((tconf[k] or 0) for k in tscore) > 0 else None),
        unsure=(sum(1 for k in tscore if (tconf[k] or 0) < 0.7)/len(tscore) if tscore else None),
        sess_conf=(sess_primary[0]["confidence"] if sess_primary else None),
        clar=sum(1 for c in calls if c["purpose"] == "turn.intent" and c.get("meta") is None),
        persona_calls=run.get("persona_calls"), game=game_c/1e6, persona_usd=persona_c/1e6,
        scorer=scorer_c/1e6, intent_llm=intent_llm_c/1e6, persona_reported=(run.get("persona_cost_micro_usd") or 0)/1e6))

json.dump(dict(runs=rows, turns=trows), open("rows.json", "w"), default=str)
P = ["paul", "lotta", "lars", "ronny", "hawk"]
def f(x, d=2): return "–" if x is None or (isinstance(x, float) and math.isnan(x)) else f"{x:.{d}f}"
print("## Runs\n\n| arm | persona | run | sha | status/stop | turns | session | turn mean | game $ | persona $ | Jev scorer $ |\n|---|---|---|---|---|---|---|---|---|---|---|")
for x in sorted(rows, key=lambda x: (x["arm"] != "off", P.index(x["persona"]) if x["persona"] in P else 9)):
    print(f"| {x['arm']} | {x['persona']} | {x['run']} | {x['sha']} | {x['status']}/{x['stop']} | {x['turns']}/{x['limit']} | {f(x['session'])} | {f(x['turn_mean'])} | {x['game']:.4f} | {x['persona_usd']:.4f} | {x['scorer']:.4f} |")
done = [x for x in rows if x["stop"] in ("turn_limit", "dead")]
print("\n## Jev per persona (finished runs; 95% t-CI over runs)\n\n| persona | off session (n) | on session (n) | off turn mean | on turn mean |\n|---|---|---|---|---|")
for p in P + ["all but ronny"]:
    sel = lambda a: [x for x in done if x["arm"] == a and (x["persona"] == p or (p == "all but ronny" and x["persona"] != "ronny"))]
    o = ci_t([x["session"] for x in sel("off")]); n_ = ci_t([x["session"] for x in sel("on")])
    ot = ci_t([x["turn_mean"] for x in sel("off")]); nt = ci_t([x["turn_mean"] for x in sel("on")])
    print(f"| {p} | {f(o[0])} [{f(o[1])}, {f(o[2])}] ({o[3]}) | {f(n_[0])} [{f(n_[1])}, {f(n_[2])}] ({n_[3]}) | {f(ot[0])} [{f(ot[1])}, {f(ot[2])}] | {f(nt[0])} [{f(nt[1])}, {f(nt[2])}] |")
# persona-centred difference (removes persona effect): subtract persona mean over both arms
def centred(key):
    out = {"off": [], "on": []}
    for p in P:
        if p == "ronny": continue
        xs = [x for x in done if x["persona"] == p and x[key] is not None]
        if not xs: continue
        m = np.mean([x[key] for x in xs])
        for x in xs: out[x["arm"]].append(x[key] - m)
    return out
print("\n## Jev confidence-weighted turn reading (sum(score*conf)/sum(conf)) and unsure share (turn conf < 0.7)\n\n| persona | off weighted | on weighted | off unsure | on unsure |\n|---|---|---|---|---|")
for p in P + ["all but ronny"]:
    sel = lambda a: [x for x in done if x["arm"] == a and (x["persona"] == p or (p == "all but ronny" and x["persona"] != "ronny"))]
    w = {a: ci_t([x["turn_wmean"] for x in sel(a)]) for a in ("off", "on")}
    u = {a: [x["unsure"] for x in sel(a) if x["unsure"] is not None] for a in ("off", "on")}
    print(f"| {p} | {f(w['off'][0])} [{f(w['off'][1])}, {f(w['off'][2])}] | {f(w['on'][0])} [{f(w['on'][1])}, {f(w['on'][2])}] | {f(100*np.mean(u['off']) if u['off'] else None,0)}% | {f(100*np.mean(u['on']) if u['on'] else None,0)}% |")
for key in ("session", "turn_mean", "turn_wmean"):
    c = centred(key)
    if c["off"] and c["on"]:
        d = boot_diff(c["off"], c["on"]); print(f"\nOn − off, {key}, persona-centred, no Ronny: {d[0]:+.2f} (bootstrap 95% CI {d[1]:+.2f} to {d[2]:+.2f}; n={len(c['off'])}/{len(c['on'])})")
print("\n## Safety read and GM input (turn.intent meta)\n")
for a in ("off", "on"):
    T = [t for t in trows if t["arm"] == a]
    llm = [t for t in T if t["label"] is not None]
    from collections import Counter
    print(f"**{a}**: turns {len(T)}; turns with LLM intent call {sum(t['llm_intent'] for t in T)}; with a safety read {len(llm)}; "
          f"GM got quote {sum(t['used']=='quote' for t in T)}, summary {sum(t['used']=='summary' for t in T)}, no meta {sum(t['used'] is None for t in T)}")
    print(f"  clarification requests (turn.intent without a decision): {sum(t['clar'] for t in T)} over {len(set(t['run'] for t in T))} runs")
    print(f"  labels {dict(Counter(t['label'] for t in llm))}; reasons {dict(Counter(t['reason'] for t in T))}")
    nr = [t for t in llm if t["persona"] != "ronny"]
    fp = [t for t in nr if t["used"] != "quote"]
    lo, hi = wilson(len(fp), len(nr))
    print(f"  non-Ronny safety reads {len(nr)}; not quoted {len(fp)} ({100*len(fp)/max(1,len(nr)):.1f}%, Wilson 95% {100*lo:.1f}–{100*hi:.1f}%)")
    rr = [t for t in llm if t["persona"] == "ronny"]
    print(f"  Ronny safety reads {len(rr)}; not quoted {sum(t['used']!='quote' for t in rr)}; labels {dict(Counter(t['label'] for t in rr))}")
    cs = [t["conf"] for t in llm if isinstance(t["conf"], (int, float))]
    if cs: print(f"  confidence: min {min(cs):.2f}, p10 {np.percentile(cs,10):.2f}, median {np.median(cs):.2f}; < 0.90: {sum(c<0.9 for c in cs)}")
print("\n## Latency per turn (intent step start → turn persisted), seconds\n\n| arm | persona | n | median | p90 | intent step median | GM call median |\n|---|---|---|---|---|---|---|")
for a in ("off", "on"):
    for p in P + ["all"]:
        T = [t for t in trows if t["arm"] == a and (p == "all" or t["persona"] == p) and t["lat"] is not None]
        if not T: continue
        L = [t["lat"] for t in T]; I = [t["intent_ms"]/1000 for t in T if t["intent_ms"] is not None]; G = [t["gm_ms"]/1000 for t in T if t["gm_ms"]]
        print(f"| {a} | {p} | {len(T)} | {np.median(L):.1f} | {np.percentile(L,90):.1f} | {np.median(I):.2f} | {np.median(G) if G else float('nan'):.1f} |")
print("\n## Clarification loops (intent call asked the player to pick an option)\n\n| arm | persona | turns | clarification requests | per turn | turns with ≥1 | extra persona calls |\n|---|---|---|---|---|---|---|")
for a in ("off", "on"):
    for p in P + ["all"]:
        T = [t for t in trows if t["arm"] == a and (p == "all" or t["persona"] == p)]
        R = [x for x in rows if x["arm"] == a and (p == "all" or x["persona"] == p)]
        if not T: continue
        k = sum(t["clar"] for t in T); w1 = sum(1 for t in T if t["clar"] > 0)
        print(f"| {a} | {p} | {len(T)} | {k} | {k/len(T):.2f} | {w1} ({100*w1/len(T):.0f}%) | {sum((x['persona_calls'] or 0) - x['turns'] for x in R)} |")
print("\n## Wall time from the player's first submission to the GM reply (includes clarification rounds and the persona's answers), seconds\n\n| arm | persona | n | median | p90 | max |\n|---|---|---|---|---|---|")
for a in ("off", "on"):
    for p in P + ["all"]:
        L = [t["flat"] for t in trows if t["arm"] == a and (p == "all" or t["persona"] == p) and t["flat"] is not None]
        if L: print(f"| {a} | {p} | {len(L)} | {np.median(L):.1f} | {np.percentile(L,90):.1f} | {max(L):.1f} |")
for a in ("off", "on"):
    L = [t["lat"] for t in trows if t["arm"] == a and t["lat"] is not None and not t["api_err"] and t["clar"] == 0]
    if L: print(f"\n{a}: turns without API errors or clarification: n={len(L)}, median {np.median(L):.1f} s, p90 {np.percentile(L,90):.1f} s")
offL = [t["lat"] for t in trows if t["arm"] == "off" and t["lat"]]; onL = [t["lat"] for t in trows if t["arm"] == "on" and t["lat"]]
if offL and onL:
    rng = np.random.default_rng(2); B = [np.median(rng.choice(onL, len(onL))) - np.median(rng.choice(offL, len(offL))) for _ in range(5000)]
    print(f"\nMedian latency on − off: {np.median(onL)-np.median(offL):+.2f} s (bootstrap 95% CI {np.percentile(B,2.5):+.2f} to {np.percentile(B,97.5):+.2f}); turn-level, ignores clustering by run.")
print("\n## Cost per finished run (USD)\n\n| arm | n | game mean [95% CI] | of which LLM intent | persona mean | Jev scorer mean | game per turn |\n|---|---|---|---|---|---|---|")
for a in ("off", "on"):
    X = [x for x in done if x["arm"] == a]
    if not X: continue
    g = ci_t([x["game"] for x in X])
    print(f"| {a} | {len(X)} | {g[0]:.4f} [{g[1]:.4f}, {g[2]:.4f}] | {np.mean([x['intent_llm'] for x in X]):.4f} | {np.mean([x['persona_usd'] for x in X]):.4f} | {np.mean([x['scorer'] for x in X]):.5f} | {sum(x['game'] for x in X)/sum(x['turns'] for x in X):.4f} |")
print(f"\nTotals, all runs incl. stopped: game ${sum(x['game'] for x in rows):.4f}, persona ${sum(x['persona_usd'] for x in rows):.4f}, Jev scorer ${sum(x['scorer'] for x in rows):.4f}")
print("\n## Engagement proxy: share of the player's content words echoed in the GM reply\n\n| arm | persona | turns | mean overlap | quoted turns overlap | summary turns overlap |\n|---|---|---|---|---|---|")
for a in ("off", "on"):
    for p in P + ["all"]:
        T = [t for t in trows if t["arm"] == a and (p == "all" or t["persona"] == p)]
        if not T: continue
        q = [t["overlap"] for t in T if t["used"] == "quote"]; s = [t["overlap"] for t in T if t["used"] == "summary"]
        print(f"| {a} | {p} | {len(T)} | {np.mean([t['overlap'] for t in T]):.2f} | {f(np.mean(q)) if q else '–'} ({len(q)}) | {f(np.mean(s)) if s else '–'} ({len(s)}) |")
