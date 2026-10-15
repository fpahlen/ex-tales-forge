#!/usr/bin/env python3
"""Post-rework series vs the 2026-10-07 baseline (docs/analysis-jev-post-rework-2026-10-08.md).

Reads the CSVs that compare.py writes (run it with --reference baseline-2026-10-07/default and
--rescore so Paul and Lotta use the new rubric on both sides) plus the export JSON (export.exs with
scenes, events and fronts), and prints Markdown: per-persona deltas with bootstrap CIs (session,
turn mean, turns 1-5 per run), leaving the inn, echo and banned tics, Hawk and the Tinjacks,
places and people reached, rolls, skill growth, cost and run conditions.

Usage: python3 post_rework.py DIR export.json [NEW_SERIES] [BASE_SERIES]
Read-only. Text features are regexes; read the turns before quoting them.
"""
import json, re, sys
from collections import Counter
import numpy as np, pandas as pd

D, EXPORT = sys.argv[1], sys.argv[2]
NEW = sys.argv[3] if len(sys.argv) > 3 else "post-rework-2026-10-08"
BASE = sys.argv[4] if len(sys.argv) > 4 else "baseline-2026-10-07"
R, T = pd.read_csv(f"{D}/runs.csv"), pd.read_csv(f"{D}/turns.csv")
coh = lambda s: R.cohort.str.startswith(s)
PERS = ["paul", "lotta", "lars", "hawk", "ronny"]
rng = np.random.default_rng(7)
w = print
def md(df, f=2): return df.round(f).to_markdown()
def mci(a, n=5000):
    a = np.asarray(a, float)
    if len(a) < 2: return "—"
    return "%.2f…%.2f" % tuple(np.percentile([rng.choice(a, len(a)).mean() for _ in range(n)], [2.5, 97.5]))
def dci(a, b, n=5000):
    a, b = np.asarray(a, float), np.asarray(b, float)
    if len(a) < 2 or len(b) < 2: return "—"
    d = [rng.choice(a, len(a)).mean() - rng.choice(b, len(b)).mean() for _ in range(n)]
    return "%+.2f…%+.2f" % tuple(np.percentile(d, [2.5, 97.5]))
X = json.load(open(EXPORT))
def series(x): m = re.search(r"series=(\S+) ", (x["run"].get("notes") or "") + " "); return m and m.group(1)
XS = {s: [x for x in X if series(x) == s and x["turns"]] for s in (BASE, NEW)}
def first_session(x):
    s = sorted([s for s in x["scores"] if s["source"] == "jev" and s["kind"] == "session_affect"], key=lambda s: s["inserted_at"])
    return s[0] if s else None
sess = R.set_index("run_id").session_score  # re-scored where --rescore applied

w("### A. Scores per persona, new series vs baseline (Paul and Lotta: new rubric on both sides)\n")
rows = []
for p in PERS:
    a, b = R[coh(NEW) & (R.persona == p)], R[coh(BASE) & (R.persona == p)]
    ta, tb = T[T.cohort.str.startswith(NEW) & (T.persona == p)], T[T.cohort.str.startswith(BASE) & (T.persona == p)]
    tma, tmb = ta.groupby("run_id").score.mean(), tb.groupby("run_id").score.mean()
    t5a = ta[ta.turn <= 5].groupby("run_id").score.mean(); t5b = tb[tb.turn <= 5].groupby("run_id").score.mean()
    rows.append(dict(persona=p, n_new=len(a), n_base=len(b), session_new=a.session_score.mean(), session_base=b.session_score.mean(),
                     d_session=a.session_score.mean() - b.session_score.mean(), ci_session=dci(a.session_score, b.session_score),
                     turn_new=tma.mean(), turn_base=tmb.mean(), d_turn=tma.mean() - tmb.mean(), ci_turn=dci(tma, tmb),
                     t1_5_new=t5a.mean(), t1_5_base=t5b.mean(), d_t1_5=t5a.mean() - t5b.mean(), ci_t1_5=dci(t5a, t5b),
                     sd_new=a.session_score.std(), conf_new=a.session_conf.mean()))
