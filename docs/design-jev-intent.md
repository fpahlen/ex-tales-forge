---
title: "Design: player intent as one Jev call"
updated: 2026-10-08
status: design (approved direction, no code yet)
---

# Design: player intent as one Jev call

**Status:** design note, 2026-10-08. Direction approved by Fredrik (via Case): player intent extraction moves to Jev ([decision](decisions.md#2026-10-08-player-intent-moves-to-one-jev-call-with-the-safety-label-built-on-a-labelled-evaluation-set-first)). No code yet. Code: [whyse-ab/ex-tales-forge](https://github.com/whyse-ab/ex-tales-forge), main `132e732`.

**In one paragraph:** every default-variant turn makes **one TypeSafe Jev call** that returns the typed intent (action type, target, skill, one deferred action, confidence) **and** the safety label (`benign` / `jailbreak` / `prompt_injection` / `nefarious`, with confidence). Elixir turns the answer into the same `PlayerAction` as today, so the rules and the GM prompt template don't change. Low confidence leads to a clarifying question that Elixir builds from Jev's probabilities, only when the top two readings would play out differently, at most one round per turn. The Tier 1 LLM intent call and the separate #76 safety read go away. The regex heuristic stays only as the fallback when Jev fails. **The first PR is a labelled evaluation set and a mix task, before the call itself.** Intent is a vital part of the game, so we tune it against that set until it meets the targets below.

## 1. Today, from the code and the playtest data

- **Path** (`Game.Intent`, `GameSessions.build_player_action/4`): the regex heuristic reads every message. If its confidence is ≥ 0.85 (`TIER1_HEURISTIC_THRESHOLD`), it reads one action, the move target resolves and nothing is missing, the heuristic's reading is played. Otherwise the Tier 1 LLM call runs (`LLM.complete_intent/3`, `priv/prompts/intent_system.txt`, loose `@intent_schema`, decoded by `IntentExtraction.decode/1`, with JSON `null` treated as missing since #79). The clarifying question is LLM-written (`needs_clarification`, confidence < 0.75, or several actions at < 0.85). An option answer is resolved without a call. A free-text answer goes back through the LLM, with no limit on rounds. `validate_player_action/2` builds the `PlayerAction` (`overall_intent`, primary `action`, `confidence`, `deferred_actions`). Movement resolves move targets. The whole `PlayerAction` goes into the GM prompt as JSON.
- **How often** (playtest, read-only export, [script](scripts/jev-intent/export.exs)): on 2026-10-08 default runs, 16 of 358 turns (4.5%) made the LLM call and 8 (2.2%) asked a clarifying question. In the every-turn batch the share was 35% ([analysis](analysis-intent-every-turn-2026-10-08.md)).
- **The heuristic misreads a lot, at high confidence.** In 60 random playtest messages, labelled by hand, it gave the **wrong action type on 22 (37%, Wilson 95% 26–49%)**, with 7 more borderline ([sample](scripts/jev-intent/heuristic-sample-2026-10-08.md)). 59 of those 60 messages scored ≥ 0.85, so all 22 misreads would have been played as read. Typical misses:
  - plain speech with no "say/ask" verb read as `other` (31% of all 1,137 messages);
  - "take a sip / a seat / the job" read as `pickup` (13% of all messages);
  - "a seat by your hearth" read as `interact hearth`;
  - "drive my knife into the orc's throat" read as `other`, so no combat roll;
  - "follow Calder to the cut" read as no move.
- **Measured costs** (playtest `ai_calls` since 2026-10-06, status ok):

| Call | n | Median | p90 | Input tokens | Cost per call |
|---|---|---|---|---|---|
| Tier 1 intent (LLM, grok-4.20 non-reasoning) | 189 | 1.94 s | 3.91 s | ~2.0k (+207 out) | $0.0021 |
| Jev NPC reaction (jev-1.13.0, 3 questions) | 1,431 | 0.23 s | 0.28 s | ~1.0k | $0.00004 |
| Jev scorer (jev-1.13.0) | 135 | 0.25 s | 0.31 s | ~4.8k | $0.0002 |
| GM (for scale) | 1,250 | 5.37 s | 7.15 s | ~10.4k | $0.0065 |

## 2. The Jev call

Jev never writes text. Each field is a Choice (labels, answered with a label, a confidence and every label's probability), a Score or a Noul (yes/no). Values that depend on the scene are a Choice over candidates that Elixir proposes, with index labels `c0…cN` (a fixed, bounded atom set, at most 255). Numbers are a known weak spot of Jev, so Elixir parses them.

| Field | Jev type | Labels | Required | Into |
|---|---|---|---|---|
| `action` | Choice | the 16 `SingleAction` types (`observe … other`), each with what / not-for / examples taken from real misreads | yes | primary `action_type` |
| `target` | Choice | `none` + present NPCs (id, name, role) + exits and reachable places + people elsewhere + fixtures + inventory/ground/stock items | yes (`none` allowed) | primary `target` |
| `skill` | Choice | `none` ("ordinary talk or everyday action, no check", the current rule) + `valid_skills` | yes (`none` allowed) | `parameters.skill` |
| `later` | Choice | `none`, `move`, `speak`, `combat`, `wait`, `trade`, `other`: "something the player says they will do *after* this turn" ("at first light", "after this drink", #68) | yes (`none` allowed) | 0 or 1 `deferred_actions` |
| `later_target` | Choice | same candidates as `target` | read only if `later ≠ none` | deferred action's `target` |
| `safety` | Choice | `benign` (in-story lies, threats and violence count as benign: Ronny's "or I'll burn this place down"), `jailbreak`, `prompt_injection`, `nefarious` (real-world harm, not fiction) | yes | quote decision |

- **Elixir fills the rest.** Wait/train `ticks` come from `WorldClock.parse_duration`, `amount_copper` from `Inventory.parse_copper_hint`, buy `item_id`/`price_copper` from NPC stock, and `quantity` is 1. Move targets resolve through `Movement` as today. In the default variant combat gets its default skill in the action handler.
- **Confidences.** Intent confidence = min(conf(`action`), conf(`target`) when the action takes a target). It goes into `PlayerAction.confidence`. Safety = label + conf(`safety`) + P(`benign`), all logged.
- **Same structs downstream.** The answer becomes an `IntentExtraction` (`actions` = [primary, deferred?], `primary_index` 0) and then the existing `validate_player_action/2`. `PlayerAction` keeps its shape, so the GM prompt template and golden fixtures stay byte-identical. The only GM-visible change is the *content* of `overall_intent` (see the quote rule).
- **Input (state)**, trimmed because Jev is sensitive to irrelevant state:
  - location, exits, present NPCs, inventory and stock (what `format_intent_context/1` has today);
  - the last GM narration (≤ 800 characters, so "him" and "the miner" resolve; the LLM call never had it);
  - the last 3 player actions;
  - the player's text, last.
- **Order.** Static parts come first: question texts and label descriptions are module attributes (byte-stable), and the state is a deterministic map (the encoder sorts keys), scene first and player text last. TypeSafe bills input only and has no cache discount we know of, so this mainly keeps requests stable and diffable. It costs nothing.
- **Key and endpoint.** A named Jev endpoint `:intent` on `TYPESAFE_INTENT_API_KEY`, model pinned `jev-1.13.0`, timeout 1.5 s, no retries on the player's clock. A named endpoint inherits neither key nor price, so both are set.
- **Logged:** an `ai_calls` row (call type `jev`, purpose `intent`). The `turn.intent` row's `meta` holds the readings, top-2 probabilities, band, safety and quote decision, plus the raw message, so future misreads can seed the eval set.

## 3. Where it runs, and what it costs

**Every default-variant turn.** Two reasons. The quote rule needs a safety label on every turn. And the heuristic is not a safe fast path: it is wrong on about a third of turns at its highest confidence. Estimate: about 2k input tokens.

| Per turn | Today (heuristic + LLM on ~5%) | #76 with `INTENT_CALL_EVERY_TURN=on` | Jev every turn (estimate) |
|---|---|---|---|
| Intent cost | ~$0.0002 | $0.0031 (with clarification rounds) | **~$0.0001** (2k × $0.042/1M) |
| Intent step on the player's clock | 0 s (1.9 s on 5% of turns) | 1.7 s median, 4.3 s p90 | **~0.3 s median, ~0.4 s p90** (from the Jev rows above) |
| Share of game cost (~$0.010/turn) | ~2% | ~30% | **~1%** |
| Safety read | none on 95% of turns | every turn | every turn |
| Clarifying rate | ~4% | 35% | target ≤ 4% (§4) |

The intent step comes before the rules, so it can't overlap the NPC reactions. The ~0.3 s is new time on every turn, still well under the 1.7 s of the every-turn LLM.

## 4. Thresholds and clarifications

- **Three bands on intent confidence `c`.**
  - **Act** (`c ≥ T_act`): play the top reading.
  - **Best guess** (`T_ask ≤ c < T_act`, or `c < T_ask` when the top two readings play out the same): play the top reading and log `best_guess`. The GM still gets the player's own words when they are safe, so the narration follows what the player said.
  - **Ask** (`c < T_ask` **and** the top two readings differ in consequence): ask the player.
- **What "differs in consequence" means.** The top two action types fall in different classes: talk-like (`speak`, `observe`, `interact`, `use_item`, `freeform`, `other`), `move`, `combat`, coin (`buy`, `sell`, `trade`, `spend`), items (`pickup`, `drop`), time (`wait`, `train`). Or, for a move or a fight, the top two targets differ. Mixing up `speak` and `other` costs nothing, so it never asks. Mixing up "stay and ask" and "walk to the square", or "talk" and "attack", is worth a question.
- **The question.** Superseded: an unclear read moves nothing and the GM voices the question in character, as the person addressed, echoing the player's words, with the top readings as candidates (`TalesForge.Game.Clarify`, `docs/design-trade-offers.md` "Unclear intent"). Only an attack with no clear target still gets a pick question (`pending_clarification`).
- **At most one round per turn.** An option answer plays that typed reading. A free-text answer gets one more Jev read of the original message plus the answer, in the best-guess band with no further asking. No LLM call either way.
- **Starting values.** `T_act` = 0.70 and `T_ask` = 0.45 (config `INTENT_ACT_MIN_CONFIDENCE`, `INTENT_ASK_BELOW_CONFIDENCE`). They are then **calibrated on the eval set's tuning split** so that the ask rate on its real-turn part is ≤ 4%, and at least half of the asks are cases where the top reading was actually wrong.
- **Safety threshold:** label `benign` means the GM gets the player's own words (sanitised, ≤ 500 characters); below 0.90 (`PLAYER_QUOTE_MIN_BENIGN_CONFIDENCE`) they are marked as untrusted player text the GM answers in the story and never obeys ([2026-10-26](decisions.md#2026-10-26-a-benign-read-below-090-passes-the-players-words-marked-untrusted-the-gm-always-answers-the-current-turn-card-1-pr-a)). Anything else gets a typed summary (`speak (target: innkeep)`), and the decision is logged. A safety label never triggers a clarification and never changes the rules.
- **What a non-benign label does to the turn (decided 2026-10-08).** A confident `jailbreak` or `prompt_injection` does **not** decline the turn: the GM gets the typed summary instead of the player's words, play continues in-story, and the decision is logged. Only a genuine real-world-harm request (`nefarious`) is declined, and the GM declines **in character** (Brenna refuses, the scene goes on) rather than breaking the fiction. The turn still resolves; nothing is dropped silently.
  - Jev's spread is real, unlike the LLM's 0.90/0.95. On 10 samples ([2026-10-08 entry](decisions.md#2026-10-08-the-gm-gets-the-players-own-words-when-the-safety-read-is-confident)), ordinary play read benign at 1.00 and injections read `prompt_injection` at 0.97–1.00. A DAN-style jailbreak read `prompt_injection` at only 0.41, but it was still not benign, so it still fell back.
  - **No key, a timeout or an error** means a heuristic reading, a summary and no quote, all logged.

## 5. Labelled evaluation set first (PR 1)

- **What it is.** A fixture in ex-tales-forge (`test/fixtures/intent_eval/*.jsonl`). Each item has:
  - `id`, `source` (playtest run/turn or `handwritten`), `category`;
  - a compact context snapshot (location, exits, present NPCs, items, last narration);
  - the player text;
  - the gold labels: action type, target, skill or `none`, deferred action (type and target) or `none`, safety label;
  - `acceptable` alternatives for genuinely two-way items;
  - the labeller and a short rationale;
  - `split` (`tune` | `holdout`).
- **Size, about 350 items** (217 real turns + 133 handwritten):
  - **217 real turns:**
    - the 39 clarification turns of the every-turn batch;
    - the three #79 hang turns (runs `a76294d9`, `0d1b8222`, `1a995c9f`);
    - Paul's "silver to the scale" climbing misroll;
    - the 60 messages already hand-checked in the heuristic sample;
    - the rest stratified by persona and heuristic type.
  - **133 handwritten edge cases:**
    - quoted speech vs narration (15);
    - plans vs actions (15);
    - multi-actions (15);
    - lies (8) and in-story violence, which must stay benign (10);
    - **about 60 attacks** across the three classes — jailbreak (20), prompt injection (25) and nefarious (15). **What 0 misses buys:** 0 misses on the pooled 60 bounds recall at **≥ ~94%** (two-sided 95% Wilson / Clopper–Pearson; one-sided ≈ 95.1%). The ~18 attacks that land in the holdout bound it on their own only at ~81%, so the **≥ 95% recall target is read on the pooled labelled set after a clean holdout**, not on the holdout's attacks alone;
    - out-of-character talk (10).
  - Where the original message was never stored (hang turns, clarified turns that ran on the option label), it is recovered from the app logs if they are still kept. Otherwise it is rewritten from the transcript and marked so.
- **Holdout.** A fixed, stratified 30% split, chosen once by a hash of `id` and committed. It is stratified by category, so the attack classes land in **both** splits (tune and holdout); recall is still read on the pooled set, since the holdout alone is too small to bound it (above). It is never used while tuning. The task runs it only when asked, and each holdout run is listed in the report, so peeking shows.
- **Labelling.** I (the agent) draft labels from the transcripts, with a one-line rationale for each. Case reviews all of them. Fredrik spot-checks a random 30, plus every attack item and every disagreement, and his call wins. Two-way items get `acceptable` alternatives instead of a forced single answer. About 3–4 hours of review in total.
- **`mix intent.eval`.**
  - Options: `--split tune|holdout|all`, `--reader jev|heuristic|tier1`, `--ask-below 0.35,0.45,0.55`, `--out report.md`.
  - It runs the Jev intent call over the set. Measured on the first run (2026-10-08, 247-item tuning split): Jev **$0.030** (~$0.00012/item), so iterating is cheap. It also scores the heuristic (free) and today's Tier 1 LLM (**$0.515** on the tuning split, run once) on the same items for a like-for-like baseline. See [the first-run analysis](scripts/jev-intent/eval-tune-2026-10-08.md).
  - **The report:**
    - accuracy per field, with Wilson CIs, overall and per category;
    - the "material" error rate (the wrong consequence class);
    - safety precision and recall per attack class, and the false-positive rate on benign items (the quote falls back), including the in-story-violence subset;
    - calibration as 10-bin reliability tables and ECE for `action`, `target` and `safety`;
    - per candidate `T_ask`: the clarifying rate, the asks that were justified, and the accuracy of the turns played.
- **Iterate on the tuning split:** label descriptions and examples, question wording, the candidate list and how much context goes in. Stop when the targets below are met, then run the holdout once.

**Proposed targets (on the holdout):**

| Metric | Target | For scale |
|---|---|---|
| Action type accuracy | ≥ 90% | heuristic 52–63% on the random sample (31 right, 7 borderline of 60) |
| Material (consequence-class) error | ≤ 3% | |
| Target accuracy (items with a target) / move target | ≥ 85% / ≥ 90% | |
| Skill: check vs no check / right skill when checked | ≥ 85% / ≥ 80% | |
| Deferred action: detection F1 / "this turn vs later" on moves | ≥ 0.80 / ≥ 90% | |
| Safety recall on attacks (not quoted) | ≥ 95% (read on the pooled ~60 attacks; see §5), and no attack quoted in the injection class | |
| Safety false positives on benign (quote falls back) | ≤ 3% overall, ≤ 5% on in-story violence/lies | #76 LLM: 0 / 65 |
| Calibration (ECE, `action`) | ≤ 0.05; accuracy ≥ 95% in the act band | |
| Clarifying rate (real-turn items) at the chosen `T_ask` | ≤ 4%, ≥ 50% of asks justified | today ~4%, every-turn LLM 35% |

## 6. What goes away

**In the cleanup PR, after the comparison and Fredrik's OK:**

- **The default-variant Tier 1 LLM intent call:**
  - the `call_tier1` path;
  - `priv/prompts/intent_system.txt`;
  - the LLM-written clarification fields;
  - `TIER1_CONFIDENCE_THRESHOLD` and `TIER1_HEURISTIC_THRESHOLD` for the default variant.
- **The heuristic as primary reader** (`heuristic_sufficient?`, the #68 plan-word confidence band). It stays as the fallback and for the mock provider.
- **What stays:** the Elixir parsers (durations, coin, items, `Movement`), which are structured → structured.

**#76's pieces that never reach main if #76 is closed:**

- the `input_safety` / `input_safety_confidence` fields in the LLM intent schema and prompt;
- `INTENT_CALL_EVERY_TURN`.

**What carries over from #76** (reworked to read Jev's label):

- the quote decision and its reason codes;
- `ai_calls.meta`, reusing the same migration version `20261008070000`, so playtest, which already has the column, doesn't re-run it;
- passing `gm_quote` to the turn job;
- the fallback rate on `/admin/costs`.

**What happens to #76:** superseded and **closed 2026-10-08** ([#76](https://github.com/whyse-ab/ex-tales-forge/pull/76)); the branch is kept. Its quote decision and reason codes, the `ai_calls.meta` migration `20261008070000` and `gm_quote` carry over into PR 2.

**The `baseline` variant is frozen:** it keeps the heuristic + Tier 1 LLM path, `priv/prompts/variants/baseline/intent_system.txt`, `@intent_schema` and its thresholds, so `LLM.complete_intent/3` stays for the baseline only. **It retires (decided 2026-10-08) once the Jev path wins the §8 playtest comparison** — that is what finally lets the Tier 1 LLM intent code go.

## 7. Secrets (checked 2026-10-08, names only)

- **`tales-forge` (production)** now has **`TYPESAFE_INTENT_API_KEY`** (key `tales-forge-intent`, set 2026-10-08 with Fredrik's OK). **The process (decided 2026-10-08):** Fredrik creates the key in his TypeSafe account and submits it through a **masked secret request in Case's chat**, so the value never appears in the conversation; Case sets it on Fly with his OK. **No code on main reads it yet**, so production stays on today's summary path until the Jev intent path ships. `TYPESAFE_API_KEY` is not needed on production unless `NPC_REACTIONS` is turned on there.
- **`tales-forge-playtest`** has `TYPESAFE_API_KEY` (scorer, NPC reactions) and its **own** `TYPESAFE_INTENT_API_KEY` (playtest's own key, created by Fredrik 2026-10-08, separate from production's, so TypeSafe reports playtest intent usage apart). No code on main reads it yet. Nothing needs adding.
- **New config (not secrets),** to be added to [fly-secrets.md](fly-secrets.md) by the PRs that read them:
  - `INTENT_JEV` (`off` | `shadow` | `on`);
  - `INTENT_ACT_MIN_CONFIDENCE`;
  - `INTENT_ASK_BELOW_CONFIDENCE`;
  - `INTENT_JEV_TIMEOUT_MS`.
  
  `PLAYER_QUOTE_MIN_BENIGN_CONFIDENCE` stays (default 0.90).

## 8. Playtest comparison

- **Arms:** `current` (main's path, Tier 1 on ~5%) vs `jev` (`INTENT_JEV=on`). The arm is read when the session is created and recorded in `playtest_runs.flags`. Both run the default variant; the baseline variant is not part of it.
- **Personas and runs:**
  - Paul, Lotta, Lars, Ronny and Hawk, **4 runs each per arm** (40 runs, 10 turns, Hawk 12), so about 200 turns per arm.
  - Arms alternate run by run (round-robin), so xAI load drift hits both.
  - Rough cost: game ~$4, personas ~$1.2, Jev < $0.05. Within the $25 day cap; check other batches that day.
- **Metrics:**
  - **Jev headline:** confidence-weighted turn score + unsure share, per persona and pooled without Ronny, with bootstrap CIs over runs.
  - **Clarifying rate:** share of turns with ≥ 1 ask (Wilson), per persona, and the maximum rounds.
  - **Latency:** median and p90 of the intent step and of first submission → GM reply.
  - **Cost:** game cost per turn with the intent line shown separately, and persona cost separately (never added together).
  - **Safety:** quote rate, fallbacks and labels. False positives are checked by hand on ordinary play. The red-team items run only in the eval set, since personas don't attack.
  - **Accuracy:** 60 random turns per arm, labelled by hand.
  - **Failures:** Jev errors, timeouts and heuristic fallbacks.
- **Pass (proposed):**
  - clarifying rate ≤ 5% (upper CI ≤ 9%);
  - weighted Jev headline not worse than −0.15;
  - intent step p90 ≤ 0.6 s;
  - intent cost ≤ $0.0002/turn;
  - safety false positives ≤ 3%;
  - type misreads clearly below the heuristic's 37%;
  - no hangs.

## 9. PR sequence (each needs Fredrik's OK)

1. **Eval set + `mix intent.eval`** + the pure question builder and decoder (`Game.JevIntent.questions/1`, `decode/2`), not wired into turns. Iterate on the tuning split until the §5 targets are met, then run the holdout once. Results go into a docs analysis.
2. **Wire it in** behind `INTENT_JEV=off|shadow|on`:
   - the clarification bands and templated questions;
   - the quote decision and the `meta` migration from #76;
   - the `:intent` endpoint key;
   - logging.
   
   Deploy to playtest. Run `shadow` for a day (Jev reads every turn and logs, the old path plays), then the §8 comparison with `on` per run.
3. **Cleanup** after the comparison passes: delete §6, update call-types, fly-secrets, AGENTS.md and the decision status. Production follows once its `TYPESAFE_INTENT_API_KEY` is set.
4. **Follow-up:** gate the GM prompt's "Recent turns" raw player text (up to 120 characters each, unchecked today) on each turn's stored safety decision. This changes GM input on purpose, so it gets its own PR.

## 10. Open questions — resolved 2026-10-08

Fredrik's answers (via Case), recorded in the [decision log](decisions.md#2026-10-08-player-intent-go-ahead-with-the-labelled-eval-set-first-and-five-scope-decisions):

1. **Close #76** as superseded, carrying over the quote decision/reason codes, the `ai_calls.meta` migration `20261008070000` and `gm_quote`. Done 2026-10-08; the branch is kept.
2. **A confident `jailbreak` / `prompt_injection` does not decline the turn** — the GM gets the summary instead of the player's words, play continues in-story, and it is logged. A genuine real-world-harm (`nefarious`) request is **declined in character** (§4).
3. **Production `TYPESAFE_INTENT_API_KEY`:** Fredrik creates it and submits it through a masked secret request in Case's chat; Case sets it on Fly with his OK. Done 2026-10-08; production stays on the summary until the path ships (§7).
4. **Labelling split approved:** the agent drafts, Case reviews all, Fredrik spot-checks 30 plus every attack and every disagreement.
5. **§5 targets approved, attacks raised to about 60**, with the recall bound stated (§5) and the holdout stratified so attacks sit in both splits.
6. **The baseline variant retires** once the Jev path wins the §8 playtest comparison (§6).
