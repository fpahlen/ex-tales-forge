---
title: "Analysis: INTENT_CALL_EVERY_TURN off vs on (2026-10-08)"
updated: 2026-10-08
status: analysis
---

# Analysis: INTENT_CALL_EVERY_TURN off vs on (2026-10-08)

**Question:** ex-tales-forge [PR #76](https://github.com/whyse-ab/ex-tales-forge/pull/76) adds a safety read of the player's message to the existing Tier 1 intent call. When the read says `benign` with confidence ≥ 0.90 (`PLAYER_QUOTE_MIN_BENIGN_CONFIDENCE`), the GM gets the player's own words (`gm_quote`). Otherwise it gets the typed intent summary. Only about 5% of turns make the intent call. The rest are resolved by the heuristic alone, so with #76 the GM sees something like `speak (target: innkeep)` on those turns. The opt-in flag `INTENT_CALL_EVERY_TURN=on` sends every turn through the intent call. We ran a short playtest batch with the flag off and on. What does the flag buy, and what does it cost?

**Short answer:** Keep the flag **off**. It does what it promises: 85 of 112 turns (76%) quoted the player's own words, with no false positives. But it also turns on a **clarification storm** that the heuristic path never triggers. That makes play slower and more expensive and gives the GM option labels instead of the player's words on a quarter of turns. Jev saw no difference.

1. **Clarification loops: 35% of turns instead of 4%.** On every turn the LLM intent call applies its "compound action with unclear priority → ask" rule. With the flag on, **39 of 112 turns (35%, Wilson 95% 27–44%)** asked the player to pick an option at least once (77 clarification requests in total, up to 5 on a single turn). With the flag off it was **4 of 108 (3.7%, 1.4–9.1%)**. Paul's long, rhetorical in-character lines were hit hardest: **13 of 20 turns (65%)**, 29 requests. Then come Lars at 35%, Ronny at 36% and Hawk at 33%. Lotta was least affected (5%). On a turn that ends in a clarification, the GM gets the **option label** the player picked ("Help move barrels and question Tam", "Ask Tam to lead the way"), not the player's words: **25 turns** (`no_intent_call_clarification`). For a real player, a multiple-choice question on a third of turns would be very visible.
2. **Jev: no detectable change.** Persona-centred, without Ronny (8 runs per arm), on − off is **+0.01 session** (bootstrap 95% CI −0.15…+0.16), **+0.08 turn mean** (−0.01…+0.17) and **+0.08 confidence-weighted turn mean** (−0.02…+0.18). Per persona, every difference is within noise with 2 runs a side (table in §2). The unsure share (turn confidence < 0.7) is 78% off and 66% on, which is high on both sides.
3. **Dialogue: the GM engages more with the player's own words. Directional, not measured rigorously.** On quoted turns, a mean **35%** of the player's content words come back in the GM reply. On summary turns it is **21%** (flag-on arm) and **23%** (flag-off arm). In the samples (§4) the quoted turns answer the question the player actually asked ("What's the stew tonight?" → "rabbit and barley"; "What does Caldern claim the voices say?" → the voices quoted). Summary turns more often answer a neighbouring question. Costs of quoting: an 8-word echo of the player's line in **3 of 85** quoted turns (0 of 131 summary turns), and a new tic, "…the words leave your mouth.", in **3 of 85**.
4. **Safety read: no false positives, but the threshold sits right on the model's lowest value.** All **85** reads said `benign`. Of the non-Ronny reads, **0 of 65** fell back (Wilson 95% 0–5.6%). The model only ever answered **0.95 (69 reads) or 0.90 (16 reads)**. Ten of the 0.90s are Ronny's in-fiction threats ("…or I'll burn this shithole down"), and labelling those benign is right. At threshold 0.90 everything quotes. At 0.91 those **16 turns (19%)** would fall back. **No persona tried a real jailbreak or prompt injection, so this batch says nothing about missed attacks (false negatives).**
5. **Cost.** Per finished run, game cost was **$0.1126 on vs $0.1008 off** (+12%). That understates the flag. The intent calls cost **$0.0031 per turn on vs $0.0002 off**. That is 167 intent calls for 112 turns, because each clarification round makes another one. The GM call happened to be cheaper on the on arm (more prompt-cache hits: 7.7k vs 6.0k cached tokens per call), and that hid part of it. Like for like, the flag adds about **+$0.0029 per turn, about 30% of the game cost per turn**. Persona-bot cost (separate): **$0.0418 vs $0.0256 per run (+63%)**. All of it comes from the persona answering clarifications: 79 extra persona calls. That is why Paul's runs cost 67k and 54k µUSD of persona instead of about 25k (29 and 20 persona calls for 10 turns).
6. **Latency.** The LLM intent step itself takes a median **1.7 s (p90 4.3 s)**. The heuristic step takes 0 s. From the last submission to the GM reply: median **6.3 s on vs 5.5 s off** (+0.8 s, CI +0.4…+1.4), p90 **12.6 vs 6.6 s**. The GM call was faster on the on arm (4.6 vs 5.1 s median, API load), which hides part of the 1.7 s. **From the player's first submission** (clarification rounds and answers included): median **7.7 vs 5.6 s**, p90 **19.4 vs 6.8 s**, max **106 s** (Paul, 5 clarification rounds on one turn).
7. **Hangs and failures:** no turn hung after an intent call in either arm (the #79 fix was in). One flag-off run timed out (Lars, turn 5). No AI call or turn job was recorded for that turn, so the stall happened before or during the persona's turn-5 call. That is a different pattern from the one #79 fixed. Two flag-on runs failed on **xAI 429 "model at capacity"** around 09:05–09:08 (Ronny at turn 8, Hawk at turn 1). That is not the flag; the driver topped both up. Lars's flag-on `stop=dead` is a real death: he rushed two orcs in the nest (turns 8–9) and died. His turn-10 action, "Try to stand and recover", is itself a clarification label.

**Something else to consider:** almost all the downside comes from clarifications, not from the safety read. One option is a variant of #76 where, on turns the heuristic already resolves, the extra intent call is used **only for the safety read and the quote**. It would never ask for clarification there, and the heuristic's action would stand. That would keep the 76% quote rate at about +1.7 s and +$0.002–0.003 per turn, without the 35% clarification rate. It would be worth re-running this batch on it. That is a code change, not a flag value, so Fredrik decides.

**Total cost of the batch:** 23 runs (20 done + 1 timeout + 2 xAI failures). **Game $2.29, persona bots $0.70, Jev scorer $0.005.** Playtest day total at the end: $5.74 of the $25 cap.

---

## 1. Data and method

| | Runs (done) | Turns | Window (CEST) | Build |
|---|---|---|---|---|
| Series `intent-off-2026-10-08`, flag unset | 11 (10 + 1 timeout) | 108 | 08:27–08:52 | #76 head `f4ea6ad`, playtest release **v64** |
| Series `intent-on-2026-10-08`, `INTENT_CALL_EVERY_TURN=on` | 12 (10 + 2 xAI 429 failures) | 112 | 08:53–09:24 | same |

- **Build:** #76 rebased onto `main` at `ccd5379` (merge of #79, the turn-hang fix; it already contains #77 and the survey page #78). CI green (Test, Dialyzer). Deployed to `tales-forge-playtest` only, by hand, the same way `playtest.yml` deploys: `flyctl deploy --remote-only -c fly.playtest.toml -a tales-forge-playtest --ha=false --depot=false --build-arg GIT_SHA=…`. The release command ran #76's migration (`ai_calls.meta`). The column stays in the playtest DB after the redeploy from main, and main's schema ignores it.
- **Flag:** set with `System.put_env("INTENT_CALL_EVERY_TURN", "on")` on the running playtest node (read at call time by `Config.intent_call_every_turn?/0`) and removed with `System.delete_env/1` after the batch. No Fly secret or config changed and the machine didn't restart. The data confirms the arms: with the flag on, every turn made the intent call except 2 (an intent call that failed and fell back to the heuristic). With it off, 4 of 108 did (the usual ~5%).
- **Driver:** [`scripts/intent-every-turn/drive.sh`](scripts/intent-every-turn/drive.sh), a copy of the post-rework driver. Round-robin Paul, Lotta, Lars, Ronny, Hawk, 2 runs each per arm, 10 turns (Hawk 12), `variant=default`, `tin_valley`. A run that doesn't count as done is logged and topped up at the end. Run flags: `npc_reactions=on`, `world_agents=off`, `llm_provider=xai`, `gm_model`/`intent_model` = `grok-4.20-0309-non-reasoning`. Same characters as the post-rework series.
- **Data:** [`export.exs`](scripts/intent-every-turn/export.exs) (read-only) → [`analyze.py`](scripts/intent-every-turn/analyze.py) and [`extra.py`](scripts/intent-every-turn/extra.py). Full tables: [`analyze-output.md`](scripts/intent-every-turn/analyze-output.md). Safety labels and the quote decision come from the `turn.intent` row's `meta` (`label`, `confidence`, `threshold`, `used`, `reason`). A `turn.intent` row without `meta` is a clarification request.
- **Jev:** the stored primary scores (`jev-affect-v1`, the same per-persona rubric hashes on both arms). Runs that stopped early (timeout, errors) are left out of the Jev tables. Lars's death at turn 10 counts, because he played all 10 turns.
- **Small samples:** 2 runs per persona and arm. A per-persona CI over 2 runs is very wide (t with 1 df). The pooled persona-centred comparison (8 vs 8 runs without Ronny) is the only Jev number with any power, and it can only detect differences of about ±0.15 session points.

## 2. Jev

| Persona | Session off (n) | Session on (n) | Turn mean off | Turn mean on | Weighted off | Weighted on | Unsure off | Unsure on |
|---|---|---|---|---|---|---|---|---|
| Paul | 4.71 (2) | 4.81 (2) | 4.12 | 4.25 | 4.18 | 4.26 | 75% | 55% |
| Lotta | 4.11 (2) | 3.94 (2) | 3.69 | 3.78 | 3.66 | 3.79 | 95% | 85% |
| Lars | 3.42 (2) | 3.36 (2) | 3.28 | 3.35 | 3.35 | 3.47 | 80% | 85% |
| Ronny\* | 4.51 (2) | 3.73 (2) | 4.46 | 4.06 | 4.72 | 4.27 | 40% | 65% |
| Hawk | 4.61 (2) | 4.76 (2) | 2.44 | 2.45 | 2.39 | 2.40 | 62% | 38% |
| **All but Ronny** | **4.21** [3.74, 4.69] (8) | **4.22** [3.66, 4.78] (8) | 3.38 | 3.46 | 3.40 | 3.48 | 78% | 66% |

Weighted = confidence-weighted turn reading, sum(score × conf) / sum(conf). Unsure = share of turns with confidence < 0.7. \*Ronny is the anti-persona and is kept out of "all". His on-arm drop comes from one run (765d64fa, session 2.75, the run where he ends by shaking down Rusk), so it's noise at n = 2.

Persona-centred on − off without Ronny: session **+0.01** (−0.15…+0.16), turn mean **+0.08** (−0.01…+0.17), weighted **+0.08** (−0.02…+0.18). Paul is the one persona where the flag should help most (long lines that a summary flattens). He is up 0.10 session and 0.13 turn mean, but he is also the one most often interrupted by clarifications. With 2 runs a side, neither effect can be separated from noise.

## 3. Safety read and what the GM got

| | Off | On |
|---|---|---|
| Turns | 108 | 112 |
| Turns with an LLM safety read | 4 | 85 |
| GM got the player's words (`quote`) | 4 (3.7%) | **85 (76%)** |
| GM got the summary: heuristic turn, no read | 101 | 2 (intent call failed, heuristic fallback) |
| GM got the summary: turn resolved from a clarification option | 3 | **25** |
| Labels | benign 4 | benign 85 |
| Confidence values | 0.95 × 4 | 0.95 × 69, **0.90 × 16** (Ronny 10, Lars 2, Hawk 2, Paul 1, Lotta 1) |
| Fell back below 0.90 (non-Ronny) | 0 / 4 | **0 / 65** (Wilson 0–5.6%) |
| Clarification requests | 5 (4 turns) | **77 (39 turns)** |

Every one of Ronny's 20 reads was benign. His messages are greedy and threatening in fiction ("Give me the exact details… or I'll flip this bar", "Make me, thief. Or better yet, how about you pay me twenty silver to leave you breathing?"). That is play, not an attack on the system, so `benign` is right, and the drop to 0.90 on threats is a sensible signal. But the model rounds to two values, so the 0.90 threshold is effectively "quote everything labelled benign". The batch had no jailbreak or injection input, so it can't measure missed attacks.

## 4. Does the GM engage with what the player said?

Proxy: the share of the player's content words (> 3 letters, no stop words) that come back in the GM reply.

| | Quoted turns | Summary turns |
|---|---|---|
| Flag off | 0.29 (n = 4) | 0.23 (n = 104) |
| Flag on | **0.35** (n = 85) | 0.21 (n = 27) |

Echo (an 8-word run of the player's line repeated): quoted 3 / 85, summary 0 / 131. The post-rework series had 5.0% of all turns. "…the words leave your mouth." appears 3 / 85 quoted, 0 elsewhere.

Samples (random draws of turns where the player asked something):

- *Flag on, quote. Lotta, T1:* "Hilde Stonebrook. Looking for a room and a hot meal. What's the stew tonight?" → "Hilde Stonebrook, then! Welcome to the Valley Inn. Stew tonight is rabbit and barley… A room's two silver for the night." Answers both questions and uses the name. (It also opens with "You step to the bar and the words leave your mouth.")
- *Flag on, quote. Lotta, T5:* "What exactly does Caldern claim these voices in the shafts are saying?" → "Caldern swears the voices call out names, old miners long dead… Whispers of 'deeper, come deeper'…" A direct answer.
- *Flag on, quote. Paul, T7:* "…tell me true now, what troubles you about young Pip and those lampless carts?" → Tam: "Pip's in it deep, sir… Those lampless carts belong to Rusk's Tinjacks…" A direct answer.
- *Flag off, summary. Lotta, T5:* "Tell me more about those boot prints, too wide for orcs, you said. What do you reckon made them?" → Brenna talks about missing salt and "no orc tracks, just boot prints heading straight for the old adit…" On topic, but she doesn't say what she thinks made them.
- *Flag off, summary. Paul, T5:* "…tell me, who among these good folk might join their voices to mine?" → Brenna talks about Osric's twenty-gold bounty. A neighbouring answer, not the question asked.
- *Flag on, clarification. Paul, T3–T10:* long sermon-like lines get 2–5 clarification rounds. The turn then runs on the option label ("Help move barrels and question Tam", "Praise Tam and ask him to lead"). That is exactly the flattening the flag was meant to remove.

## 5. Cost (USD per finished run; persona bots kept apart)

| | n | Game mean [95% CI] | Intent calls in game | GM call per turn | Persona bots | Jev scorer |
|---|---|---|---|---|---|---|
| Off | 10 | 0.1008 [0.0828, 0.1188] | 0.0021 | 0.0086 | 0.0256 | 0.0002 |
| On | 10 | 0.1126 [0.0955, 0.1297] | **0.0332** | 0.0065 | **0.0418** | 0.0002 |

- Intent calls: 9 off (4 safety reads + 5 clarification re-asks) and **167 on**, at about $0.0021–0.0026 each. Per turn: **$0.0031 on**, more than the $0.0024 estimated in #76, because of clarification rounds.
- GM: the on arm had more prompt-cache hits (7.7k vs 6.0k cached input tokens per call), so its GM calls were 24% cheaper. That is unrelated to the flag. Don't read the +12% game figure as the flag's cost. The flag's cost is the intent line, about +$0.03 per 10-turn run.
- Persona bots: +$0.016 per run, all from 79 extra persona calls that answer clarifications (about 2.6k input tokens each).
- Batch total (23 runs): **game $2.2875, persona $0.7009, Jev $0.0047.**

## 6. Latency per turn (seconds)

| | Off median | Off p90 | On median | On p90 |
|---|---|---|---|---|
| Intent step | 0.0 | 0.0 | 1.7 (LLM turns) | 4.3 |
| Last submission → GM reply persisted | 5.5 | 6.6 | 6.3 | 12.6 |
| Same, turns without clarification or API error | 5.5 | 6.6 | 6.6 | 12.7 |
| **First submission → GM reply** (incl. clarifications) | **5.6** | **6.8** | **7.7** | **19.4** |

On − off for the median of last submission → reply: +0.8 s (bootstrap 95% CI +0.4…+1.4; turn-level, ignores clustering by run). The GM call itself was faster on the on arm (4.6 vs 5.1 s median, xAI load). Without that the gap would be closer to the 1.7 s intent step. Per persona, first submission → reply on the on arm: Paul 14.2 s median (p90 33 s, max 106 s), Ronny 8.5, Lars 7.6, Lotta 7.2, Hawk 4.9.

## 7. Hangs, failures and odd things

- **No post-intent hangs** in 220 turns (the #79 fix).
- **Off, Lars f62ada63:** timed out at turn 5 (4 turns played). Turn 4 finished normally (heuristic intent). For turn 5 there is no persona call, no `turn.intent` row and no Oban job. The stall came before the turn reached the game, during or around the persona call. That is a different pattern from the one #79 fixed, and it is worth a look if it repeats.
- **On, Ronny 60333425 and Hawk a2a3a008:** `failed/error` with xAI `429 resource-exhausted` ("model is currently at capacity") at 09:05–09:08. GM calls had already been retried on that Ronny run (turns 3, 4 and 6). Not the flag. Both were replaced.
- **On, Lars fa948c45 `stop=dead`:** a legitimate death in combat with two orcs in the nest (turns 8–10). The run played all 10 turns and is counted.
- **Prompt artifact:** "the words leave your mouth" (3 quoted turns) is new and looks like the GM reacting to being handed the player's words verbatim.

## 8. Environment changes made for the test

| When (CEST) | What |
|---|---|
| 08:24 | Playtest **v64** = #76 at `f4ea6ad` (by hand, `fly.playtest.toml`, `GIT_SHA` build arg) |
| 08:53 | `INTENT_CALL_EVERY_TURN=on` via `System.put_env` on the running node (no secret) |
| 09:25 | Flag removed (`System.delete_env`) |
| 09:27 | Playtest **v65** = `main` `ccd5379` via the "Deploy to playtest" workflow (workflow_dispatch). Playtest matches main again; the flag is unset |

Production was not touched. No Fly secrets changed, so [fly-secrets.md](fly-secrets.md) needs no update. #76 is not merged; Fredrik decides.