w(md(pd.DataFrame(rows).set_index("persona")))
w("\nCIs: bootstrap over runs (5000 resamples). Turn and T1–5 columns use one mean per run.")

w("\n### A2. Turn argmax levels (Paul, Lotta)\n")
for p in ["paul", "lotta"]:
    for s in (BASE, NEW):
        g = T[T.cohort.str.startswith(s) & (T.persona == p)]
        if "probs" in g and g.probs.notna().any() and (g.probs.fillna("") != "").any():
            am = Counter(int(max(json.loads(v).items(), key=lambda kv: kv[1])[0]) + 1 for v in g.probs if isinstance(v, str) and v)
            w(f"- {p} {s}: " + ", ".join(f"{k}: {v}" for k, v in sorted(am.items())) + f" ({sum(am.values())} turns)")

w("\n### B. Leaving the inn\n")
INN = r"brenna|the bar\b|counter|hearth|common room|valley inn"
LEAVE = r"\b(head (out|to|for|toward)|leave the inn|set out|step (outside|out|into the square)|make (my|our) way|go to the|walk to|out the door|to(ward)? the square|seek (out )?osric|find osric)\b"
def turn_locs(x):
    """Recorded location per turn: the latest scene inserted at or before the turn row."""
    sc = sorted(x.get("scenes") or [], key=lambda s: s["at"]); out = {}
    for t in x["turns"]:
        loc = None
        for s in sc:
            if s["at"] <= t["at"][:19] + "Z" or s["at"] <= t["at"]: loc = s["location_id"]
        out[t["n"]] = loc
    return out
rows = []
for s, xs in XS.items():
    for x in xs:
        ts = sorted(x["turns"], key=lambda t: t["n"]); inn = {t["n"]: bool(re.search(INN, (t["gm"] or "").lower())) for t in ts}
        tries = [t["n"] for t in ts if re.search(LEAVE, (t["player"] or "").lower())]
        last = ts[-1]["n"]
        stuck = [n for n in tries if n + 1 <= last and inn[n + 1]]
        locs = turn_locs(x) if s == NEW else {}
        moved = [n for n in tries if locs and locs.get(n) not in (None, "valley_inn")]
        loc_stuck = [n for n in tries if n + 1 <= last and locs and locs.get(n + 1) == "valley_inn"]
        rows.append(dict(series=s, persona=x["run"]["persona"], tries=len(tries), tries_followed=len([n for n in tries if n + 1 <= last]),
                         regex_inn_after=len(stuck), recorded_left_on_try=len(moved), recorded_inn_after=len(loc_stuck),
                         scenes=max(0, len(x.get("scenes") or []) - 1), left_inn=any(v not in (None, "valley_inn") for v in locs.values()),
                         last_inn_regex=inn[last]))
L = pd.DataFrame(rows)
w(md(L.groupby(["series", "persona"]).agg(runs=("tries", "size"), runs_with_try=("tries", lambda s: (s > 0).sum()), tries=("tries", "sum"),
     tries_with_next_turn=("tries_followed", "sum"), inn_regex_next_turn=("regex_inn_after", "sum"),
     recorded_move_on_try=("recorded_left_on_try", "sum"), recorded_inn_next_turn=("recorded_inn_after", "sum"),
     scene_changes=("scenes", "sum"), runs_left_inn=("left_inn", "sum"), last_turn_inn_regex=("last_inn_regex", "mean"))))
