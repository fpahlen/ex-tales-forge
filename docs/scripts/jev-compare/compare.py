#!/usr/bin/env python3
"""Jev comparison: new playtest runs vs the 2026-10-07 Elara runs.

Redoes the analysis in docs/analysis-jev-scores-2026-10-07.md (per persona, by
turn, correlations, low scores and their causes, low confidence) for every
cohort, then compares each cohort with the reference (the Elara runs).

Cohorts:
  * elara: runs played with the default character, Elara Voss (every run before
    persona-chosen characters), unless they carry a series tag;
  * SERIES/VARIANT: runs tagged by TalesForge.Playtest.Series in their notes
    ("series=NAME variant=V"); short git SHA and character are kept per run.

Usage:
  python3 compare.py raw_export.json jev_export.json [--out report.md] [--csv DIR]
                     [--reference COHORT] [--rescore rescore.json]
  (several export files may be given; runs are de-duplicated by id)

  --reference: the cohort the others are compared with (default: elara), e.g.
    "baseline-2026-10-07/default" for the post-rework comparison.
  --rescore: rows from docs/scripts/jev-rescore/rescore.exs; for every run in it, the
    session and turn scores of the "new" rubric replace the stored first pass, so a
    reference cohort scored with an older rubric can be compared like for like (the
    turn confidences of re-scored runs are unknown and left empty).

Read-only: it reads export JSON files and writes a Markdown report and CSVs.
Needs pandas, numpy and scipy.
"""
import argparse, json, math, re, sys
from collections import Counter
import numpy as np, pandas as pd
from scipy import stats

REFERENCE = "elara"         # --reference changes the comparison cohort; Elara runs stay "elara"
ELARA = "elara"
ANTI_PERSONAS = {"ronny"}  # scored for exploit coverage, kept out of delight averages
LOW_CONF = 0.3             # below this a score counts as "unscored" (analysis rec. 12)
STOP = set("the a an and or of to in on at for with your you his her their it its is was are be as by "
           "from that this into but not no so if then than there here i me my we our he she they them".split())
STOCK = {
    "eyes narrow": r"eyes narrow",
    "scarred oak": r"scarred (oak|bar|wood|counter)",
    "slides the mug": r"slides? (the|a) (mug|tankard)",
    "hearth crackles": r"(hearth|fire) (crackles|pops)",
    "two copper": r"two coppers?",
    "wind moans": r"wind (moans|rattles)",
}
BRUSH_OFF = r"eyes narrow|voice (flat|goes flat)|clearly done|that's all i'll say|cheap words|not my business|keep to yourself"
HOOK = r"osric|caldern|steward|\bnest\b|\bshaft\b|bounty|\bjob\b|\bwork\b|pays? (good )?(coin|silver|steel)|lend a hand|drovers?"


QUOTED = r'"[^"]*"|\u201c[^\u201d]*\u201d'  # dialogue in straight or curly quotes


def words(s): return re.findall(r"[a-z']+", (s or "").lower())
def ngrams(ws, n=3): return set(tuple(ws[i:i + n]) for i in range(len(ws) - n + 1))


def entropy(p):
    v = [x for x in (p or {}).values() if x and x > 0]
    return -sum(x * math.log(x) for x in v) / math.log(5) if v else None


def cohort(x):
    notes = x["run"].get("notes") or ""
    m = re.search(r"series=(\S+) variant=(\S+)", notes)
    if m: return f"{m.group(1)}/{m.group(2)}"
    name = (x.get("character") or {}).get("name") or "Elara Voss"
    return ELARA if name.startswith("Elara") else f"other/{x.get('variant', 'default')}"


def _top_skill_lp(turns):
    """LP of the skill that gained most in the run (from each turn's rules result)."""
    per = Counter()
    for t in turns:
        m = t.get("mech") or {}
        if m.get("skill"): per[m["skill"]] += float(m.get("lp_awarded") or 0)
    return max(per.values() or [0])