for s in (BASE, NEW):
    g = L[L.series == s]
    w(f"\n- {s}: {g.tries.sum()} leave attempts in {(g.tries > 0).sum()}/{len(g)} runs; next GM turn still describes the inn/Brenna "
      f"(regex) after {g.regex_inn_after.sum()} of {g.tries_followed.sum()} ({g.regex_inn_after.sum() / max(1, g.tries_followed.sum()):.0%}); "
      f"runs ending with an inn turn {g.last_inn_regex.mean():.0%}" + (f"; recorded scene changes {g.scenes.sum()}, runs that left the inn {g.left_inn.sum()}; "
      f"recorded location still the inn on the turn after an attempt: {g.recorded_inn_after.sum()} of {g.tries_followed.sum()}" if s == NEW else ""))
if XS[NEW]:
    vis = Counter(); per = {}
    for x in XS[NEW]:
        ids = [sc["location_id"] for sc in (x.get("scenes") or [])]
        for i in set(ids): vis[i] += 1
        per.setdefault(x["run"]["persona"], Counter()).update(set(ids))
    w("\nPlaces with a recorded scene (runs): " + ", ".join(f"{k} {v}" for k, v in vis.most_common()))
    for p in PERS:
        if p in per: w(f"- {p}: " + ", ".join(f"{k} {v}" for k, v in per[p].most_common()))

w("\n### C. Echo and banned tics\n")
def ng(s, n): ws = re.findall(r"[a-z']+", (s or "").lower()); return set(tuple(ws[i:i + n]) for i in range(len(ws) - n + 1))
TICS = {"on the house": r"on the house", "tilts her head": r"tilts? (her|his) head", "tilts her head toward": r"tilts? (her|his) head (toward|towards|to)",
        "wipes her hands": r"wip(es|ing) (her|his) hands", "hands on her apron": r"hands? on (her|his) apron", "leans on the counter": r"lean(s|ing) on the (counter|bar)",
        "a fresh mug of ale": r"fresh mug", "eyes narrow": r"eyes narrow"}
rows = []
for s, xs in XS.items():
    for x in xs:
        for t in x["turns"]:
            low = (t["gm"] or "").lower()
            d = dict(series=s, persona=x["run"]["persona"], run=x["run"]["id"], echo8=bool(ng(t["player"], 8) & ng(t["gm"], 8)))
            for k, p in TICS.items(): d[k] = bool(re.search(p, low))
            rows.append(d)
E = pd.DataFrame(rows)
w(md(E.groupby(["series", "persona"]).echo8.mean().unstack(0), 3))
w("\nShare of turns where the GM repeats an 8-word run of the player's line (baseline method).\n")
for s in (BASE, NEW):
    g = E[E.series == s]; pr = g.groupby("run")[list(TICS)].any()
    w(f"- {s}: echo {g.echo8.mean():.1%} of {len(g)} turns; runs with: " + ", ".join(f"\"{k}\" {pr[k].sum()}/{len(pr)} ({pr[k].mean():.0%})" for k in TICS)
      + "; turns with \"on the house\" " + f"{g['on the house'].mean():.1%}")
cnt = Counter()
STOPW = set("the a an and of to in on at your you her his it is with as for from that".split())
for x in XS[NEW]:
    seen = set()
    for t in x["turns"]:
        for g in ng(t["gm"], 4):
            if sum(w_ in STOPW for w_ in g) <= 2: seen.add(g)
    cnt.update(seen)
w("\nRecurring GM 4-grams (new series, runs): " + ", ".join(f"\"{' '.join(g)}\" {n}" for g, n in cnt.most_common(15)) + f" (of {len(XS[NEW])} runs)")