def _rescore(js, s0):
    """Session score of the latest pass with another rubric (e.g. Hawk/Ronny re-scored after #57), or None."""
    later = [s for s in js if s["kind"] == "session_affect" and s["rubric_version"] != s0["rubric_version"]]
    if not later: return None
    first = sorted(later, key=lambda s: s["inserted_at"])[0]
    return dict(rubric=first["rubric_version"], overall=first["overall"], confidence=first["confidence"])


def _character_changes(x):
    """Per-run character-change numbers from export.exs (TalesForge.Playtest.CharacterChanges.run_metrics/1)."""
    cc = x.get("character_changes")
    if not cc:
        return dict(cc_memories=np.nan, cc_npcs_changed=np.nan, cc_npcs_attitude=np.nan, cc_attitude=np.nan,
                    cc_stance=np.nan, cc_relationship=np.nan)
    return dict(cc_memories=cc.get("memories_added"), cc_npcs_changed=cc.get("npcs_changed"),
                cc_npcs_attitude=cc.get("npcs_attitude_changed"), cc_attitude=float(bool(cc.get("attitude_changed?"))),
                cc_stance=float(bool(cc.get("stance_changed?"))), cc_relationship=float(bool(cc.get("relationship_changed?"))))


def build(runs, rescore=None):
    rescore = rescore or {}
    R, T = [], []
    for x in runs:
        r = x["run"]
        js = [s for s in x["scores"] if s["source"] == "jev"]
        sess = sorted([s for s in js if s["kind"] == "session_affect"], key=lambda s: s["inserted_at"])
        if not sess: continue
        s0 = sess[0]  # first scoring pass is primary (a run scored twice keeps its first pass)
        c = cohort(x)
        char = x.get("character") or {}
        first = (char.get("name") or "Elara").split()[0]
        calls = x["calls"]
        # Jev = the scorer only. npc_reaction calls also run on a jev-* model, but they are part of the game.
        is_jev = lambda k: k["purpose"] == "scorer"
        usd = lambda keep: sum((k.get("cost_micro_usd") or 0) for k in calls if keep(k)) / 1e6
        R.append(dict(cohort=c, run_id=r["id"], persona=r["persona"], module=r["module"], started_at=r["started_at"],
                      git_sha=(r.get("git_sha") or "")[:7] or None, variant=x.get("variant", "default"),
                      flags=json.dumps(r.get("flags") or {}, sort_keys=True), character=char.get("name") or "Elara Voss (default)",
                      race=char.get("race"), klass=char.get("class"), turns_played=len(x["turns"]),
                      stop_reason=r.get("stop_reason"), session_score=s0["overall"], session_conf=s0["confidence"],
                      session_entropy=entropy(s0["probabilities"]), rubric=s0["rubric_version"],
                      game_usd=usd(lambda k: k["purpose"] != "persona" and not is_jev(k)),
                      persona_usd=usd(lambda k: k["purpose"] == "persona") or (r.get("persona_cost_micro_usd") or 0) / 1e6,
                      jev_usd=usd(is_jev), npc_reaction_usd=usd(lambda k: k["purpose"] == "npc_reaction"),
                      g_lp=(r.get("growth") or {}).get("lp_gained"), g_rolls=(r.get("growth") or {}).get("rolls"),
                      g_attempts=(r.get("growth") or {}).get("attempts"),
                      g_skills=json.dumps((r.get("growth") or {}).get("skills") or {}, sort_keys=True),
                      rolls=sum(1 for t in x["turns"] if ((t.get("mech") or {}).get("outcome") not in (None, "none"))),
                      lp=sum(float((t.get("mech") or {}).get("lp_awarded") or 0) for t in x["turns"]),
                      top_skill_lp=_top_skill_lp(x["turns"]),
                      improvements=(r.get("growth") or {}).get("improvements"),
                      **_character_changes(x),
                      rescore=_rescore(js, s0)))
        new = rescore.get(r["id"])
        if new:  # stored first pass replaced by the re-scored new rubric (like-for-like comparison)
            R[-1].update(session_score=new["session"], session_conf=new.get("session_conf"), session_entropy=np.nan,
                         rubric=new.get("rubric_label", "new rubric (re-scored)"))
        seen = set()
        turns = {t["n"]: t for t in x["turns"]}
        gm_calls = {k["turn_number"]: k for k in calls if k["purpose"] == "gm" and k["turn_number"] is not None}
        prev = ngrams(words(x.get("opening")))
        feats = {}
        for n in sorted(turns):
            t = turns[n]; pw, gw = words(t["player"]), words(t["gm"])
            pc = {w for w in pw if w not in STOP}; g3 = ngrams(gw); low = (t["gm"] or "").lower()
            mech = t.get("mech") or {}
            feats[n] = dict(player=t["player"], gm=t["gm"], player_words=len(pw), gm_words=len(gw),
                            echo_content=len([w for w in pc if w in set(gw)]) / max(1, len(pc)),
                            echo_trigram=len(ngrams(pw) & g3) / max(1, len(ngrams(pw))),
                            gm_repeat_trigram=len(g3 & prev) / max(1, len(g3)),
                            outcome=mech.get("outcome"), skill=mech.get("skill"), roll=mech.get("roll"),
                            lp=float(mech.get("lp_awarded") or 0), improved=len([i for i in (mech.get("improvements") or [])
                                                                                if isinstance(i, dict) and i.get("improved")]),
                            checked=mech.get("outcome") not in (None, "none"),
                            failed=mech.get("outcome") in ("failure", "critical_failure"),
                            brush_off=bool(re.search(BRUSH_OFF, low)),
                            stock=sum(bool(re.search(p, low)) for p in STOCK.values()),
                            # narration only: an NPC saying the character's name in dialogue is not a POV slip
                            third_person=bool(re.search(rf"\b{re.escape(first.lower())}\b", re.sub(QUOTED, " ", low))),
                            hook=bool(re.search(HOOK, low)),
                            gm_latency_ms=gm_calls.get(n, {}).get("latency_ms"))
            for k, p in STOCK.items(): feats[n]["stock:" + k] = bool(re.search(p, low))
            prev |= g3
        if new:
            ns = sorted(turns)
            for n, sc in zip(ns, new["turns"]):
                T.append(dict(cohort=c, run_id=r["id"], persona=r["persona"], turn=n, score=sc, conf=np.nan, entropy=np.nan,
                              probs="", turns_in_run=len(x["turns"]), is_last_turn=n == len(x["turns"]), **feats.get(n, {})))
            continue
        for s in sorted([s for s in js if s["kind"] == "turn_affect"], key=lambda s: (s["turn_number"], s["inserted_at"])):
            n = s["turn_number"]
            if n in seen: continue  # primary pass only
            seen.add(n)
            T.append(dict(cohort=c, run_id=r["id"], persona=r["persona"], turn=n, score=s["overall"],
                          conf=s["confidence"], entropy=entropy(s["probabilities"]), probs=json.dumps(s["probabilities"]),
                          turns_in_run=len(x["turns"]), is_last_turn=n == len(x["turns"]), **feats.get(n, {})))
    R, T = pd.DataFrame(R), pd.DataFrame(T)
    if len(T):
        T["dm"] = T.score - T.groupby("run_id").score.transform("mean")
        T["cdm"] = T.conf - T.groupby("run_id").conf.transform("mean")
    return R, T