w("\n### D. Hawk, the Tinjacks and fights\n")
GANG = r"\b(rusk|cobb|pip|tinjacks?)\b"
COMBAT = ("melee_combat", "ranged_combat", "unarmed_combat")
STAGE_FIRED = {"trouble:3": "incident", "trouble:6": "confrontation", "trouble:12": "escalation", "beaten:2": "broken"}
STAGE_FACT = {"tinjacks_watchman": "incident", "tinjacks_toll": "confrontation", "tinjacks_burning": "escalation"}
rows = []
for s, xs in XS.items():
    for x in xs:
        ts = sorted(x["turns"], key=lambda t: t["n"])
        gang = [t["n"] for t in ts if re.search(GANG, (t["gm"] or "").lower())]
        fights = [t for t in ts if (t.get("mech") or {}).get("skill") in COMBAT]
        fr = {f["front_id"]: f for f in (x.get("fronts") or [])}.get("tinjacks")
        rt = (fr or {}).get("runtime_state") or {}
        facts = [f.get("id") for f in rt.get("public_facts") or []]
        # stages_fired (e.g. "trouble:6") when the front records it; else the stage facts still standing
        # (a later stage's fact can replace an earlier one, e.g. the burning replaces the toll)
        fired = rt.get("stages_fired")
        stages = [STAGE_FIRED.get(f, f) for f in fired] if fired is not None else [v for k, v in STAGE_FACT.items() if k in facts]
        # ticks per turn from time.passed events (one per turn, in order) -> turn at which trouble reaches 3 / 6 / 12
        tp = [e for e in (x.get("events") or []) if e["kind"] == "time.passed"]
        cum, at = 0, {}
        for i, e in enumerate(tp, 1):
            cum += int((e.get("payload") or {}).get("delta_ticks") or 1)
            for th in (3, 6, 12):
                if cum >= th and th not in at: at[th] = i
        s0 = first_session(x)
        rows.append(dict(series=s, persona=x["run"]["persona"], run=x["run"]["id"][:8], session=sess.get(x["run"]["id"], s0 and s0["overall"]),
                         gang_first_turn=gang[0] if gang else None, gang_turns=len(gang), fight_rolls=len(fights),
                         fight_success=sum((t["mech"] or {}).get("outcome") in ("success", "critical_success") for t in fights),
                         front=(fr or {}).get("status"), trouble=((rt.get("clocks") or {}).get("trouble") or {}).get("value"),
                         beaten=((rt.get("clocks") or {}).get("beaten") or {}).get("value"), stages=",".join(stages) or "-",
                         t_incident=at.get(3), t_confrontation=at.get(6)))
H = pd.DataFrame(rows)
hn = H[(H.series == NEW)]
if len(hn):
    w(md(hn[hn.persona == "hawk"].set_index("run").drop(columns=["series", "persona"])))
    w("\nAll personas, new series:\n")
    w(md(hn.groupby("persona").agg(runs=("run", "size"), runs_gang_named=("gang_first_turn", lambda s: s.notna().sum()),
         first_mention_turn=("gang_first_turn", "mean"), runs_with_fight_roll=("fight_rolls", lambda s: (s > 0).sum()),
         fight_rolls=("fight_rolls", "sum"), fight_successes=("fight_success", "sum"), runs_confrontation_fired=("stages", lambda s: s.str.contains("confrontation").sum()),
         runs_broken=("front", lambda s: (s == "broken").sum()), trouble_end=("trouble", "mean"))))
w("\nHawk session score with and without a combat roll:\n")
hh = H[H.persona == "hawk"].assign(fight=lambda d: d.fight_rolls > 0)
w(md(hh.groupby(["series", "fight"]).agg(runs=("session", "size"), session=("session", "mean"), min=("session", "min"), max=("session", "max"))))

w("\n### E. People and activities reached (new series; GM text)\n")
# Hilde the smith is matched by "Brask" only: Lotta's character is Hilde Stonebrook.
PEOPLE = {"Brenna": r"\bbrenna\b", "Osric": r"\bosric\b", "Caldern": r"\bcaldern\b", "Tam": r"\btam\b", "Mags": r"\bmags\b",
          "Hilde Brask": r"\bbrask\b", "Maude": r"\bmaude\b", "Rusk": r"\brusk\b", "Cobb": r"\bcobb\b", "Pip": r"\bpip\b"}
ACT = {  # activity type -> (places with a recorded scene, player-text regex)
    "talk": (None, r"\b(ask|tell|say|speak|talk)\b"),
    "trade": (None, r"\b(buy|sell|trade|haggle|barter|purchase|hire)\b"),
    "explore": ({"west_road", "old_adit", "mine_workings", "orc_approach"}, r"\b(explore|search|track|follow the|look for tracks)\b"),
    "sneak": (None, r"\b(sneak|creep|stealth|unseen|unnoticed|slip (out|away|past|round|around))\b"),
    "fight": (None, None), "lore": ({"herb_cottage"}, r"\b(carving|history|legend|old (miners|stories)|lore)\b"),
    "crafts/chores": ({"smithy"}, r"\b(bellows|hammer|forge|muck|harness|chop|haul|sweep|help (her|with))\b"),
    "heal/rest": (None, r"\b(sleep|bed down|take a room|room for the night|heal|salve|stitch|bandage|rest (for|a while|my|here))\b"),
}
rows = []
for s, xs in XS.items():
    for x in xs:
        allgm = " ".join((t["gm"] or "") for t in x["turns"]).lower(); allp = " ".join((t["player"] or "") for t in x["turns"]).lower()
        places = {sc["location_id"] for sc in (x.get("scenes") or [])}
        d = dict(series=s, persona=x["run"]["persona"])
        for k, p in PEOPLE.items(): d[k] = bool(re.search(p, allgm))
        for k, (pl, rx) in ACT.items():
            if k == "fight": d["act:" + k] = any((t.get("mech") or {}).get("skill") in COMBAT for t in x["turns"])
            else: d["act:" + k] = bool((pl and places & pl) or (rx and re.search(rx, allp)))
        rows.append(d)
P = pd.DataFrame(rows)
w("Runs where the GM names each person (share of runs):\n")
w(md(P.groupby(["series", "persona"])[list(PEOPLE)].mean().T, 2))
w("\nActivity types reached (share of runs; places from recorded scenes, else a regex on the player's lines, so approximate):\n")
w(md(P.groupby(["series", "persona"])[[c for c in P if c.startswith("act:")]].mean().T, 2))
w("\nDistinct activity types per run: " + ", ".join(f"{s}: {P[P.series == s][[c for c in P if c.startswith('act:')]].sum(axis=1).mean():.1f}" for s in (BASE, NEW)))

w("\n### F. Rolls and outcomes\n")
TT = T.assign(series=np.where(T.cohort.str.startswith(NEW), NEW, np.where(T.cohort.str.startswith(BASE), BASE, "other")))
TT = TT[TT.series != "other"]
w(md(TT.groupby(["series", "persona"]).agg(turns=("turn", "size"), roll_rate=("checked", "mean"), fail_rate=("failed", "mean")).unstack(0), 3))
w("\n" + md(pd.crosstab(TT.series, TT.outcome.fillna("missing"))))
w("\nRuns with at least one roll: " + ", ".join(f"{s}: {(TT[TT.series == s].groupby('run_id').checked.any()).mean():.0%}" for s in (BASE, NEW)))
w("\nSkills rolled (new series): " + ", ".join(f"{k} {v}" for k, v in TT[(TT.series == NEW) & TT.checked].skill.value_counts().items()))

w("\n### G. Skill growth under the new rule\n")
rows = []
for s, xs in XS.items():
    for x in xs:
        gr = x["run"].get("growth") or {}; sk = gr.get("skills") or {}
        rows.append(dict(series=s, persona=x["run"]["persona"], run=x["run"]["id"][:8], rolls=gr.get("rolls", 0), lp=gr.get("lp_gained", 0.0),
                         attempts=gr.get("attempts", 0), improvements=gr.get("improvements", 0),
                         top_skill_impr=max([v.get("improvements", 0) for v in sk.values()] or [0]),
                         top_skill=max(sk.items(), key=lambda kv: kv[1].get("improvements", 0))[0] if sk else None))