def cliffs_delta(a, b):
    a, b = np.asarray(a), np.asarray(b)
    if not len(a) or not len(b): return np.nan
    return ((a[:, None] > b[None, :]).sum() - (a[:, None] < b[None, :]).sum()) / (len(a) * len(b))


def boot_ci(a, b, n=5000, seed=7):
    a, b = np.asarray(a), np.asarray(b)
    if len(a) < 2 or len(b) < 2: return (np.nan, np.nan)
    rng = np.random.default_rng(seed)
    d = [rng.choice(a, len(a)).mean() - rng.choice(b, len(b)).mean() for _ in range(n)]
    return tuple(np.percentile(d, [2.5, 97.5]))


def mwu(a, b):
    return stats.mannwhitneyu(a, b).pvalue if len(a) > 1 and len(b) > 1 else np.nan


def md(df, floatfmt=2):
    return df.round(floatfmt).to_markdown() if len(df) else "_no data_"


def report(R, T):
    out = []; w = out.append
    w("# Jev comparison report\n")
    w(f"Runs: {len(R)}; scored turns: {len(T)}. Reference cohort: `{REFERENCE}`. "
      f"Primary scoring pass only. Ronny is an anti-persona: shown, but kept out of the 'all (no Ronny)' rows.\n")
    w("## 0. Cohorts, builds and rubrics\n")
    w(md(R.groupby(["cohort", "persona"]).agg(runs=("run_id", "size"), turns=("turns_played", "mean"),
                                               git_sha=("git_sha", lambda s: ", ".join(sorted({x for x in s if isinstance(x, str) and x})) or "—"),
                                               rubric=("rubric", lambda s: ", ".join(sorted(set(s)))),
                                               character=("character", lambda s: ", ".join(sorted({str(x) for x in s}))))))
    w("\nA rubric hash that differs between cohorts (Hawk and Ronny changed in ex-tales-forge #57) means the levels changed: compare those personas with care.\n")

    w("## 1. Per persona\n")
    sess = R.groupby(["persona", "cohort"]).agg(n=("session_score", "size"), mean=("session_score", "mean"),
                                                 sd=("session_score", "std"), conf=("session_conf", "mean"),
                                                 conf_lt_03=("session_conf", lambda s: (s < LOW_CONF).sum()))
    w("### Session scores\n"); w(md(sess))
    turn = T.groupby(["persona", "cohort"]).agg(n=("score", "size"), mean=("score", "mean"), sd=("score", "std"),
                                                 conf=("conf", "mean"), conf_lt_03=("conf", lambda s: (s < LOW_CONF).sum()),
                                                 within_run_sd=("dm", "std"))
    w("\n### Turn scores\n"); w(md(turn))
    nr = T[~T.persona.isin(ANTI_PERSONAS) & (T.conf >= LOW_CONF)]
    w("\n### All personas but Ronny, turns with confidence ≥ 0.3\n")
    w(md(nr.groupby("cohort").agg(n=("score", "size"), mean=("score", "mean"), conf=("conf", "mean"))))

    w("\n## 2. By turn index\n")
    w(md(T.pivot_table(index="turn", columns="cohort", values="score", aggfunc="mean")))
    w("\nPer persona and turn (mean score):\n")
    w(md(T.pivot_table(index="turn", columns=["cohort", "persona"], values="score", aggfunc="mean")))
    w("\nWithin-run (score minus the run's mean), and confidence by turn:\n")
    w(md(T.pivot_table(index="turn", columns="cohort", values=["dm", "conf"], aggfunc="mean")))
    for c, g in T.groupby("cohort"):
        d = g.groupby("run_id").apply(lambda r: r[r.turn == 1].score.mean() - r[r.turn > 1].score.mean()).dropna()
        if len(d) > 1:
            w(f"\n- `{c}`: turn 1 minus the rest, per run: mean {d.mean():+.2f} (n={len(d)}, T1 lower in {(d < 0).sum()}).")

    w("\n\n## 3. Correlations (turn level, Spearman, within cohort)\n")
    rows = []
    for c, g in T.groupby("cohort"):
        for col in ["turn", "gm_words", "player_words", "echo_content", "gm_repeat_trigram", "failed", "checked",
                    "roll", "brush_off", "stock", "third_person", "hook", "gm_latency_ms"]:
            for tgt in ["score", "dm", "conf"]:
                s = g[[col, tgt]].dropna().astype(float)
                if len(s) > 5 and s[col].nunique() > 1:
                    rho, p = stats.spearmanr(s[col], s[tgt]); rows.append((c, col, tgt, len(s), rho, p))
    w(md(pd.DataFrame(rows, columns=["cohort", "feature", "target", "n", "rho", "p"]).set_index(["cohort", "feature", "target"]), 3))

    w("\n\n## 4. Low scores and low confidence\n")
    for c, g in T.groupby("cohort"):
        low = g.nsmallest(10, "score")
        w(f"\n### `{c}`: lowest 10 turns\n")
        w(md(low.assign(run=low.run_id.str[:8], gm_start=low.gm.fillna("").str[:110])
             [["run", "persona", "turn", "score", "conf", "skill", "outcome", "brush_off", "stock", "third_person",
               "echo_content", "gm_start"]].set_index("run")))
        tally = Counter()
        for _, t in low.iterrows():
            if t.brush_off: tally["NPC brush-off"] += 1
            if t.failed: tally["failed check"] += 1
            if t.echo_content >= 0.5: tally["echo of the player's words"] += 1
            if t.gm_repeat_trigram >= 0.15: tally["repetition"] += 1
            if t.third_person: tally["third person / name"] += 1
            if t.stock: tally["stock phrase"] += 1
        w("\nCause tally (automatic markers; read the turns before quoting them): " +
          (", ".join(f"{k} {v}" for k, v in tally.most_common()) or "none"))
        nh = g[g.persona != "hawk"].nsmallest(10, "score")
        if len(nh) and (g.persona == "hawk").any():
            w(f"\n\n`{c}`: lowest 10 non-Hawk turns\n")
            w(md(nh.assign(run=nh.run_id.str[:8], gm_start=nh.gm.fillna("").str[:110])
                 [["run", "persona", "turn", "score", "conf", "skill", "outcome", "brush_off", "echo_content", "gm_start"]].set_index("run")))
        lc = g[g.conf < LOW_CONF]
        w(f"\n\nConfidence < {LOW_CONF}: {len(lc)} of {len(g)} turns" +
          (" — " + ", ".join(f"{r.run_id[:8]} {r.persona} T{r.turn}" for r in lc.itertuples()) if len(lc) else ""))

    w(f"\n\n## 5. Versus the reference (`{REFERENCE}`)\n")
    ref_R, ref_T = R[R.cohort == REFERENCE], T[T.cohort == REFERENCE]
    rows = []
    for c in sorted(set(R.cohort) - {REFERENCE}):
        for p in sorted(set(R.persona)) + ["all (no Ronny)"]:
            sel = (lambda d: d[~d.persona.isin(ANTI_PERSONAS)]) if p.startswith("all") else (lambda d, p=p: d[d.persona == p])
            a, b = sel(R[R.cohort == c]).session_score, sel(ref_R).session_score
            # turns 1-5: one mean per run (turns within a run are not independent), then compare runs
            ta = sel(T[(T.cohort == c) & (T.turn <= 5)]).groupby("run_id").score.mean()
            tb = sel(ref_T[ref_T.turn <= 5]).groupby("run_id").score.mean()
            if not len(a) and not len(ta): continue
            lo, hi = boot_ci(a, b); tlo, thi = boot_ci(ta, tb)
            rows.append(dict(cohort=c, persona=p, n=len(a), n_ref=len(b), session=a.mean(), session_ref=b.mean(),
                             diff=a.mean() - b.mean(), ci95="—" if np.isnan(lo) else f"{lo:+.2f}…{hi:+.2f}", cliffs=cliffs_delta(a, b),
                             p_mwu=mwu(a, b), turns1_5=ta.mean(), turns1_5_ref=tb.mean(), diff1_5=ta.mean() - tb.mean(),
                             ci95_1_5="—" if np.isnan(tlo) else f"{tlo:+.2f}…{thi:+.2f}", p_turns1_5=mwu(ta, tb),
                             ref_small="yes" if len(b) < 5 else ""))
    w(md(pd.DataFrame(rows).set_index(["cohort", "persona"]) if rows else pd.DataFrame(), 3))
    w("\n\nThe Elara runs were mostly 5 turns long, so turns 1–5 is the like-for-like window; session scores of 10-turn runs judge a longer story. "
      "`turns1_5` is the mean over runs of each run's turn 1–5 mean; its CI and p are over runs, not turns. "
      "`ref_small` = fewer than 5 Elara runs: treat that row as anecdote.\n")

    w("\n### Game behaviour per cohort\n")
    beh = T.groupby("cohort").agg(turns=("score", "size"), check_rate=("checked", "mean"),
                                  insight_share=("skill", lambda s: (s == "insight").mean()),
                                  fail_rate=("failed", "mean"), brush_off=("brush_off", "mean"),
                                  stock_per_turn=("stock", "mean"), third_person=("third_person", "mean"),
                                  echo=("echo_content", "mean"), repeat=("gm_repeat_trigram", "mean"))
    hook2 = T[T.turn <= 2].groupby(["cohort", "run_id"]).hook.any().groupby("cohort").mean().rename("hook_by_t2")
    eyes = T.groupby(["cohort", "run_id"])["stock:eyes narrow"].any().groupby("cohort").mean().rename("runs_with_eyes_narrow")
    w(md(beh.join(hook2).join(eyes), 3))
    w("\n\n### Game behaviour per persona\n")
    bp = T.groupby(["cohort", "persona"]).agg(turns=("score", "size"), check_rate=("checked", "mean"), fail_rate=("failed", "mean"),
                                              brush_off=("brush_off", "mean"), stock_per_turn=("stock", "mean"),
                                              third_person=("third_person", "mean"), echo=("echo_content", "mean"),
                                              gm_words=("gm_words", "mean"))
    hk = T[T.turn <= 2].groupby(["cohort", "persona", "run_id"]).hook.any().groupby(["cohort", "persona"]).mean().rename("hook_by_t2")
    w(md(bp.join(hk), 3))
    w("\n\n### Dice outcomes (turns)\n")
    w(md(pd.crosstab([T.cohort, T.persona], T.outcome.fillna("missing"))))
    w("\n\nScore by outcome:\n")
    w(md(T.pivot_table(index=["cohort", "outcome"], values="score", aggfunc=["count", "mean"])))
    w("\n\n### Cost per run (USD; game, persona bot and Jev kept apart)\n")
    cost = dict(runs=("run_id", "size"), turns=("turns_played", "mean"), game=("game_usd", "mean"),
                npc_reaction=("npc_reaction_usd", "mean"), persona=("persona_usd", "mean"), jev=("jev_usd", "mean"),
                game_total=("game_usd", "sum"), persona_total=("persona_usd", "sum"), jev_total=("jev_usd", "sum"))
    w(md(R.groupby("cohort").agg(**cost), 4))
    w("\n`game` includes `npc_reaction` (shown separately; it runs on a jev-* model but is part of the game). `jev` is the scorer only.\n")
    w(md(R.groupby(["cohort", "persona"]).agg(**cost), 4))

    w("\n\n## 6. Skill growth (LP)\n")
    w("Rolls and LP per run (`lp_awarded` on each turn's rules result; `growth` on the run once ex-tales-forge #66 is in). "
      "Tiers after #64: a skill improves at 5/7/10/15 LP, so `turns_to_5lp` is how many turns the busiest skill needs at this pace.\n")
    g = R.assign(rolls_per_turn=R.rolls / R.turns_played.clip(lower=1), lp_per_turn=R.lp / R.turns_played.clip(lower=1))
    gs = g.groupby(["cohort", "persona"]).agg(runs=("run_id", "size"), turns=("turns_played", "mean"), rolls=("rolls", "mean"),
                                              rolls_per_turn=("rolls_per_turn", "mean"), lp=("lp", "mean"),
                                              lp_per_turn=("lp_per_turn", "mean"), top_skill_lp=("top_skill_lp", "mean"),
                                              improvements=("improvements", "sum"))
    gs["turns_to_5lp"] = (5 / (gs.top_skill_lp / gs.turns)).replace([np.inf], np.nan)
    w(md(gs, 3))
    gr = R[R.g_lp.notna()]
    if len(gr):
        w("\n\nFrom the per-run growth log (`playtest_runs.growth`, ex-tales-forge #66):\n")
        gg = gr.groupby(["cohort", "persona"]).agg(runs=("run_id", "size"), lp_gained=("g_lp", "mean"), lp_sd=("g_lp", "std"),
                                                    lp_max=("g_lp", "max"), rolls=("g_rolls", "mean"), attempts=("g_attempts", "mean"),
                                                    improvements=("improvements", "mean"), improvements_total=("improvements", "sum"),
                                                    runs_with_any_lp=("g_lp", lambda s: (s > 0).sum()))
        w(md(gg, 3))
        sk = Counter()
        for js_ in gr.g_skills:
            for k, v in json.loads(js_).items(): sk[k] += float(v.get("lp_gained") or 0)
        w("\n\nLP by skill (all runs with a growth log): " + (", ".join(f"{k} {v:g}" for k, v in sk.most_common()) or "none"))
    w("\n\n## 7. Reference runs re-scored with today's rubric\n")
    rs = R[R.rescore.notna()]
    if len(rs):
        rr = pd.DataFrame([dict(cohort=r.cohort, persona=r.persona, run=r.run_id[:8], first_rubric=r.rubric, first=r.session_score,
                                first_conf=r.session_conf, new_rubric=r.rescore["rubric"], new=r.rescore["overall"],
                                new_conf=r.rescore["confidence"]) for r in rs.itertuples()]).set_index(["cohort", "persona", "run"])
        w(md(rr, 2))
    else:
        w("_none_")
    w("\n\n## 8. Character changes (player character and NPCs)\n")
    w("Per run, from `TalesForge.Playtest.CharacterChanges.run_metrics/1` (ex-tales-forge, export field `character_changes`). "
      "`attitude_share`: share of runs where some NPC's latest Jev stance toward the player character is not neutral, "
      "or its relationship score moved off 0; `npcs_attitude`: NPCs per run whose attitude changed; `memories`: memories "
      "NPCs gained per run; `npcs_changed`: NPCs with any stored change per run. Median and mean.\n")
    cc = R[R.cc_memories.notna()] if "cc_memories" in R else R.iloc[0:0]
    if len(cc):
        ct = cc.groupby("cohort").agg(runs=("run_id", "size"), attitude_share=("cc_attitude", "mean"),
                                      stance_share=("cc_stance", "mean"), relationship_share=("cc_relationship", "mean"),
                                      npcs_attitude_median=("cc_npcs_attitude", "median"), npcs_attitude_mean=("cc_npcs_attitude", "mean"),
                                      memories_median=("cc_memories", "median"), memories_mean=("cc_memories", "mean"),
                                      npcs_changed_median=("cc_npcs_changed", "median"), npcs_changed_mean=("cc_npcs_changed", "mean"))
        w(md(ct, 2))
    else:
        w("_No export carries `character_changes` yet (needs the CharacterChanges module on the playtest app)._")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("exports", nargs="+"); ap.add_argument("--out"); ap.add_argument("--csv")
    ap.add_argument("--reference", default=REFERENCE); ap.add_argument("--rescore")
    a = ap.parse_args()
    globals()["REFERENCE"] = a.reference
    rescore = {}
    if a.rescore:
        rescore = {row["run"]: row for row in json.load(open(a.rescore)) if row.get("rubric") == "new"}
    runs = {}
    for f in a.exports:
        for x in json.load(open(f)): runs[x["run"]["id"]] = x
    R, T = build(list(runs.values()), rescore)
    text = report(R, T)
    if a.out: open(a.out, "w").write(text)
    else: sys.stdout.write(text)
    if a.csv:
        R.to_csv(f"{a.csv}/runs.csv", index=False); T.to_csv(f"{a.csv}/turns.csv", index=False)


if __name__ == "__main__":
    main()