G = pd.DataFrame(rows)
w(md(G.groupby(["series", "persona"]).agg(runs=("lp", "size"), lp=("lp", "mean"), lp_max=("lp", "max"), attempts=("attempts", "mean"),
     improvements=("improvements", "mean"), improvements_max=("improvements", "max"), top_skill_levels_max=("top_skill_impr", "max"))))
for s in (BASE, NEW):
    g = G[G.series == s]
    w(f"\n- {s}: {g.lp.mean():.2f} LP/run (CI {mci(g.lp)}), {g.attempts.sum()} attempts, {g.improvements.sum()} levels gained "
      f"({g.improvements.mean():.2f}/run), success {g.improvements.sum() / max(1, g.attempts.sum()):.0%} of attempts")
big = G[(G.series == NEW) & (G.improvements >= 3)]
w("\nRuns with ≥ 3 levels gained (new series): " + (", ".join(f"{r.run} {r.persona} {r.improvements} ({r.top_skill} +{r.top_skill_impr})" for r in big.itertuples()) or "none"))
sk = Counter(); ski = Counter()
for x in XS[NEW]:
    for k, v in ((x["run"].get("growth") or {}).get("skills") or {}).items(): sk[k] += v.get("lp_gained", 0); ski[k] += v.get("improvements", 0)
w("\nLP / levels by skill (new series): " + ", ".join(f"{k} {sk[k]:g}/{ski[k]}" for k, _ in sk.most_common()))

w("\n### H. Cost (USD)\n")
rows = []
for s in (BASE, NEW):
    g = R[coh(s)]
    rows.append(dict(series=s, runs=len(g), game=g.game_usd.sum(), npc_reaction=g.npc_reaction_usd.sum(), persona=g.persona_usd.sum(),
                     jev=g.jev_usd.sum(), total=g.game_usd.sum() + g.persona_usd.sum() + g.jev_usd.sum(),
                     per_run=(g.game_usd.sum() + g.persona_usd.sum() + g.jev_usd.sum()) / max(1, len(g)),
                     game_per_run=g.game_usd.mean(), persona_per_run=g.persona_usd.mean(), jev_per_run=g.jev_usd.mean()))
w(md(pd.DataFrame(rows).set_index("series"), 4))
w("\n" + md(R[coh(NEW)].groupby("persona").agg(runs=("run_id", "size"), game=("game_usd", "mean"), persona=("persona_usd", "mean"), jev=("jev_usd", "mean")), 4))

w("\n### I. Run conditions (new series)\n")
xs = XS[NEW]
if xs:
    w("git SHA: " + ", ".join(sorted({x["run"].get("git_sha") or "?" for x in xs})))
    fl = {}
    for x in xs:
        for k, v in (x["run"].get("flags") or {}).items(): fl.setdefault(k, set()).add(str(v))
    w("\nRun flags: " + "; ".join(f"{k}={'/'.join(sorted(v))}" for k, v in sorted(fl.items())))
    w("\nSession features (world_state): " + ", ".join(f"{k} {v}" for k, v in Counter(",".join(x.get("features") or []) or "none" for x in xs).items()))
    w("\nCharacters: " + ", ".join(sorted({f"{x['run']['persona']}: {(x.get('character') or {}).get('name')}" for x in xs})))
    w("\nWindow (UTC): " + min(x["run"]["started_at"] for x in xs) + " … " + max((x["run"].get("finished_at") or "") for x in xs))
    w("\nStatus/stop: " + ", ".join(f"{k} {v}" for k, v in Counter(f"{x['run']['status']}/{x['run']['stop_reason']}" for x in xs).items()))
    w("\nRubrics: " + ", ".join(f"{k} {v}" for k, v in Counter(f"{x['run']['persona']}:{(first_session(x) or {}).get('rubric_version')}" for x in xs).items()))
