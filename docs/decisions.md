---
title: Decision log
updated: 2026-10-09
---

# Decision log

Decisions made by the founders. Newest at the top. Each entry: date, decision, why, link to details. Changing a decision means adding a new entry that supersedes the old one.

Open questions waiting for a decision live in the [decision queue](../decisions/README.md); once decided, they are recorded here.

Ideas we may pick up later, not yet decided, live in [Future ideas](future-ideas.md).

## 2026-10-09: Fresh full playtest batch as the new baseline

- **Decision (Fredrik):** run a fresh full persona batch on playtest with the new scoring, because much of the system has changed: Jev intent on, one place per thing (#85), the Tinjacks coming to the fighter (#86), gesture variety (#87), forge and cottage hooks (#88), the phone layout (#89) and the costs pages (#90). It becomes the new baseline.
  - **Setup:** the same shape as the previous full batch (`post-rework-2026-10-08`): Paul, Hawk, Lotta, Lars and Ronny, 5 runs each, round-robin, 10 turns (Hawk 12), variant default, series `full-2026-10-09`. Sessions run with `INTENT_JEV=on`.
  - **Scoring:** the current Jev scorer, the sharpened rubrics and the confidence-weighted headline.
  - **Budget:** abort above $8 (the playtest day cap is $25). Persona bot cost is reported apart from game cost.
- **Why:** with this many changes, comparing against older batches piece by piece would mislead; one fresh batch gives a clean reference for the persona rework.
- **Status:** running (started 2026-10-09 11:10). The analysis goes in [Analysis: full batch 2026-10-09](analysis-full-batch-2026-10-09.md).

## 2026-10-09: Jev intent on for playtest and production

- **Decision (Fredrik):** turn the Jev intent read on (`INTENT_JEV=on`). The [persona comparison](analysis-intent-compare-2026-10-09.md) gave a quality tie (Jev session score 3.98 with intent on against 3.96 off; the confidence interval includes 0) and a clear latency win (intent p95 1641 ms down to 308 ms, 100% of reads within 1.5 s). That is good enough: we can't refine further until the personas are refined.
  - **Playtest:** switched 2026-10-09 (release v76).
  - **Production:** first held for Fredrik's explicit OK; he gave it the same day (2026-10-09 11:00) and production was switched (release v85).
  - Calibration tightening (the generous lifts and zero clarifying questions in the comparison) follows as a separate PR; it does not block this.
  - The baseline code (Tier 1 LLM intent) is kept until after the persona rework and the new full batch.
- **Why:** same quality, much faster turns, cost-neutral, and refining further needs better personas first.
- **Status:** live on both apps since 2026-10-09 (playtest v76, prod v85). New default-variant sessions pin `on`; older sessions keep their mode. See [Fly secrets](fly-secrets.md).
- **Details:** [Intent comparison: INTENT_JEV on vs off (2026-10-09)](analysis-intent-compare-2026-10-09.md), [Design: player intent as one Jev call](design-jev-intent.md)

## 2026-10-09: The /team founders' presentation page copy is approved

- **Decision (Fredrik):** the copy for the `/team` founders' presentation page in [docs/team-page/content.md](team-page/content.md) (commit `0069849`) is approved. Build the page from it.
- **Why:** the content brief has been through its tone revision (one crew, the current setup as a starting point, a founder's OK, the playtest-first flow, a closing "together" section).
- **Status:** approved; a PR to build the page follows (needs Fredrik's OK like any code change).
- **Details:** [Team page content](team-page/content.md)

## 2026-10-09: Deploy order: playtest first, then production

- **Decision (Fredrik):** a merge to `main` deploys to playtest first. Gentry (the QA bot) and the playtest batch check it there, and only then does it go to production. Production still needs Fredrik's OK.
- **Why:** today `main` deploys to production first and playtest after, so production meets a change before anything has tested it.
- **Status:** decided; workflow change [ex-tales-forge PR #91](https://github.com/whyse-ab/ex-tales-forge/pull/91) open (not merged). [Environments](environments.md) describes the new flow; until #91 merges, `main` still deploys production first.
- **Details:** [Environments: how a change gets to production](environments.md#how-a-change-gets-to-production)

## 2026-10-09: Costs pages: playtest shows only playtest-run costs, production shows all costs

- **Decision (Fredrik):** fix the `/admin/costs` pages so each app shows the right costs. For now they cover AI calls only (Grok, Jev and TypeSafe); Fly hosting may be added later.
  - **Playtest app:** shows only the cost of playtest runs: the persona bot, the GM, Jev scoring and Jev intent on playtest-run sessions. Other calls on playtest, such as manual play, get their own line and stay out of the runs' total.
  - **Production app:** shows all costs. It has its own numbers, plus a separate Playtest section read live from the playtest app through a small authenticated internal endpoint. No data is copied. One grand total goes on top. If playtest is down, the section says "playtest unavailable" and production's numbers still show.
  - Persona bot cost is always shown apart from game cost.
  - **Auth:** the endpoint (`GET /internal/costs`) answers only on playtest and reuses the existing shared secret `COSTS_PEER_TOKEN`, which is already set on both apps. No new secret. Production reads playtest's URL from config, so `COSTS_PEER_URL` is no longer read once the PR is deployed. The read has a 2 s timeout.
- **Why:** each thing lives in one place (playtest-run costs live on playtest and are read from there), and production gives full cost visibility on one page.
- **Status:** live. [ex-tales-forge #90](https://github.com/whyse-ab/ex-tales-forge/pull/90) merged 2026-10-09 with Fredrik's OK (`dd5dc7e`, final main after #86–#90; prod v84, playtest v75). Checked: playtest `GET /internal/costs` answers 401 without a token, production's `/internal/costs` is 404, and production's `/admin/costs` goes to sign-in without a session.

## 2026-10-09: Jev intent fallback and per-session latency probes

- **Decision (Fredrik):** the Jev intent call gets a fallback model from a different provider. Provider latency is checked once when a session starts, not with continuous pings.
  - Each provider in use (TypeSafe/Jev, the GM model and the fallback) gets a tiny probe call, and the game routes on those timings.
  - If Jev is slow, the session uses the fallback directly.
  - If the GM is slow, the game shows an in-fiction line (e.g. "The GM is a bit tired today...") instead of a spinner.
  - The per-turn timeouts stay as the safety net.
  - Probe timings are recorded so they can appear on the costs/status page later.
- **Why:** resilience and latency. One slow provider shouldn't stall a turn, and the player should see the game's voice, not a spinner.
- **Status:** planned. The spike waits for provider accounts (Groq, Anthropic, Google). It builds on the Jev wrapper and provider config refactors (steps 1 and 2 in the [architecture baseline](architecture-baseline-2026-10-09.md#5-suggested-order-for-refactor-prs)).
- **Details:** [Architecture baseline: ex-tales-forge main at 2f27ff1](architecture-baseline-2026-10-09.md)

## 2026-10-09: Pragmatic Programmer architecture review on every merge to ex-tales-forge main

- **Decision (Fredrik):** every merge to `main` in ex-tales-forge gets an architecture review in the spirit of *The Pragmatic Programmer*: DRY, orthogonality, broken windows, reversibility, and our own rules (call types, state written only by Elixir rules and Jev, each thing lives in one place, docs, specs and tests for every module). The starting point is the baseline review of `main` at `2f27ff1`. The refactors it found are queued in its suggested order, as separate PRs: (1) one Jev client plus correct cost source, (2) LLM provider config, (3) an intent reader behaviour and pipeline out of `GameSessions`, (4) error-handling cleanup, (5) a typed turn/intent context and no Repo in `Game.*`, (6) splitting `Inventory`, (7) Crossroads as a full pack, (8) GM memory and summary writes moved to Jev or Elixir, then ongoing cleanup.
- **Why:** the intent pipeline and the AI-call plumbing grew by copy-paste and flags, so the next changes (a fallback intent provider, per-session latency probes) would touch many places. Reviewing each merge against a baseline keeps that from coming back.
- **Status:** baseline written; no refactor started. Each refactor PR needs Fredrik's OK like any code change.
- **Details:** [Architecture baseline: ex-tales-forge main at 2f27ff1](architecture-baseline-2026-10-09.md)

## 2026-10-08: Each thing lives in one place: surveys on production, playtest runs on playtest

- **Decision (Fredrik, via Case):** each thing lives in one place. Founder surveys live only on production (`/admin/survey`, `/admin/surveys/*`), and playtest runs live only on playtest (`/admin/playtest/*`). Each app redirects those pages to the other app, and its admin nav links there. No survey answers are stored on playtest and no playtest data on production: saving a survey on playtest is refused, and the persona runner, series and scorer refuse to start on production. The app knows which one it is from `FLY_APP_NAME`; the two base URLs are in config, so there are no new secrets.
- **Why:** looking at playtest, Fredrik thought his survey answers had vanished. It was a false alarm: they were on production. With one source for each thing, that confusion can't happen and the data isn't split between two databases.
- **Status:** live. [ex-tales-forge #85](https://github.com/whyse-ab/ex-tales-forge/pull/85) merged 2026-10-09 with Fredrik's OK (main `2f27ff1`, prod v82, playtest v73). Checked with curl: on playtest, `/admin/survey` and `/admin/surveys/*` redirect to production; on production, `/admin/playtest/*` redirects to playtest, and `/admin/survey` stays put (it goes to sign-in). PR preview apps, which aren't built yet, would count as production by name; revisit that when they're built.

## 2026-10-08: Playtests show character changes (PC and NPCs)

- **Decision (Fredrik, via Case):** each admin playtest run page shows how the player character and every NPC changed between the start and end of the run, with a per-turn timeline linking to the turns. The playtest index gets a per-batch summary. The view shows only what we store today, and says "not tracked yet" for the rest instead of inventing it.
  - **Shown:** NPC location, mood, stance toward the player and the latest Jev feeling, relationship score, current concern, and the memories added (per turn, with who wrote them). For the player character: location, wounds, coins, learning points and skill improvements.
  - **Not tracked yet:** NPC feelings toward other NPCs, Maslow level and concerns (written once, never updated), OCEAN-filtered memory (no personality filter exists yet), the player character's memories and mood, and per-turn Jev reaction values (only the latest reaction is kept).
  - **Batch metrics:** share of runs where an NPC's attitude to the player changed, NPCs whose attitude changed per run, memories added per run, and NPCs with any change per run (median and mean). The [Jev compare scripts](scripts/jev-compare/compare.py) export the same numbers.
- **Why:** to judge whether play leaves a mark on the characters, we need to see it per run and per batch. Today that state is scattered (npc_instances, characters, world_state, session events, turns, ai_calls). One read-only module (`TalesForge.Playtest.CharacterChanges`) gathers it now and will switch to the world event log once [WORLD_STATE](design-stateful-world.md) lands. That is also where the "not tracked yet" gaps get filled.
- **Status:** live. [ex-tales-forge #83](https://github.com/whyse-ab/ex-tales-forge/pull/83) merged 2026-10-08 with Fredrik's OK (main `c98b482`, prod v80, playtest v70). Reads today's scattered state; switches to the world event log once WORLD_STATE lands.
- **First numbers (2026-10-08 batches):** the attitude share is 100% in all three series, so NPCs whose attitude changed per run is what separates them (median 3 with intent off, 2 with intent on, 2 after the rework). Memories per run (median): 31, 24 and 21.

## 2026-10-08: Stateful world: four design answers

- **Decision (Fredrik, via Case):** answers to questions 1–4 of the [stateful world design note](design-stateful-world.md#11-questions). Questions 5–8 (trace fading, world pace, snapshot cadence, shared worlds) wait for measurements.
  1. **One process per world; entities are plain data.** An NPC that needs to think something through gets a short-lived Task when it matters (Jev calls, answer returned to the world as an event). If a world outgrows one process later, it splits by region, never per entity. This replaces the per-character agent of [Character plan](plan-unify-character.md) phase 3.
     - *Why:* a turn touches several entities and must commit as one; pure functions over an ordered log replay the same way every time; only the world has a clock of its own; and idle data costs nothing.
  2. **The GM gets the state snapshot plus the last 1–2 turns.**
     - *Why:* the snapshot keeps the facts straight, and the recent turns keep the prose continuous in voice and thread. The GM no longer carries the world in its own summary, which is where the drift came from.
  3. **Commit before the GM call.** The rules and Jev decide what happened, and it is saved first. If the GM call fails, the world has still changed and only the prose is retried. A retry never re-rolls dice or re-asks Jev. The player sees the result in plain words until the narration arrives, with a retry button if the GM keeps failing.
     - *Why:* the outcome belongs to the rules, not to the narrator. A failed GM call no longer loses the player's action, and a shared world is never held for the length of a GM call.
  4. **Only the rules (Elixir) and Jev write events.** The GM writes prose only. The GM's `npc_memory_updates` and `World.Extract` become Jev calls or are dropped: memories come from events and the Jev judgements, and promises from a Jev reader with fixed promise kinds. Free-text facts invented in the prose are no longer recorded.
     - *Why:* the [call-type rule](call-types.md): structured state from an LLM is a smell, and Jev is cheaper (~$0.0001 against ~$0.001 for the extraction call).
- **Order:** the first code PR (`WORLD_STATE=shadow`) comes after [Jev intent](design-jev-intent.md) PR 2. Each code PR needs Fredrik's OK.
- **Details:** [Design: persistent world state, updated with the answers](design-stateful-world.md) (§4 processes, §6 commit and event writers, §9 prompt layout, §10 migration)

## 2026-10-08: Design note: persistent world state at the core of the turn loop

- **Decision (Fredrik, via Case):** write a design note on making persistent world state the core of the turn loop. An "apply consequences" step goes between the rules and the prose. The turn's result becomes events sent to everything it touched (people, the player character, places, factions), each updates its own state in plain Elixir, Jev is used only for judgements, and the GM gets a snapshot of the current state instead of the history. The world keeps moving on world time.
- **What the note recommends:**
  - **Processes:** one `World.Instance` process per world; people, places, items and factions are plain data inside it.
  - **Persistence:** an event log (extending `session_events`) plus snapshots every 25 events.
  - **First step:** a shadow mode behind `WORLD_STATE=shadow` that changes nothing the GM sees.
  - **Cost:** no new LLM call on the hot path.
- **Why:** today the state is spread over several copies (mood in four places), places hold no state, nothing moves between turns, and the GM carries the continuity itself, which is where the drift comes from. One state model with recorded causes gives the [living world](design-world-agents.md#living-world-design-to-try) and the Tinjacks something to run on.
- **Status:** design note written, no code. Questions 1–4 were answered on 2026-10-08 ([Stateful world: four design answers](#2026-10-08-stateful-world-four-design-answers)); questions 5–8 wait for measurements. The first PR (`WORLD_STATE=shadow`) comes after Jev intent PR 2.
- **Details:** [Design: persistent world state at the core of the turn loop](design-stateful-world.md)

## 2026-10-08: Several founder surveys at once, as tabs, from docs JSON with an active flag

- **Decision (Fredrik, via Case):** `/admin/survey` shows one tab per active survey, each with the signed-in founder's status (not started, in progress, done). Surveys are discovered from the `docs/*survey*.json` files in tales-forge-docs, and each file's `"active": true/false` flag decides whether it is a tab. Adding or closing a survey is a docs commit (60 s cache, or "Sync from repo"), with no deploy. Closed and inactive surveys leave the tabs but stay readable in the admin, with results, CSV and Markdown. A new `/admin/surveys` page shows every founder's status per survey. founder-survey-3 keeps its slug, results and answers (`active: true`), and the `priv/surveys` snapshots stay the fallback for both surveys.
- **Why:** the intent survey and founder survey 3 are open at the same time. Founders need to see both and where they stand on each, and opening or closing a survey shouldn't need a code change.
- **Status:** live. [ex-tales-forge #82](https://github.com/whyse-ab/ex-tales-forge/pull/82) merged 2026-10-08 with Fredrik's OK (main `410b132`, prod v79, playtest v69); prod lists founder-survey-3 and founder-survey-4-intent as active tabs.
- **Details:** [survey file format](https://github.com/whyse-ab/ex-tales-forge/blob/main/priv/surveys/README.md)

## 2026-10-08: Founders label vague player inputs in a second survey (tune split only); the answers set labels and the ask band

- **Decision (Fredrik, via Case):** the founders say what ambiguous player inputs mean in a short second survey, [founder survey 4](founder-survey-4-intent.md) (`founder-survey-4-intent`, about 10 minutes, at `/admin/surveys/founder-survey-4-intent`).
  - **Items:** 12 genuinely ambiguous items from the intent eval set's **tune split only**; holdout items are never used (the selection script fails on any). No attack or safety items.
  - **Question format (Fredrik's addendum):** one question per item with 3–4 plain-language readings drawn from the gold label, the `acceptable` alternatives and Jev's readings, deduped and shuffled, never marking which is gold; plus "Unclear, the game should ask the player", "Something else" with a free-text field, and an optional comment. Every reading maps back to structured labels (action, target, now or later, deferred action and target), carried in the survey JSON (`option_labels`) and in `mapping.json`.
  - **Use:** the majority reading becomes gold, a minority reading becomes acceptable, and an Unclear win or no majority marks the item as one the game should ask about. "Something else" answers are reviewed by hand. Per-item founder agreement is reported and feeds the ask-band (`T_act`/`T_ask`) calibration.
- **Why:** Case's and Fredrik's labels settle most items, but on genuinely two-way inputs the honest gold is what players mean, and where players disagree the game should ask rather than guess. Using the tune split keeps the holdout unseen.
- **Status:** live as the second tab on `/admin/survey` since [ex-tales-forge #82](https://github.com/whyse-ab/ex-tales-forge/pull/82) merged 2026-10-08 (prod v79), with each option's labels in the results and CSV. Answers are applied later per `docs/scripts/survey-intent/apply_answers.md`; fixture changes go in a PR after Fredrik's OK.
- **Details:** [survey](founder-survey-4-intent.md), [how answers become labels](scripts/survey-intent/apply_answers.md), [selection and build scripts](scripts/survey-intent/), [Design: player intent as one Jev call](design-jev-intent.md)

## 2026-10-08: Player intent go-ahead with the labelled eval set first, and five scope decisions

- **Decision (Fredrik, via Case):** go ahead with the [Jev intent plan](design-jev-intent.md) and the labelled-evaluation-set-first approach, with five scope answers. This builds on (does not replace) the entry below.
  1. **Close #76** as superseded by the Jev intent design. Its quote decision and reason codes, the `ai_calls.meta` migration (version `20261008070000`) and passing `gm_quote` to the turn job all carry over into the wiring PR. The branch is kept.
  2. **A confident `jailbreak` or `prompt_injection` does not decline the turn.** The GM gets the typed summary instead of the player's own words, play continues in-story, and the decision is logged. Only a genuine real-world-harm request (`nefarious`) is declined, and the GM declines **in character** rather than breaking the fiction.
  3. **Production `TYPESAFE_INTENT_API_KEY`:** Fredrik creates the key in his TypeSafe account and submits it through a **masked secret request in Case's chat** (the value never appears in the conversation); Case sets it on Fly with his OK. Until the path ships, production stays on the summary. (Done 2026-10-08: key `tales-forge-intent` set on production; playtest has its own separate key. See [fly-secrets](fly-secrets.md).)
  4. **The §5 targets are approved, with attacks raised to about 60.** The report states what recall bound "no misses in 60" supports (0 misses on the pooled 60 bounds recall at ≥ ~94%, two-sided 95%; the ~18 holdout attacks alone bound it only at ~81%, so the ≥ 95% recall target is read on the pooled set after a clean holdout). The 30% holdout stays stratified so the attack classes sit in **both** splits.
  5. **The frozen `baseline` variant retires** once the Jev path wins the §8 playtest comparison — that is what finally lets the Tier 1 LLM intent code go.
- **Labelling split (approved):** the agent drafts every label (marked `reviewed: false`), Case reviews all of them, and Fredrik spot-checks a random 30 plus **every attack item and every disagreement**; his call wins. Two-way items carry `acceptable` alternatives.
- **Why:** these settle the open questions the design note left for Fredrik (§10). Declining only real-world harm keeps the game playable under adversarial play while still refusing genuine harm; reading recall on the pooled set is the honest bound given a small holdout; retiring the baseline only after the comparison keeps a safe rollback until the Jev path is proven.
- **Status:** approved. PR 1 ([#81](https://github.com/whyse-ab/ex-tales-forge/pull/81): the labelled eval set of 350 items, reviewed by Case and spot-checked by Fredrik, plus `mix intent.eval`; not wired into turns) merged 2026-10-08 with Fredrik's OK (main `0c727a8`, prod v78, playtest v68); #76 is closed. Tune split after review: action 95.1%, safety 42/42 with 0 false positives; deferred and calibration are the tuning targets. Each later PR still needs Fredrik's OK. PR 2 ([#84](https://github.com/whyse-ab/ex-tales-forge/pull/84): tune-split tuning, the calibration map, and `INTENT_JEV=off|shadow|on` wiring; tune numbers in [the v2 eval note](scripts/jev-intent/eval-tune-2026-10-08-v2.md)) merged 2026-10-08 with Fredrik's OK (main `36797eb`, prod v81, playtest v72). `INTENT_JEV=shadow` set on playtest 2026-10-08 (Fredrik's OK); prod off. Next: a day of shadow, then the persona comparison, then the holdout run once on frozen tuning before prod.
- **Details:** [Design: player intent as one Jev call](design-jev-intent.md), [heuristic sample](scripts/jev-intent/heuristic-sample-2026-10-08.md), [Fly secrets](fly-secrets.md)

## 2026-10-08: Player intent moves to one Jev call with the safety label, built on a labelled evaluation set first

- **Decision (Fredrik, via Case):** player intent extraction moves to Jev. One TypeSafe Jev call per default-variant turn returns the typed intent and the safety label together:
  - **Intent:** action type, target, skill, deferred action, confidence.
  - **Safety label:** `benign`, `jailbreak`, `prompt_injection` or `nefarious`, with its confidence.
  - **What it replaces:** the Tier 1 LLM intent call and the separate safety read of ex-tales-forge #76.
  - **The regex heuristic** stays only as a fast path or a fallback, and only if it still earns its place. The design note proposes fallback only.
  - **Low Jev confidence** leads to a clarifying question, not another LLM call. The clarifying rate must stay near today's ~4%.
  - **Proof:** a playtest comparison against the current path (Jev score, clarifying rate, latency, cost).
  - The player-quote rule is unchanged (benign at ≥ 0.90 means the GM gets the player's own words, otherwise the summary; logged). The `baseline` variant is frozen and keeps the old path. GM prompts stay byte-identical.
- **Addendum (Fredrik, via Case, same day): a labelled evaluation set comes first.** Intent is a vital part of the game, and it's fine to spend considerable effort tuning it.
  - **The set:** player inputs with known correct intent (action type, target, skill, deferred action, safety label), kept as a fixture in ex-tales-forge.
  - **Seeds:** real playtest turns (the 39 clarification turns of the every-turn batch, the three #79 hang turns, Paul's "scale" misroll) plus handwritten edge cases: quoted speech vs narration, plans vs actions, multi-actions, lies and in-story violence (Ronny's threats are benign), jailbreak and injection attempts.
  - **The mix task:** it runs the Jev call over the set and reports accuracy per field, safety precision and recall, calibration (reliability bins, ECE) and the clarifying rate at candidate thresholds.
  - **Holdout:** a fixed ~30% split, never used while tuning.
  - The Jev input is iterated until the proposed targets are met. The eval set and the mix task are the **first PR**, before the call itself.
- **Supersedes:** [Clarification: the safety read is part of the intent call, not a separate Jev call](#2026-10-08-clarification-the-safety-read-is-part-of-the-intent-call-not-a-separate-jev-call). The safety read is still part of the intent call, but that call is now Jev, not the Tier 1 LLM. `INTENT_CALL_EVERY_TURN` is no longer needed. That entry is unchanged otherwise.
- **Why:**
  - **The call-type rule** ([call types](call-types.md)): unstructured in, structured out is a Jev call, and structured output from the LLM is a smell.
  - **The every-turn batch** ([analysis](analysis-intent-every-turn-2026-10-08.md)): putting the LLM intent call on every turn raised clarifications to 35% of turns (4% before; Paul 65%, up to 5 rounds). It added about $0.0029 per turn (~30% of game cost), 1.7 s median / 4.3 s p90 on the intent step, and +63% persona cost. Its LLM safety confidence only ever took the values 0.90 and 0.95.
  - **Jev on playtest** costs ~$0.00004 per call at 0.23 s median for the NPC reactions. An intent call is estimated at ~$0.0001 and ~0.3 s.
  - **The heuristic** gave the wrong action type on 22 of 60 random playtest messages (37%), all at confidence ≥ 0.85, so it is not a safe fast path.
- **Status:** approved, design note written, no code yet. The first PR is the eval set and `mix intent.eval`. Each PR needs Fredrik's OK. #76 is likely superseded; closing it is Fredrik's call. Production has no TypeSafe key; it needs a `TYPESAFE_INTENT_API_KEY` before this path is turned on there.
- **Details:** [Design: player intent as one Jev call](design-jev-intent.md), [heuristic sample](scripts/jev-intent/heuristic-sample-2026-10-08.md), [Fly secrets](fly-secrets.md)

## 2026-10-08: Paul's level 5 needs a consequence of his own choice or discovery

- **Decision (Fredrik, via Case):** on Paul's 4-vs-5 border, a vivid answer or a new fact is a 4. A 5 requires a consequence of his own choice or discovery, where the world reacts: for example an NPC acts on what he learned, or a door opens because he asked.
  - Surprise, callback and NPC goals no longer count as level-5 evidence for Paul. Lotta's level 5 is unchanged.
  - Paul's rubric version: `jev-affect-v1-df3c861`, replacing the first sharp version `7862783` from the entry below. GM prompts and the `baseline` variant are untouched.
- **Why:** on the first sharp version Jev split about 0.42 / 0.45 between levels 4 and 5 on Paul's unsure turns, which were 72% of his baseline turns. His typical turn is an open question answered with vivid new facts, and that fits both "an answer" (4) and "a surprise" (5).
- **Result:** the re-score ran on the box from existing transcripts: Paul's 13 baseline and 5 post-rework runs, 18 Jev calls, $0.0062.
  - **Unsure share** (confidence < 0.7): 33% on the baseline and 48% post-rework, against 51% / 46% on #69 and 72% / 74% on the first sharp version.
  - **Weighted headline:** 4.41 / 4.27.
  - **Turn weighted delta:** −0.14 (CI −0.24…−0.03). The session delta is −0.01 (CI −0.09…+0.08).
  - **Post-rework stays less settled:** its threat-heavy turns, where the world reacts but not to his delight, still split.
- **Status:** approved; [ex-tales-forge #80](https://github.com/whyse-ab/ex-tales-forge/pull/80) merged 2026-10-08 09:31 (merge commit `132e732`, Fredrik approved 09:23) and deployed: production v76, playtest v66. New Paul scores use `jev-affect-v1-df3c861`; older scores keep their rubric versions.
- **Details:** [Analysis: Jev post-rework 2026-10-08, added section](analysis-jev-post-rework-2026-10-08.md#added-2026-10-08-pauls-level-5-needs-a-consequence-of-his-own-choice-or-discovery), [Jev scoring: sharper borders](jev-scoring.md#sharper-borders-for-paul-4-vs-5-and-lotta-3-vs-4-2026-10-08), [results](scripts/jev-confidence/results-2026-10-08-paul-consequence.md)

## 2026-10-08: The headline Jev score is a confidence-weighted average

- **Decision (Fredrik, via Case):** the headline Jev score is the confidence-weighted average, `sum(score × confidence) / sum(confidence)`, on the 1–5 scale. It is shown with the unsure share (confidence < 0.7) next to it, and the high / low / unsure breakdown stays underneath.
  - **This refines the entry below** ("Jev scores are read as a score-by-confidence matrix"). The weighted average replaces the mean of the scores at confidence ≥ 0.7 as the headline.
  - **The 0.7 cutoff stays** for the unsure share and the breakdown. The rest of that entry (the three groups, bootstrap CIs over runs, comparing unsure shares only within one rubric) still holds.
  - **On the playtest pages** (`/admin/playtest` and `/admin/playtest/:id`), the weighted turn average is the headline as "X/5 · unsure Y%". The breakdown sits under it and the session score is a secondary line.
- **Why:** the cutoff mean throws scores away. Where Jev is often unsure, too few remain to read: for example only 7 of Lotta's post-rework turns were left on the #69 rubric. The weighted average uses every turn and lets unsure turns count less. In practice it stays within about 0.1 of the plain mean for most personas, and it gives the same deltas: Paul's turn dip is −0.12 (CI −0.20…−0.05), and Hawk's gain stays clear of zero (+0.22, CI +0.01…+0.41).
- **Status:** approved; [ex-tales-forge #80](https://github.com/whyse-ab/ex-tales-forge/pull/80) merged 2026-10-08 09:31 (merge commit `132e732`, Fredrik approved 09:23) and deployed: production v76, playtest v66. The playtest pages show the weighted headline "X/5 · unsure Y%" with the breakdown underneath. The analyses report the weighted headline from 2026-10-08.
- **Details:** [Analysis: Jev post-rework 2026-10-08, added section](analysis-jev-post-rework-2026-10-08.md#added-2026-10-08-confidence-weighted-headline-and-sharper-paullotta-borders), [Analysis: Jev baseline 2026-10-07, update](analysis-jev-baseline-2026-10-07.md#update-2026-10-08-confidence-aware-reading), [script](scripts/jev-confidence/README.md)

## 2026-10-08: Sharper Jev borders for Paul (4 vs 5) and Lotta (3 vs 4)

- **Decision (Fredrik, via Case):** sharpen the two rubric borders where Jev was most often split, then re-score the existing baseline and post-rework runs. Each border now names what to look for in the turn, with a short example from a real turn.
  - **Paul 4:** the reply only answers him (information he asked for, a price, a room, a welcome, a gift).
  - **Paul 5:** at least two kinds of evidence, each visible in this turn's narration: a surprise he did not ask about, a consequence of his choice, a callback to an earlier word or deed, or an NPC acting on their own goals. Asked-for information, warmth, gifts and prices never count.
  - **Lotta 3:** the reply would read the same for any traveller who said her line.
  - **Lotta 4:** it picks up something particular to her character (race, craft or calling, background, earlier deeds). Using her name or answering her question is not enough.
  - **New rubric versions:** paul `jev-affect-v1-7862783` (was `fd84ebb`), lotta `jev-affect-v1-989546a` (was `ce84a1a`). Lars, Hawk and Ronny are unchanged. GM prompts are untouched.
- **Why:** on the #69 rubric Jev was unsure (confidence < 0.7) on 51% of Paul's and 75% of Lotta's baseline turns, split on exactly these borders.
- **Result:** the re-score ran on the box from existing transcripts (36 Jev calls, $0.012). Unsure share, baseline / post-rework:
  - **Lotta: it worked**, from 75% / 86% to 39% / 30%. Jev is now mostly sure she is at level 3, so her weighted headline drops from 3.92 to 3.28 on both sides, delta 0.00 (CI −0.22…+0.30).
  - **Paul: it did not**, from 51% / 46% to 72% / 74%. His typical turn is both an answer to his open question and vivid new detail he didn't ask for, and the wording can't settle which. His turn dip stays about −0.1 (weighted −0.10, CI −0.22…−0.01).
  - **Not done:** a further change to Paul's level 5 (for example requiring a consequence of his choice) would change the level's meaning. It is left open for Fredrik.
- **Status:** approved; [ex-tales-forge #80](https://github.com/whyse-ab/ex-tales-forge/pull/80) merged 2026-10-08 09:31 (merge commit `132e732`, Fredrik approved 09:23) and deployed: production v76, playtest v66. New scores use paul `jev-affect-v1-df3c861` (the consequence rule above replaced this entry's Paul level 5) and lotta `jev-affect-v1-989546a`; older scores keep their rubric versions.
- **Details:** [Analysis: Jev post-rework 2026-10-08, added section](analysis-jev-post-rework-2026-10-08.md#added-2026-10-08-confidence-weighted-headline-and-sharper-paullotta-borders), [Jev scoring: sharper borders](jev-scoring.md#sharper-borders-for-paul-4-vs-5-and-lotta-3-vs-4-2026-10-08), [re-score rows](scripts/jev-rescore/rescore-baseline-2026-10-08-sharp.json)

## 2026-10-08: Jev scores are read as a score-by-confidence matrix, not a plain average

- **Decision (Fredrik, via Case):** Jev scores are read as a score-by-confidence matrix, not a plain average.
  - **Headline score:** the mean of the confident scores only, with the cutoff at confidence ≥ 0.7. The same figure at 0.6 and 0.8 is shown next to it as a sensitivity check.
  - **Low-confidence share:** the share of turns (and sessions) below the cutoff is reported separately as its own metric. A high share is a sign of unclear or flat play. Compare it only within one rubric, because a stricter rubric adds a border Jev can be unsure about.
  - **Three groups:** confident-high (score ≥ 3.5, works), confident-low (score ≤ 2.5, broken) and unsure (confidence below the cutoff). Confident scores between 2.5 and 3.5 (level 3) are shown as confident-middle.
  - **Deltas** between series use the confident means, with bootstrap CIs over runs, next to the old plain-average deltas. A cutoff that leaves fewer than 20 turns or 3 runs (or 3 sessions) on a side is flagged as too few to read.
  - This entry covers the analysis method. Changes to the playtest page or the scorer code would be a separate PR and need Fredrik's OK.
- **Why:** plain averages mixed confident verdicts with split, unsure ones. For example, Ronny's turns where Jev leaned to level 1 but was split landed at 2.2–2.9 with confidence 0 (baseline `54c401ab` and `e367a9a0`, post-rework `50a3c41a` T3–T6), and several excerpt scores had confidence 0. In the baseline, problems outside Hawk showed up as unsure turns, not low ones: only 1 of 520 non-Hawk turns was confidently low.
- **Status:** applied to the 2026-10-07 baseline and the 2026-10-08 post-rework comparison, using existing scores only (no new runs, no Jev calls). The session deltas stay indistinguishable from zero. Hawk's turn-level gain becomes clear (+0.32, CI +0.15…+0.47), and Ronny's session dip turns out to come from unsure sessions. Paul's and Lotta's turn deltas can't be read this way yet, because the stricter re-score of their baseline kept no turn confidences. The playtest page and the scorer are unchanged. *Added 2026-10-08:* their baseline was re-scored again with turn confidences kept (26 Jev calls, $0.0067). Paul's turn dip is about the same size under the new reading (−0.08 at 0.7, CI −0.17…+0.01). Lotta has too few sure turns at 0.7.
- **Details:** [Analysis: Jev baseline 2026-10-07, update 2026-10-08](analysis-jev-baseline-2026-10-07.md#update-2026-10-08-confidence-aware-reading), [Analysis: Jev post-rework 2026-10-08, update 2026-10-08](analysis-jev-post-rework-2026-10-08.md#update-2026-10-08-confidence-aware-reading), [script](scripts/jev-confidence/README.md)

## 2026-10-08: Bug fix: the turn hang after an intent call; crashed turns now fail visibly; run flags record the world features

- **Decision (Fredrik, via Case):** merge and deploy the fix for the turn hang found in the post-rework series. Approved 2026-10-08 07:48: merge #79 and deploy once the survey page was live. This is a bug fix, recorded here for the behaviour changes below.
  - **Cause:** the intent call answers `"parameters": null` for actions that need no roll. The decoder kept that `nil`, and the rules step crashed on it (`BadMapError`) inside the turn job. Oban retried three times and dropped the job without any log line or failed-turn message, so the player or playtest runner waited until its timeout. This hung 3 of 14 intent-call turns: runs `a76294d9`, `0d1b8222` and `1a995c9f`.
  - **Fix:** the intent decoders treat JSON `null` as missing.
  - **Crashed turns now fail visibly:** a crash in any turn step is logged with its stacktrace, shown to the player as a failed turn ("crashed: <error>"), marked `error` on that step's `ai_calls` row and retried by Oban. A playtest run then ends as `failed` with the error in its notes, instead of `stopped` / `timeout`.
  - **Run flags:** `playtest_runs.flags` now record `inn_world` and `world_antagonist` (`on`/`off`). They come from the session's features.
  - **Misread roll:** "scale" now counts as climbing only as a verb ("scale the wall"). Paul's "silver to the scale" no longer rolls climbing.
- **Why:** a crash should never look like a slow turn. Run conditions should be readable from the run itself.
- **Status:** merged as `ccd5379`, deployed to production v75 and playtest v63. Health checks pass and the survey page still redirects to the login when signed out.
- **Details:** [ex-tales-forge PR #79](https://github.com/whyse-ab/ex-tales-forge/pull/79), [Analysis: Jev post-rework 2026-10-08, §9](analysis-jev-post-rework-2026-10-08.md#9-limitations)

## 2026-10-08: Founder survey in the app instead of Google Forms

- **Decision (Fredrik, via Case):** the founder survey runs on our own page at `/admin/survey`, behind the GitHub team login, so we know who answered and there's no name question. Approved by Fredrik (2026-10-08 07:45: "You are go for survey", merge and deploy).
  - The questions come from [`founder-survey-3.json`](founder-survey-3.json) on this repo's main, read through GitHub with the server's `GITHUB_DOCS_TOKEN` and cached for 60 s. A snapshot in the release is the fallback. A wording change, opening or closing (`status`) is a docs commit, with no deploy. The `.md` is generated from the JSON (`scripts/survey/render_md.py`).
  - Answers autosave per section, one response per founder, editable until `status` is `closed`. Each answer records the survey `version` it was given under, and every survey file answered under is stored verbatim.
  - Results at `/admin/surveys/founder-survey-3/results`: per-question aggregates by persona, per-founder answers, a CSV export and a Markdown summary for personas.md.
- **Why:** survey 2 never went out, and Google Forms can't link the excerpts to the playtest runs or keep answers tied to the exact question wording.
- **Status:** merged as `944ad1a`, deployed to production v74 and playtest v62. On both apps the release loads the survey from tales-forge-docs main (27 questions, status open, no problems). The page redirects to the login when signed out. The first prod deploy attempt (v73) failed on a transient database connection timeout in the migration step and passed on re-run.
- **Details:** [ex-tales-forge PR #78](https://github.com/whyse-ab/ex-tales-forge/pull/78), [founder survey](founder-survey-3.md)

## 2026-10-08: Broken links fixed in the admin docs viewer and the code docs; CI checks the links

- **Decision:** links in the admin docs viewer (`/admin/docs`, decision pages) and in the code docs (`/admin/code-docs`) resolve, and CI fails when one breaks. Approved by Fredrik (2026-10-08 07:40: merge, deploy and sync the docs on both apps).
  - Docs viewer: relative `.md` links go to the doc's own page (`/admin/docs/<path>`) or the decision page, images under `docs/` are served at `/admin/docs-files/<path>`, other repo files go to their GitHub URL in this repo, and headings get ids so `#anchor` links work.
  - Code docs: the missing `docs_config.js` is shipped, PRODUCT, architecture and DEPLOY-FLY are included as pages, links to files ExDoc doesn't ship go to GitHub, and "View source" points at the deployed commit (`GIT_SHA`).
  - CI: `mix docs.check_links doc` checks every internal link in the ExDoc output, and a crawl test signs in and checks that every internal link on the app's pages returns 200.
- **Why:** Fredrik found broken links on the admin docs pages and in the code docs.
- **Status:** merged as `b8b41cc`, deployed to production v72 and playtest v61; docs synced on both apps (32 docs, 12 decisions each; before: production 13 docs, playtest 12). An in-app check of all 44 doc and decision pages found no broken internal link or anchor on either app.
- **Details:** [ex-tales-forge PR #77](https://github.com/whyse-ab/ex-tales-forge/pull/77)

## 2026-10-08: Hawk / Tinjacks: the Tinjacks come to the fighter; Brenna points at trouble, not chores

- **Decision (Fredrik, via Case):** the Tinjacks come to the fighter. Their plans run on world time even when he's away, so the toll happens anyway and he hears about the consequences afterwards. Brenna points fighters at the trouble instead of offering chores.
  - Status: live. [ex-tales-forge #86](https://github.com/whyse-ab/ex-tales-forge/pull/86) merged 2026-10-09 with Fredrik's OK (`169a743`); deployed with final main `dd5dc7e` (prod v84, playtest v75). Measured in the [full batch 2026-10-09](#2026-10-09-fresh-full-playtest-batch-as-the-new-baseline).
- **Why:** in the post-rework batch, only 1 of 5 Hawk runs fought (on the last turn) and he still did chores in 3 of 5; runs without a fight scored better (3.14 vs 2.54) but the confrontation came too late.
- **Details:** [Analysis: Jev post-rework 2026-10-08](analysis-jev-post-rework-2026-10-08.md)

## 2026-10-08: GM tics: track recent gestures as off-limits; drop phrase-by-phrase bans

- **Decision (Fredrik, via Case):** drop phrase-by-phrase bans. Elixir tracks the gestures used in the last N turns and passes them to the GM as off-limits, and a pattern check on the output catches repeats (log any that slip through).
  - Status: live. [ex-tales-forge #87](https://github.com/whyse-ab/ex-tales-forge/pull/87) merged 2026-10-09 with Fredrik's OK (`bda5e9e`); deployed with final main `dd5dc7e` (prod v84, playtest v75). Measured in the [full batch 2026-10-09](#2026-10-09-fresh-full-playtest-batch-as-the-new-baseline).
- **Why:** the banned "wipes her hands" still appeared in 57% of runs, and new tics replaced the banned ones ("leans an elbow" 11, "leans a hip" 10, Cobb "shifts his weight" 12).
- **Details:** [Analysis: Jev post-rework 2026-10-08](analysis-jev-post-rework-2026-10-08.md)

## 2026-10-08: The forge and Maude's cottage pull players in through rumours and hooks

- **Decision (Fredrik, via Case):** the forge and Maude's cottage pull players in through rumours and hooks from Brenna and the regulars, tied to what the world is doing, so the lore actually gets found.
  - Status: live. [ex-tales-forge #88](https://github.com/whyse-ab/ex-tales-forge/pull/88) merged 2026-10-09 with Fredrik's OK (`77ba4e2`); deployed with final main `dd5dc7e` (prod v84, playtest v75). Measured in the [full batch 2026-10-09](#2026-10-09-fresh-full-playtest-batch-as-the-new-baseline).
- **Why:** the forge, Maude's cottage and the lore were never reached in 23 runs.
- **Details:** [Analysis: Jev post-rework 2026-10-08](analysis-jev-post-rework-2026-10-08.md)

## 2026-10-08: Clarification: the safety read is part of the intent call, not a separate Jev call

- **Clarification (Fredrik, via Case, 07:27):** "We don't need another call to Jev, we just need to add it to the existing intent call." The rule of [the GM gets the player's own words when the safety read is confident](#2026-10-08-the-gm-gets-the-players-own-words-when-the-safety-read-is-confident) stands (threshold 0.90, fallback to the intent summary, logged). What changes is how the safety read is done: it is two more fields in the Tier 1 intent call's reply, `input_safety` (`benign`, `jailbreak`, `prompt_injection`, `nefarious`) and `input_safety_confidence`. The instructions sit in the static intent system prompt, so prompt caching still works. The separate Jev call (purpose `input_safety`) and its TypeSafe key are gone. That entry is unchanged otherwise.
- **The heuristic path has no safety read.** Most turns never make the intent call, because the heuristic reads them alone.
  - On playtest, 14 of 258 player messages on 2026-10-08 went to the intent call (5%), and 0 of 714 on 2026-10-07; the rest were heuristic.
  - Those turns now get a short typed summary of the action (`speak (target: innkeep)`) instead of the player's words. That is the simplest safe choice: no extra calls and no unchecked text. Its cost is that on about 95% of turns the GM no longer sees what the player said this turn.
  - `INTENT_CALL_EVERY_TURN=on` sends every default-variant turn through the intent call instead. Every turn then gets a safety read and can quote the player. The cost is one intent call per heuristic turn, about $0.0024 and 2.0 s at the median (3.5 s at p90) on the player's clock, and the LLM's reading replaces the heuristic's. Default off; **Fredrik decides** (a playtest comparison with the flag on and off is the natural test).
- **Cost of the extra fields** (6 sample messages, the same intent call before and after):
  - About +260 input tokens and +28 output tokens per intent call, about +$0.0004 (+21%) and +0.25 s.
  - Averaged over all turns at today's 5% intent share, that is about +$0.00002 and +15 ms per turn compared with before PR #76.
  - All six were labelled as expected: three benign (0.90–0.95), two `prompt_injection` (0.95) and the DAN text `jailbreak` (0.95).
- **Caveats:**
  - **The confidence is the LLM's own estimate.** For ordinary play it was 0.90 or 0.95, so the 0.90 threshold sits at the edge.
  - **Earlier turns still reach the GM unchecked.** The GM's per-turn prompt lists earlier turns' raw player text under "Recent turns" (up to 120 characters each), with no safety read; this PR does not change that. Gating that list on each turn's decision would be a follow-up.
- **Logged and queryable:** each decision goes in `ai_calls.meta` (`label`, `confidence`, `threshold`, `used`, `reason`). It is stored on the intent call's row (purpose `intent`) and on the turn's `turn.intent` step row, which exists for every message, so heuristic turns count too (reason `no_intent_call_heuristic`). `/admin/costs` shows the per-turn fallback rate. In SQL:

    ```sql
    SELECT count(*) FILTER (WHERE meta->>'used' = 'summary')::float / NULLIF(count(*), 0) AS fallback_rate,
           count(*) AS turns
    FROM ai_calls
    WHERE purpose = 'turn.intent' AND meta IS NOT NULL
      AND inserted_at > now() - interval '7 days';
    ```

- **Status:** [ex-tales-forge #76](https://github.com/whyse-ab/ex-tales-forge/pull/76), reworked; not merged or deployed. Merging needs Fredrik's OK, after the baseline/default comparison. The baseline variant keeps its intent prompt and schema (frozen).

## 2026-10-08: The GM gets the player's own words when the safety read is confident

- **Decision (Fredrik, via Case):** the GM gets the **player's own words** as the quote in the `PlayerAction` (`overall_intent`), sanitised and at most 500 characters, on **both** intent paths (heuristic and intent LLM), when an input safety read is **at least 90% confident the message is benign**: not a jailbreak, not prompt injection, not nefarious, so the risk is near 0. Below that, the GM gets the intent summary, and the fallback is logged.
- **Supersedes:** [Clarification: the GM gets a typed struct plus a short quote of the player's words](#2026-10-08-clarification-the-gm-gets-a-typed-struct-plus-a-short-quote-of-the-players-words). There, the intent LLM's summary was the quote whenever the intent LLM read the turn, and the heuristic path always quoted the player's text unchecked. That entry is unchanged otherwise. The validated, typed `PlayerAction` still decides what happens, and the server's rules still read it.
- **How** ([ex-tales-forge #76](https://github.com/whyse-ab/ex-tales-forge/pull/76), stacked on #75, not merged or deployed; merge needs Fredrik's OK, after the baseline/default comparison):
  - **The call:** one Jev call per turn (`TalesForge.Game.PlayerQuote`, call type `jev`, purpose `input_safety`, `jev-1.13.0`). It is a choice between fixed labels, `benign`, `jailbreak`, `prompt_injection` and `nefarious`, with a confidence. There was no input check to reuse; this call is new. Unstructured input and a typed answer make it a Jev call by the [call-type rule](call-types.md).
  - **The threshold:** `PLAYER_QUOTE_MIN_BENIGN_CONFIDENCE` (0..1, default 0.90), read in `config/runtime.exs`. A quote needs label `benign` and confidence ≥ threshold.
  - **The fallback:** another label, a lower confidence, an error, a 2 s timeout or no TypeSafe key all mean the summary. The summary is the intent LLM's summary, or a short typed summary such as `speak (target: innkeep)` when the heuristic read the turn.
  - **The key:** `TYPESAFE_INTENT_API_KEY` when set (staged on playtest), else `TYPESAFE_API_KEY`. Production has neither, so on production the GM gets the summary until a key is set (Fredrik's OK).
  - **Scope:** only the GM prompt's quote changes. The GM prompt template and the golden fixtures are unchanged. The baseline variant makes no read (frozen for the comparison).
  - **Parallel:** the read runs alongside the rules, prices and NPC reactions; the turn waits for it only before the GM prompt (step `turn.player_quote`).
- **Cost and latency** (measured 2026-10-08 on 10 sample messages):
  - About 510 input tokens per read, about **$0.00002 per turn**, under 1% of a GM call.
  - 73–323 ms, median about 130 ms, mostly hidden behind the NPC reaction call on playtest.
  - Ordinary play (including in-story fights and lies) read `benign` 1.00.
  - Injection attempts read `prompt_injection` 0.97–1.00. A DAN-style jailbreak read `prompt_injection` 0.41; it still falls back, because the label is not benign. A real-world weapon question read `nefarious` 0.96.
- **Logged and queryable:**
  - Each turn logs a `player quote … used=quote|summary reason=… label=… confidence=… threshold=…` line.
  - Each turn stores `label`, `confidence`, `benign_probability`, `threshold`, `used` and `reason` in `ai_calls.meta`.
  - `/admin/costs` shows the fallback rate ("GM quote fallback (input safety)"). In SQL:

    ```sql
    SELECT count(*) FILTER (WHERE meta->>'used' = 'summary')::float / NULLIF(count(*), 0) AS fallback_rate,
           count(*) AS reads
    FROM ai_calls
    WHERE purpose = 'input_safety' AND inserted_at > now() - interval '7 days';
    ```

- **Why:**
  - The player's own words keep their tone and detail better than a summary, which flattens them.
  - The safety read keeps text that tries to steer the GM, or that is not play, out of the prompt, for a fraction of a cent.
  - A summary is still the safe default whenever the read is unsure or unavailable.
- **Details:** [Fly secrets](fly-secrets.md) (`PLAYER_QUOTE_MIN_BENIGN_CONFIDENCE`, `TYPESAFE_INTENT_API_KEY`), [Call types](call-types.md)

## 2026-10-08: Clarification: nothing syncs from the earlier apps

- **Clarification (Fredrik, via Case):** ex-tales-forge stands on its own. Nothing is synced from text-forge, tales-forge-new or any other earlier app; its rules, prompts, packs and code are maintained in ex-tales-forge. The earlier apps are history only.
- **Applies to:** [the code docs stand alone](#2026-10-08-clarification-the-code-and-its-docs-stand-alone-where-the-code-came-from-is-recorded-here). Its notes on where the code came from are history, and the old "sync rules and prompts from text-forge" note it mentions does not apply any more. That entry is unchanged otherwise. The Agent Rules say the same ([ex-tales-forge #75](https://github.com/whyse-ab/ex-tales-forge/pull/75)).
- **Why:** one source of truth for the game's rules and prompts; the golden prompt tests guard them, and nobody has to watch another repo.

## 2026-10-08: Clarification: the GM gets a typed struct plus a short quote of the player's words

- **Clarification (Fredrik, via Case):** the GM gets the validated, typed `PlayerAction` **plus a short, sanitised quote of the player's words**, and that is intended. The quote is the action's `overall_intent`: at most 500 characters, with whitespace collapsed and "ignore previous instructions" phrases removed. When the heuristic reads the turn it is the player's own text; when the intent LLM reads it, it is that call's short summary of the message, sanitised the same way. The full raw message never reaches the GM.
- **Applies to:** [GM pipeline direction](#2026-10-07-gm-pipeline-direction) ("a typed struct with a short quote of the player's words"). That entry is unchanged. The Agent Rules used to say "raw player text never reaches Tier 2"; they now say this ([ex-tales-forge #75](https://github.com/whyse-ab/ex-tales-forge/pull/75)).
- **Why:** the quote lets the GM keep the player's tone, while the typed struct and the server's rules decide what happens.
- **Details:** `TalesForge.Game.Intent` (`sanitize_summary/1`), [Call types: target turn pipeline](call-types.md#target-turn-pipeline)

## 2026-10-08: The prose-only GM prototype is dropped; the GM has one structured reply mode

- **Decision (Fredrik, via Case):** the prose-only GM prototype (`GM_REPLY_MODE=prose`, [ex-tales-forge #38](https://github.com/whyse-ab/ex-tales-forge/pull/38)) is dropped and its PR closed without merging. The GM keeps **one reply mode**, the strict structured JSON schema, and there is no reply-mode flag. This answers the open question "Prose-only GM vs structured reply format" (bottom of this file).
- **Why:** in the prototype's local runs (Paul, Tin Valley, 5 turns, 2 runs per mode) prose was cheaper and faster: $0.00395 against $0.00567 per turn (−30%), median GM latency 4.0 s against 4.8 s, and first tokens at about 0.8 s when streamed. But it lost what the schema gives:
  - **NPC memories:** the GM wrote none, so NPCs only had automatic "Overheard player: …" lines and a later turn could contradict an earlier promise or price (one room-price contradiction in a prose run, none in the schema runs);
  - **lore anchoring:** invented facts were not recorded per turn (both final prose runs turned the orc nest into "harpies"; neither schema run reached the nest, so that sample can't compare the modes), and the summary updated only every 3 turns.
  - **No clear gain in play:** session scores showed no difference either way (Jev 4.14 prose against 4.01 schema, n = 4 against 5, with lower confidence for prose), and the schema stayed the default.
  - Since then the schema mode has the useful parts of the prototype: the Jev NPC reaction before the GM call (`NPC_REACTIONS`) and, with `WORLD_AGENTS` on, facts read from the narration after each turn.
- **Details:** [ex-tales-forge PR #38](https://github.com/whyse-ab/ex-tales-forge/pull/38) (results and trade-offs), [Analysis: Jev scores 2026-10-07](analysis-jev-scores-2026-10-07.md), [Design: world agents](design-world-agents.md)

## 2026-10-08: Clarification: the code and its docs stand alone; where the code came from is recorded here

- **Clarification (Fredrik, via Case):** ex-tales-forge's code, module docs, comments, README and Agent Rules (`AGENTS.md`, the "Agent Rules" page of `/admin/code-docs`) describe what the code does now. They no longer mention the earlier apps; history and origin notes live in this repo. Nothing about the game changes.
  - Status: [ex-tales-forge #75](https://github.com/whyse-ab/ex-tales-forge/pull/75) is approved by Fredrik (2026-10-08) and is merged after the current playtest series ends; not merged or deployed yet. It removes 18 such references in 9 files.
- **Where the code came from** (the notes removed from ex-tales-forge, kept here):
  - **text-forge** (FastAPI + Next.js, file-based campaigns with a git commit per campaign turn; repo `text-forge`, still under `fpahlen`, see [Infrastructure](infrastructure.md)). ex-tales-forge started as an Elixir rewrite of it. Its `backend/app/rules/*.md` became `priv/rules/*.md`, its `backend/app/prompts/*.txt` became `priv/prompts/*.txt`, and the Crossroads NPC files `priv/npcs/*.json`, the server-side dice and Learning Points (`Game.Mechanics`) and the play-test skill (`.grok/skills/play-test`) came from it. Its Supabase code was not ported. Turn history moved from git commits to the `Turn` table (same goal, different storage). The old Agent Rules also said "when rules or prompts change in text-forge, sync the corresponding files here"; that note is gone with the rest.
  - **tales-forge-new** (`fpahlen/tales-forge-new-31993d9d`, the React + Supabase app; tales-forge.ai on Netlify, see [Infrastructure: to retire](infrastructure.md#to-retire)). The skill rules in `priv/characters/creation.json` come from its written rules (sources listed in [character creation port: skill rules](character-creation-port.md#skill-rules-ported-2026-10-07)), and the prompt-prefix test (`test/ex_tales_forge/game/prompt_prefix_test.exs`) was ported from its `_shared/__tests__/promptOrdering.test.ts`.
  - Left in the code on purpose: the "Starting Wealth (Legacy Fallback)" / `STARTING_WEALTH` text in `priv/rules/economy.md` and its pack copies. It is part of the GM's rules text and the golden prompt fixtures, which must not change by accident.
- **Why:** humans and coding bots read the module docs to learn what the code does. Notes about another app's files send them to code they don't have and make the docs go stale; one place for history keeps both clear.
- **Details:** [ex-tales-forge PR #75](https://github.com/whyse-ab/ex-tales-forge/pull/75), [Coding standards](coding-standards.md), [character creation port](character-creation-port.md)

## 2026-10-07: Build out the inn and its surroundings for every player type; record scene changes

- **Decision (Fredrik, via Case):**
  - Build out the inn and its surroundings so **every player type finds a favourite activity**: talking, trading, exploring, sneaking, fighting, lore, crafts and so on. This is done through **world agents and locations**, not a longer script.
  - Fix the **leave-the-inn bug**: when the player leaves, record the **scene change** (new location and the NPCs present there), so the GM stops describing the inn and stops answering as Brenna after the player has gone.
  - Status: merged 2026-10-08: [ex-tales-forge #68](https://github.com/whyse-ab/ex-tales-forge/pull/68) (scene changes) as `7b88dad` and [#72](https://github.com/whyse-ab/ex-tales-forge/pull/72) (inn world) as `9080cb1`; deployed (prod v67 and v69, playtest v56 and v58). `INN_WORLD` is on for playtest only.
- **Why:** in 62% of runs the player tries to leave the inn, and after 38 of 65 such attempts the GM is still describing the inn or Brenna on the next turn. In Paul's two weakest runs the GM walks him to the Market Square and then answers his speech to Osric as Brenna, back at the bar; neither run registered a scene change. With only the inn to play in, each persona runs out of things it likes (Hawk gets chores, Lars's adventure is deferred).
- **Details:** [Analysis: Jev baseline 2026-10-07, §4 and recommendation 1](analysis-jev-baseline-2026-10-07.md), [Design: world agents](design-world-agents.md), [PR #68](https://github.com/whyse-ab/ex-tales-forge/pull/68) (scene changes), [PR #72](https://github.com/whyse-ab/ex-tales-forge/pull/72) (inn world, `INN_WORLD`)

## 2026-10-07: Hawk gets real conflict: a minor antagonist who acts on their own

- **Decision (Fredrik, via Case):** Hawk gets real conflict. A **minor antagonist** stirs up trouble in or near the village and **acts on their own**, whether or not the player engages. This follows the living-world and factions direction: an agent with a goal and a plan that moves on world time. It is **not a scripted fight**.
  - This builds on [To try: living world](#2026-10-07-to-try-living-world) and makes a small first case of it a decision for Tin Valley.
  - Status: merged 2026-10-08: [ex-tales-forge #73](https://github.com/whyse-ab/ex-tales-forge/pull/73) (Tinjacks) as `9e7d447` and [#71](https://github.com/whyse-ab/ex-tales-forge/pull/71) (fights roll) as `8bf10d3`; deployed (prod v70 and v66, playtest v59 and v55). `WORLD_ANTAGONIST` is on for playtest only.
- **Why:** Hawk almost never meets danger. His turn mean is 1.93, only 4 of 13 runs reach a turn scoring 3 or more (never before turn 8), and his session score is 2.54 without a fight roll against 4.61 with one. Brenna's "lend a hand" hooks have him hauling kegs. A scripted fight would fix the number once; an antagonist who moves on their own gives danger that the player's choices change.
- **Details:** [Analysis: Jev baseline 2026-10-07, §1, §4 and recommendations 2–3](analysis-jev-baseline-2026-10-07.md), [Design: world agents, living world](design-world-agents.md#living-world-design-to-try), [PR #73](https://github.com/whyse-ab/ex-tales-forge/pull/73) (Tinjacks antagonist, `WORLD_ANTAGONIST`), [PR #71](https://github.com/whyse-ab/ex-tales-forge/pull/71) (fights roll)

## 2026-10-07: Skill growth: spend 1 LP for one improvement attempt (supersedes the tiered thresholds)

- **Decision (Fredrik, via Case):** a new skill growth rule.
  - Spending **1 LP buys one improvement attempt** on that skill.
  - Roll **d20**. If the result is **equal to or higher than the current skill level**, the skill gains **+1**.
  - More LP means more attempts.
  - This **supersedes** the progression part of [Skill rules ported from the old game](#2026-10-07-skill-rules-ported-from-the-old-game-signature-skills-up-to-7-growth-no-longer-stalls) ([#64](https://github.com/whyse-ab/ex-tales-forge/pull/64)): the 5 / 7 / 10 / 15 LP tier thresholds, the failure requirement, the rest requirement and the tiered thresholds are gone. It also supersedes item 4 ("growth pace stays as it is for now") of [Skill rules: the open questions answered](#2026-10-07-skill-rules-the-open-questions-answered). LP are still earned per roll as before, including the stat bonus.
  - Status: merged 2026-10-08 as `c2f237f` ([ex-tales-forge #67](https://github.com/whyse-ab/ex-tales-forge/pull/67)); deployed (prod v65, playtest v54). In it: attempts happen at the end of every turn (every whole LP is spent), a trainer gives one free attempt at +5, and the Expert −3 / Master −5 modifiers are removed. The `baseline` variant keeps the #64 rule.
- **Why:** skill growth has stopped. The baseline averages about 1.0 LP per run, and there were **0 improvement attempts in 65 runs**: an attempt needed 5 LP, a failure and a rest of an hour, and almost no run had all three. With one attempt per LP, every LP is a visible chance to grow, and the d20 ≥ level roll slows growth naturally as a skill gets higher (a success chance of (21 − level)/20).
- **Details:** [Analysis: Jev baseline 2026-10-07, §6 and recommendation 7](analysis-jev-baseline-2026-10-07.md), [character creation port: growth rule replaced](character-creation-port.md#growth-rule-replaced-2026-10-07-1-lp--one-improvement-attempt), [PR #67](https://github.com/whyse-ab/ex-tales-forge/pull/67)

## 2026-10-07: How the GM plays Brenna: no default echo, no stock tics

- **Decision (Fredrik, via Case):**
  - The GM does **not** echo or restate the player's line by default. It answers the action instead of re-narrating it.
  - Echoing the player's last few words is allowed only as a **deliberate, rare negotiator move** by a character, to draw the player out ("…the old shaft?"). It is never a turn opener by habit.
  - Brenna's "on the house" generosity default goes. A freebie needs a reason in the story.
  - The stock gesture "tilts her head (toward)" goes, along with the other new tics the baseline found.
  - This refines the prose rules in [Brenna is a warm, chatty barkeep](#2026-10-07-brenna-is-a-warm-chatty-barkeep-a-lead-by-turn-2-gm-prose-cleanup): "no echoing the player's words" stays, and the rare deliberate echo is now the one exception. Brenna stays warm and chatty.
  - Status: merged 2026-10-08 as `eb752fa` ([ex-tales-forge #70](https://github.com/whyse-ab/ex-tales-forge/pull/70)); deployed (prod v68, playtest v57).
    - Default variant only: "React, do not restate", the deliberate-echo exception, a banned stock-phrase list (now also "wipes her hands", which replaced the old tics in local checks), "a gesture in the recent turns is used up", and NPCs charge their prices.
    - Brenna's personality: "her gossip is free; her goods are not".
    - The default golden fixtures were regenerated on purpose. The baseline variant and its fixtures are unchanged.
    - Local checks (6 small runs, not comparable to Fly): the GM echoed the player's line on 1 of 36 turns, against 22% in the baseline.
    - It conflicts with #68 in `scene_system.txt` and the fixtures. Whichever merges second needs a rebase.
- **Why:** the GM opens 22% of turns by repeating the player's own line (Lotta: 52%; Elara runs: 5%). Brenna gives something "on the house" in 77% of runs and "tilts her head toward" in 36 of 65 runs. The cold "eyes narrow" tic has been replaced by a generous one, which is also what confuses Ronny's rubric.
- **Details:** [Analysis: Jev baseline 2026-10-07, §4 and recommendations 4–5](analysis-jev-baseline-2026-10-07.md)

## 2026-10-07: A stricter Jev rubric before the next A/B; the personas stay as they are

- **Decision (Case's recommendation; Fredrik did not object):** before the next A/B, the Jev rubric gets stricter at the top. The top levels need concrete evidence in the transcript, such as a surprise, a consequence that matters, a callback to earlier play, or an NPC acting on its own, so that a pleasant but uneventful session no longer reaches them. The rubric version or hash is bumped. Any comparison with the 2026-10-07 baseline must re-score the baseline with the new rubric. The personas (Paul, Lotta and the others) do **not** change: they model real players, so the scale has to move, not the players.
  - This refines [Jev persona-affect scoring](#2026-10-07-jev-persona-affect-scoring): same 1–5 scale and same inputs, with harder top levels.
  - Status: merged 2026-10-08 as `cb6a5f6` ([ex-tales-forge #69](https://github.com/whyse-ab/ex-tales-forge/pull/69)); deployed (prod v64, playtest v53).
    - Paul is now `jev-affect-v1-fd84ebb` (was `dfec71a`) and Lotta `jev-affect-v1-ce84a1a` (was `4545d3b`). Lars, Hawk and Ronny are unchanged.
    - Level 3 now covers smooth but generic play. Level 4 needs a reply to their particular character. Level 5 needs evidence of at least two of: a surprise, a consequence, a callback, an NPC acting on its own goals (Lotta: or care when stakes hurt).
    - Pilot re-score of the 26 baseline runs: Paul's turns went from argmax 5 on 124/130 to 4 on 75 and 5 on 54. Lotta's went from 4 on 130/130 to 3/4/5 on 24/94/12.
    - Paul's session mean did not drop (4.67 → 4.73), so for Paul use turn means. See [Jev scoring](jev-scoring.md#stricter-top-for-paul-and-lotta-2026-10-07).
- **Why:** Paul and Lotta sit at the ceiling. Lotta's most likely level is 4 on 130 of 130 turns (session SD 0.07), and Paul's is 5 on 124 of 130. At that point no change to the game can show up in their scores, so they are useless as A/B signals.
- **Details:** [Analysis: Jev baseline 2026-10-07, §1 and recommendation 6](analysis-jev-baseline-2026-10-07.md), [Jev scoring](jev-scoring.md)

## 2026-10-07: Skill rules: the open questions answered

- **Decision (Fredrik, via Case):**
  1. **Half-Elf** keeps the game's DEX +1, CHA +1 (not the old JSON's CHA +1, INT +1). No change.
  2. **The untrained floor applies only to skills at level 0.** As in the old rule ("an untrained attempt uses stat ÷ 3"), a level-0 skill rolls against `max(stat ÷ 3, stat bonus)`. A trained skill uses level + stat bonus as before, so levels 1–3 always count. The roll note says "untrained: stat ÷ 3". Done in [ex-tales-forge #62](https://github.com/whyse-ab/ex-tales-forge/pull/62).
  3. **The past occupation feeds the OCEAN, Maslow and concerns defaults** for player characters, as occupations do for NPCs. Fredrik's earlier decision is that defaults come from class, race, social standing and occupation. It replaces "adventurer" there too (now only a fallback). Done in [#63](https://github.com/whyse-ab/ex-tales-forge/pull/63). The occupation goes on the GM's character sheet with the planned "GM sees who the character is" PR (character-creation PR 5). Today that sheet has no race, class or skills either, so adding the occupation alone would be a separate prompt change ahead of the PR that adds the whole character section once.
  4. **Growth pace stays as it is for now.** Every playtest run now records its skill growth: rolls, LP gained, improvement attempts and improvements per skill, on the run's `growth`. That way the baseline shows how fast characters grow.
- **Why:** these close the open questions from the skill-rules port before Fredrik merges it.
- **Details:** [character creation port: skill rules](character-creation-port.md#skill-rules-ported-2026-10-07)

## 2026-10-07: Skill rules ported from the old game; signature skills up to 7; growth no longer stalls

- **Decision (from Fredrik, via Case):** player characters get the written skill rules of the old game. Signature skills are Fredrik's call.
  - **Skill budget 25:** levels 1–3 cost 1 each and levels 4–5 cost 2 each. The normal cap is 5, and a character needs at least 5 skills. The screen suggests a spread build, and the player can change it within the budget.
  - **Signature skills (Fredrik's call):** one or two skills may go to **7** for solo heroes. Levels 6–7 cost **3 each**, continuing the 1, 1, 1, 2, 2 curve: a 7 bought from scratch costs 13 of the 25 points, a real commitment.
  - **Free levels:**
    - the class package gives all three class skills at 3/2/1 (before, the third was dropped);
    - a **past occupation**, chosen from the existing occupation tables, gives +2 on its core skills and +1 on its secondary ones. It replaces the skill-less "adventurer", and each class suggests one;
    - race: Human +5 and Half-Elf +3 points, Elf/Dwarf/Gnome/Halfling fixed skill levels from `game-system.json`.
  - All free levels stack under the same caps, and levels the caps cut off come back as points.
  - **Untrained floor:** a roll never uses less than `max(stat ÷ 3, stat bonus)`.
  - **Progression:**
    - LP thresholds by tier: 5 / 7 / 10 / 15 (Novice, Adept, Expert, Master);
    - improvement roll modifiers: Expert −3, Master −5;
    - LP stat bonus: `(stat − 10) ÷ 4`, 0 to +2 per roll;
    - **one** failure since the last attempt is enough (was three).
  - Status: open PRs, not merged or deployed. Each waits for Fredrik's approval:
    - [ex-tales-forge #62](https://github.com/whyse-ab/ex-tales-forge/pull/62): rules engine and untrained floor;
    - [#63](https://github.com/whyse-ab/ex-tales-forge/pull/63): occupation;
    - [#64](https://github.com/whyse-ab/ex-tales-forge/pull/64): progression, with the GM rules text and golden fixtures updated on purpose;
    - [#65](https://github.com/whyse-ab/ex-tales-forge/pull/65): creation screen and persona builds.
- **Why:** a solo character has no party to cover its gaps, so it must be well rounded from the start. The old cap of 2 class skills left created characters with two skills. After the roll rule ([#56](https://github.com/whyse-ab/ex-tales-forge/pull/56)) fewer actions roll at all, so "5 LP and 3 failures" would have stalled growth.
- **Details:** [character creation port: skill rules](character-creation-port.md#skill-rules-ported-2026-10-07), including every ambiguity in the old rules and how it was resolved; [persona characters](playtest-persona-characters.md)

## 2026-10-07: Brenna is a warm, chatty barkeep; a lead by turn 2; GM prose cleanup

- **Decision (Fredrik's call, via Case):** Brenna, the Tin Valley innkeep, becomes a warm, chatty barkeep who genuinely enjoys running the tavern.
  - Her OCEAN traits go up on extraversion and agreeableness: O4 C8 E5 A6 N5 → **O6 C7 E8 A8 N3**. Her mood is cheerful. Her concern becomes "keep the common room full, warm and talking, and her regulars safe while the hills are restless" (Maslow is still belonging).
  - Her default brush-off is dropped. She treats a civil, paying guest warmly unless the character gives her a reason not to.
  - The story gets moving by turn 2. NPCs can carry ready-made `hooks` (Brenna has four: Osric Vane paying for steel against the orc nest, Caldern Voss and the shaft, goods the orcs took off the valley road, and a free meal plus gossip for a helper). The GM prompt asks for one concrete lead (a job, a name or a place) by the end of the player's second turn at the latest.
  - The GM's prose is cleaned up:
    - always second person, so no "Elara …" openers;
    - no echoing the player's words;
    - no re-serving or re-describing;
    - stock phrases ("eyes narrow", "scarred oak", "slides the mug across", "the hearth crackles") are named and avoided;
    - prices, names and promises stay consistent.
  - The old Brenna and the old prompts stay available as the opt-in `baseline` behaviour variant, so the rework can be A/B-tested on one deploy.
  - Status: [ex-tales-forge PR #58](https://github.com/whyse-ab/ex-tales-forge/pull/58) is open, stacked on #56, and waits for Fredrik's approval. It is not merged or deployed.
- **Why:** in the Jev analysis, Brenna's brush-off ("eyes narrow", flat voice, "clearly done") appeared in 39 of 44 runs. It was the most common cause of low turn scores (15 of the 19 lowest turns examined), hit Lotta hardest, and no run got past the inn in five turns.
- **Details:** [Analysis: Jev scores 2026-10-07](analysis-jev-scores-2026-10-07.md), [PR #58](https://github.com/whyse-ab/ex-tales-forge/pull/58), [measurement plan](plan-jev-baseline-and-ab.md)

## 2026-10-07: No skill roll on ordinary talk; a failed roll only means you learn nothing extra

- **Decision (from Fredrik, via Case):**
  - Ordinary talk and everyday actions (ordering, chatting, asking a question, looking around) get **no skill roll**. A check happens only when the outcome is genuinely uncertain and failing would cost something.
  - A **failed** roll costs only what was tried for. A failed read, search or recall means the character learns nothing extra; it never makes an NPC colder, more suspicious or hostile.
  - NPC attitude follows the character's words and deeds, not the dice. People notice an attempt only when the action itself shows (a lie, a threat, a clumsy grab).
  - The fix is at the root, in three places:
    - the intent heuristic no longer falls back to Insight (72% of rolls were Insight);
    - intent no longer forces a skill onto every action;
    - action resolution no longer defaults to a check.
  - In addition, the intent and GM prompts state the rule, and unseen checks (Insight, history and similar) no longer reach NPC reactions.
  - The old behaviour is kept as the opt-in `baseline` behaviour variant (`variant: "baseline"`) for A/B runs.
  - Status: [ex-tales-forge PR #56](https://github.com/whyse-ab/ex-tales-forge/pull/56) is open and waits for Fredrik's approval. It is not merged or deployed.
- **Why:** in the Jev analysis, the rules engine rolled Insight on 72% of turns (155 of 216), even for ordering ale, and those checks failed about 70% of the time.
  - The GM then narrated each failure as the NPC turning colder: 87% of failed turns had cold phrasing.
  - Within a run, a failed check cost about −0.35 on the turn score, and 9 of the 10 lowest non-Hawk turns were failed checks.
  - In short, the dice punished players for talking.
- **Details:** [Analysis: Jev scores 2026-10-07](analysis-jev-scores-2026-10-07.md), [PR #56](https://github.com/whyse-ab/ex-tales-forge/pull/56)

## 2026-10-07: GitHub team sign-in is the only login on production and playtest

- **Decision (from Fredrik, via Case):** "Sign in with GitHub", checked against the GitHub team `whyse-ab/tales-forge` (`ADMIN_GITHUB_TEAM`), is the only login on production (`tales-forge`) and playtest (`tales-forge-playtest`) for now.
  - Email magic-link sign-in is disabled: its routes, the email form and the code that sent the links are gone, and old email-only sessions no longer count. The `ADMIN_EMAILS` allowlist no longer lets anyone in.
  - Every page and LiveView needs a signed-in team member: play, character creation (and any route added later), admin, costs, code docs at `/admin/code-docs`, and playtest run reports. Only the login page, the GitHub OAuth request and callback, and the health check (`/health`; the Fly checks move off `/`) are open, plus the static files the login page needs and the token-guarded machine-to-machine `/internal/costs`. Anyone else is sent to the login page. A GitHub user who isn't on the team is refused there with a short message.
  - No separate admin login: any signed-in team member gets the admin pages, with no extra admin check or second login step. The team check is the single gate.
  - Status: [ex-tales-forge PR #54](https://github.com/whyse-ab/ex-tales-forge/pull/54) is open and waits for Fredrik's approval. It is not merged or deployed, so this takes effect when it is.
- **Why:** both apps were publicly reachable, and Fredrik doesn't want that. No unauthenticated route, LiveView event or endpoint may start an AI call. The AI entry-point audit is in the PR.
- **Supersedes:** [2026-10-06: Sign-in](#2026-10-06-sign-in) (admin uses email magic links, logins last 30 days). Logins still last up to 30 days, with team membership rechecked on every request.
- **Details:** [ex-tales-forge PR #54](https://github.com/whyse-ab/ex-tales-forge/pull/54), [GitHub sign-in](infrastructure.md#github-sign-in-for-the-admin), [Fly secrets](fly-secrets.md)

## 2026-10-07: Clarification: the Tuckman phase belongs to the group, not the character

- **Clarification (from Fredrik, via Case):** the Tuckman phases (forming, storming, norming, performing, adjourning) are a property of a team or group (party, gang, council), not a character attribute.
  - A Character references its group membership(s), and the phase lives on the Group.
  - Wherever a character's behaviour depends on the phase, the phase is read from the group. That includes the companion rule ("decide by their reaction, concerns and party phase").
- **Applies to:** the [2026-10-07 seven design answers](#2026-10-07-one-character-entity-the-seven-design-answers). In answer 4 (companions), "party phase" means the phase of the companion's party group. In the "Why", Tuckman is listed among the levers, but it is the group's lever, not one each character holds. That entry is unchanged otherwise.
- **Why:** a phase describes how a group works together. Storing it per character would let members disagree about their own group's phase and would need syncing on every group event.
- **Details:** [World agents: character levers](design-world-agents.md#character-levers-design-not-built), [Plan: one Character entity, section 3](plan-unify-character.md#3-levers-mapped-onto-character). The code has no Tuckman or phase field on characters (checked on ex-tales-forge `main`, `e867f16`).

## 2026-10-07: Characters: defaults, rescale, backfill and double-write (#50, #51)

- **Decision:** approved by Fredrik on 2026-10-07 at 15:49: "Yes, merge #50 and #51, deploy, and run the backfill on prod and playtest".
  - [#50](https://github.com/whyse-ab/ex-tales-forge/pull/50) (merge `8d8efc3`, production v47, playtest v35): `Characters.Defaults` (a global label list extended per pack, seeded per-character variation, validated overrides) and NPC skills on the PC scale.
  - [#51](https://github.com/whyse-ab/ex-tales-forge/pull/51) (merge `e867f16`, production v48, playtest v36): backfill of existing sessions, and a double-write of the `characters` rows after every turn.
  - The release migrate step passed on both apps. Nothing reads `characters` yet.
- **Backfill (2026-10-07, about 15:58):**

| App | Before | Run 1 | Run 2 | After |
|---|---|---|---|---|
| Production | 0 characters, 0 memories (5 sessions, 15 `npc_instances`) | inserted 20, memories 3, failed none | inserted 0 | 20 (5 PC + 15 NPC), 3 memories |
| Playtest | 8 characters (2 PC + 6 NPC), 0 memories (22 sessions, 63 `npc_instances`, 18 playtest runs) | inserted 77, memories 141, failed none | inserted 0 | 85 (22 PC + 63 NPC), 141 memories |

  - Every playtest-run PC has controller `bot` with the run's persona as its reference: paul 13, lotta 2, hawk 1, lars 1, ronny 1. The other 4 playtest PCs and all 5 production PCs are `player`.
- **Check run:** Paul on playtest, 5 turns, Tin Valley.
  - The rows were updated after each turn: memory rows landed with turns 2–5, and the PC's learning points moved.
  - The new session's NPCs have the rescaled skills (innkeep persuasion 8, insight 8, etiquette 4).
  - No double-write errors in the logs.
  - Jev session affect 4.28 (confidence 0.63).
  - Game cost $0.0402 ($0.0080/turn; GM alone $0.0293), cache hits 4/4. Persona cost $0.0082 is logged separately.
- **Why:**
  - It completes phase 1: every PC and NPC now has a `characters` row that stays in step with play. That is the precondition for phase 2 (the read switch).
  - The rescale gives NPCs and PCs one skill scale without hand re-authoring.
- **Known gaps:**
  - The double-write runs after the turn, so an NPC change made outside a turn, or a memory written late in a turn, lands at the next turn.
  - Levers and OCEAN are set only when a row is first created.
  - Existing sessions keep their old NPC skill values.
- **Details:** [Plan: one Character entity, phased rollout](plan-unify-character.md#5-phased-rollout)

## 2026-10-07: Character defaults: the four answers

- **Decision:** confirmed by Fredrik on 2026-10-07 (via Case).
  1. **Label lists:** a global base list that each world pack extends.
  2. **Jev threshold:** confidence 0.6 to start. Every confidence is logged, and the threshold is tuned after playtests.
  3. **Variation:** small random variation, seeded per character (a hash of the session id plus the character key), so a character is stable on reload.
  4. **Player edits:** the player can edit everything Jev fills in, within the rules: stats within the point budget, OCEAN, concerns, background and name. This follows the per-section "own input or AI assist" flow.
- **Why:**
  - A shared base list keeps labels, tests and Jev questions consistent, while each world can still add its own occupations.
  - 0.6 is a cautious start that real playtest data can move.
  - Seeded variation stops two innkeepers from being clones without making a character change between page loads.
  - Player edits keep Jev as a helper, not a judge: 4 of 5 personas wanted per-section control.
- **Details:** [Plan: one Character entity, section 7.4](plan-unify-character.md#74-decisions-confirmed-by-fredrik-2026-10-07), [Plan: character creation port](character-creation-port.md#update-2026-10-07-derived-defaults-and-jev-direction-from-fredrik-via-case)

## 2026-10-07: Design direction: derived character defaults, and Jev for descriptions

- **Direction (from Fredrik, via Case):**
  - **Defaults:** stats, skills, OCEAN, Maslow level and concerns are derived in pure Elixir from class, race, social standing and occupation. The assumption is that people are reasonably skilled at their job and have a typical personality for the role.
  - **Notable characters** (the reluctant king, the sour barkeep) are hand-authored overrides on top of the defaults.
  - **Descriptions:** turning a free-text description into a Character is one Jev call (unstructured in, structured out). The same call serves player character creation: the player describes their character, Jev returns fixed labels with confidence, and the defaults fill the gaps.
- **Why:**
  - Most characters come out right with no authoring and no LLM.
  - Authors spend their time only on the characters that matter.
  - One skill scale falls out of occupation tiers, which is decision 5 without hand re-authoring.
  - Creation is fast and cheap (one Jev call, under $0.001) and keeps working when Jev is unsure or down.
  - It follows the call-types rule: structured answers from Jev and Elixir, not from an LLM.
- **Not yet decided:**
  - the label lists (per world or global);
  - the confidence threshold;
  - jitter;
  - what a player may edit;
  - whether a prose LLM call stays for the backstory.

  The derivation module lands with the skill-rescale PR. Jev for players lands with the character creation port, after phase 2.
- **Details:** [Plan: one Character entity, section 7](plan-unify-character.md#7-defaults-from-class-race-standing-and-occupation-jev-for-descriptions), [Plan: character creation port](character-creation-port.md#update-2026-10-07-derived-defaults-and-jev-direction-from-fredrik-via-case)

## 2026-10-07: Characters phase 1 merged and deployed (#48)

- **Decision:** ex-tales-forge PR #48 is merged (main `326c8ae`) and deployed: production v45, playtest v33. Approved by Fredrik ("Yes, merge #48 and deploy").
  - New tables `characters` and `character_memories`.
  - New sessions write one character per PC and NPC; nothing reads them yet.
  - Every pack NPC and PC file has `maslow` and `concerns`, checked at load time.
  - Elara now lives in the packs.
- **Why:** this is the setup step of the [Character plan](plan-unify-character.md), and it carries no behaviour change. A golden test keeps the GM prompts byte-identical.
- **Checked after deploy:**
  - Both release_command migrations passed, and both tables exist.
  - `/` returns 200, and logged-out admin pages redirect to login.
  - Packs and NPC files load with no validation errors.
  - A playtest Paul run completed 5 turns. It wrote 4 characters: Elara with controller `bot` (ref `paul`), plus 3 NPCs with controller `gm`.
  - Costs are logged: game $0.040, persona $0.0082 kept separate.
  - Logs show no app errors. The only health-check failure was during the restart.
- **Cost:** GM cost was $0.0081 per turn, back to the usual ~$0.008. The previous run's $0.0114 came from prompt-cache misses on turns 3 and 5 (2 of 4 later turns hit; this run 4 of 4). Each miss costs about $0.012 instead of $0.004–0.005. The 429 itself cost nothing: the failed call has no cost. Prompt size is the same in both runs (9,200–9,650 input tokens per GM call), so neither the prompt nor the token count changed.
- **Not yet:** backfill of older sessions, dual-write of per-turn changes, and the NPC skill rescale. These come in the next PR.
- **Details:** [ex-tales-forge PR #48](https://github.com/whyse-ab/ex-tales-forge/pull/48), [Plan: one Character entity](plan-unify-character.md)

## 2026-10-07: One Character entity: the seven design answers

- **Decision:** confirmed by Fredrik on 2026-10-07 (via Case). These are the answers to the open questions in the Character plan:
  1. **Scope:** characters are per session for now, but the schema is ready for a character to belong to a player and carry over (`owner_player_id`, `origin`). The persistent-world option (B) stays open in the design.
  2. **PC levers:** PCs get OCEAN, a Maslow level and concerns, visible on the character sheet.
  3. **AFK:** solo play pauses. In a party the GM takes over an absent PC after a timeout.
  4. **Companions** decide by their reaction, concerns and party phase, not by obeying.
  5. **Skill scale:** NPC skills are rescaled to the PC scale, and the trainer gap rule is re-checked.
  6. **Memory:** one shared events table (the existing `session_events`) plus per-character, personality-filtered memory rows.
  7. **Controller:** `player | gm | bot`. The persona runner uses `bot`.
- **Why:** with one shape for PCs and NPCs, every lever (OCEAN, Maslow, concerns, Tuckman, perception) works the same for everyone. Per session keeps phase 1 small and matches today's data, and the owner column means carry-over needs no second migration. One shared record of each event, with a personal memory of it per character, avoids copying facts while letting characters remember the same event differently. The `bot` controller keeps playtest data and costs apart from real players.
- **Details:** [Plan: one Character entity, section 6](plan-unify-character.md#6-decisions-confirmed-by-fredrik-2026-10-07)

## 2026-10-07: To try: living world

- **To try (not a final decision):** an unscripted world in which nothing waits for the player.
  - Factions and antagonists are agents with goals, plans, clocks, resources and a memory of who helped or hindered them.
  - A world tick (Oban cron, plus each turn's own ticks) advances their plans on world time, between sessions and during them. Most of the tick is Elixir functions.
  - Jev reacts for a faction when an event touches it.
  - The GM narrates only what a character perceives (direct encounters, news, rumours), following the perception rules.
  - Example: if nobody stops the Mining Guild, they dig too deep and something gets loose; if the player stops them, the Guild remembers and acts on it. Acting and not acting both have consequences.
  - Direction from Fredrik (via Case).
- **Why:** a world that moves on its own makes choices matter and gives emergent stories without scripting. Cost stays bounded: a world nobody visits costs well under $0.001 per world-day, and a played one adds a few tenths of a cent per day on top of the turns.
- **Depends on:** characters and world state that outlive one session (option B of Q1 in the Character plan). For now characters are per session but ready to belong to a player.
- **Details:** [Design: world agents, living world](design-world-agents.md#living-world-design-to-try), [Plan: one Character entity](plan-unify-character.md)

## 2026-10-07: Ash removal merged and deployed (#47)

- **Decision:** ex-tales-forge PR #47 is merged (main `a564e95`) and deployed: production v44, playtest v32. Ash, ash_postgres, ash_phoenix and igniter are gone, and the admin session and NPC forms use Ecto changesets. The NPC definition pages are read-only views of the pack files; Fredrik can veto this and get a small file-only editor back. The migration dropped the `adventures`, `locations` and `npc_definitions` tables. Approved by Fredrik ("Yes, merge #47 and deploy once the recount shows the tables are empty").
- **Why:** a recount right before the merge found all three tables empty on both apps. The release shrinks from 99.1 to 88.3 MB, and lib loses about 2,000 lines.
- **Checked after deploy:**
  - Both release_command migrations passed.
  - The three tables no longer exist.
  - `/` returns 200, and logged-out admin pages redirect to login.
  - As admin (in-machine request), the session form, NPC form and read-only definition page load.
  - A playtest Paul run completed 5 turns with costs logged: game $0.057, persona $0.0086 kept separate.
  - Logs show no app errors. One xAI 429 "at capacity" on a GM call was retried and succeeded.
- **Details:** [ex-tales-forge PR #47](https://github.com/whyse-ab/ex-tales-forge/pull/47), [Plan: remove Ash](plan-remove-ash.md)

## 2026-10-07: Ash removed for now; plain Ecto; revisit if an in-app adventure editor needs it

- **Decision:** ex-tales-forge drops Ash (`ash`, `ash_postgres`, `ash_phoenix`) and uses plain Ecto everywhere. The authoring layer (Adventure, Location, NpcDefinition and the pack importer) goes, the two admin edit forms move to Ecto changesets, and the three empty authoring tables are dropped. Revisit Ash if an in-app adventure editor needs it. Decided by Fredrik (via Case). **Supersedes the Ash part of "Elixir is the platform" below**; Phoenix LiveView, Oban and Jido stay.
- **Why:** only the authoring layer used Ash. Its three tables (`adventures`, `locations`, `npc_definitions`) are empty on prod and playtest, and the game reads its content from the pack files. The admin forms already have Ecto schemas underneath. Removing it cuts about 1,800 lines and about 11 MB of release, and leaves one data-access style for humans and bots to learn.
- **Details:** [Plan: remove Ash](plan-remove-ash.md), [Module audit](module-audit-2026-10-07.md). Done: merged and deployed as [#47](https://github.com/whyse-ab/ex-tales-forge/pull/47) (entry above).

## 2026-10-07: Code docs: ExDoc's JavaScript allowed past the admin CSRF check

- **Decision:** ex-tales-forge PR #45 is merged and deployed to production and playtest. Files served from the docs folder at `/admin/code-docs` skip Plug's cross-origin JavaScript check. The admin login check is unchanged. Approved by Fredrik ("Yes, open the fix PR, merge it and deploy once CI is green").
- **Why:** after #44 the pages loaded but every ExDoc script got 403, so the sidebar was empty and search didn't work. The files are static and hold no tokens. The session cookie is SameSite=Lax, so another site's `<script>` request has no admin session and is still redirected to login. The tests now run with CSRF protection on, which the test helpers turn off by default and which hid the bug.
- **Details:** [ex-tales-forge PR #45](https://github.com/whyse-ab/ex-tales-forge/pull/45), [PR #44](https://github.com/whyse-ab/ex-tales-forge/pull/44)

## 2026-10-07: Code docs served admin-only at /admin/code-docs

- **Decision:** ex-tales-forge PR #44 is merged and deployed to production and playtest. Each release builds the ExDoc site in the Docker builder stage (about 4 MB in the image, ex_doc itself stays out of the release) and serves it at `/admin/code-docs` behind the admin login, with a "Code docs" link in the admin nav. Approved by Fredrik ("Yes, merge #44 and deploy").
- **Why:** the documented code (see coding standards) should be readable where we already work, without a local build, and not public.
- **Details:** [ex-tales-forge PR #44](https://github.com/whyse-ab/ex-tales-forge/pull/44), [Coding standards](coding-standards.md)

## 2026-10-07: Coding standards: documented, typed, tested, enforced in CI

- **Decision:** every module has a `@moduledoc` and every public function a `@doc` (with doctests where sensible) and a `@spec` checked by Dialyzer. Credo strict, `mix format`, ExDoc for a browsable docs site, tests for every change with coverage tracked. CI enforces format, Credo, Dialyzer, tests with coverage and the docs build, so failing PRs can't merge. Existing modules are backfilled gradually, starting with the core GM, Character/Person and world-agent modules. Fredrik's standard, relayed by Case.
- **Why:** humans may need to understand the code one day, including code written by coding bots.
- **Details:** [Coding standards](coding-standards.md), [ex-tales-forge PR #43](https://github.com/whyse-ab/ex-tales-forge/pull/43)

## 2026-10-07: Merge the runner fix and world agents round 2, world agents still off

- **Decision:** ex-tales-forge PR #41 (the playtest runner ignores a stale "turn finished" message, which caused a double turn 2) and PR #42 (world agents round 2: prices from code and facts read from the narration) are merged and deployed. `WORLD_AGENTS` stays off in production and playtest; `NPC_REACTIONS` stays on in playtest only. Approved by Fredrik ("Merge #41 and #42 and deploy").
- **Why:** the runner fix makes playtest runs complete and comparable. Round 2 costs nothing while the flag is off, and having it on main lets the next round build on it.
- **Details:** [ex-tales-forge PR #41](https://github.com/whyse-ab/ex-tales-forge/pull/41), [PR #42](https://github.com/whyse-ab/ex-tales-forge/pull/42), [Design sketch: world agents](design-world-agents.md#round-2-results-2026-10-07)

## 2026-10-07: World agents round 2: prices from code, facts read from the narration

- **To try (not a final decision):** Elixir, not the GM, quotes prices. When the player's words mention something with a listed price, the server puts "Price: Bowl of stew, 5 copper" in the GM's per-turn data, or charges the coins itself and says "Purchase: …, paid". After the turn, off the critical path, one small LLM call (`fact_extract`, conv id `<session>:facts`) reads the finished narration for new facts and NPC promises; Elixir validates and stores them for the owning agent. The GM's own `new_facts` field is dropped.
- **Why:** in round 1 the GM still got prices wrong with the price in its facts, and it filled `new_facts` once in 20 turns. Prices are structured data, so code should state them (the call-type rule). Jev can't write text, so extraction is an LLM call.
- **Details:** [Design sketch: world agents](design-world-agents.md#round-2-results-2026-10-07), [ex-tales-forge PR #42](https://github.com/whyse-ab/ex-tales-forge/pull/42)

## 2026-10-07: NPC reactions on in playtest

- **Decision:** `NPC_REACTIONS=on` on tales-forge-playtest only (a Fly secret, like the other playtest switches); `WORLD_AGENTS` stays off there. Approved by Fredrik.
- **Why:** to see the Jev reaction (Brenna's mood and stance before each GM turn) in real playtests. The first Lotta check logged one `npc_reaction` row per turn (~$0.00004, 216–407 ms) and Brenna's replies varied, though she grew steadily warier over 5 turns.
- **Details:** [Fly secrets](fly-secrets.md), [Design sketch: world agents](design-world-agents.md#the-brenna-reaction)

## 2026-10-07: Merge the NPC reaction and world-agent prototype, off by default

- **Decision:** ex-tales-forge PR #40 is merged with both `NPC_REACTIONS` and `WORLD_AGENTS` off by default; production runs with both off. Approved by Fredrik ("Put it all in - I like it").
- **Why:** both flags cost nothing when off, the cached prefix is unchanged (prefix test), and having the code on main lets playtest and the next round build on it.
- **Details:** [ex-tales-forge PR #40](https://github.com/whyse-ab/ex-tales-forge/pull/40), [Design sketch: world agents](design-world-agents.md)

## 2026-10-07: To try: world agents hold facts

- **To try (not a final decision):** world agents (persons, locations, items, maybe animals) hold facts; the GM asks them for facts before narrating, and facts the GM invents are written back to the owning agent.
- **Why:** the prose-GM prototype drifted on lore (harpies instead of the orc nest) and on prices (a room for 2, 3 or 8 silver), and NPCs forgot promises. Facts kept by agents and sent per turn should keep the world consistent while the cached GM prefix stays small and stable.
- **Details:** [Design sketch: world agents](design-world-agents.md)

## 2026-10-07: Measure every call and turn step by call type

- **Decision:** every `ai_calls` row has a `call_type` (`function`, `jev`, `llm`) and adventure and game-system tags; the main Elixir steps of a turn are timed as zero-cost `function` rows. `/admin/costs` and playtest run reports show cost and p50/p90 latency per call type and purpose, the cache hit rate and the idle gap before each GM call, with persona cost kept apart.
- **Why:** so the call-type rule, caching and pricing can be checked with numbers instead of guesses.
- **Details:** [ex-tales-forge PR #39](https://github.com/whyse-ab/ex-tales-forge/pull/39), [Call types: recording call types and metrics](call-types.md#recording-call-types-and-metrics)

## 2026-10-07: Each bot call gets its own conversation id

- **Decision:** persona, scorer and intent calls send `x-grok-conv-id` `<session>:<purpose>`; only the scene and GM calls share the session id.
- **Why:** the persona bot's calls on the session id pushed the GM prompt out of xAI's cache between turns, so GM calls missed the cache.
- **Details:** [ex-tales-forge PR #37](https://github.com/whyse-ab/ex-tales-forge/pull/37)

## 2026-10-07: No length limits in the GM reply schema

- **Decision:** the strict GM/scene reply schema has no `maxLength` or `maxItems`; the caps on notes, summary and NPC memories are applied in code when the reply is parsed.
- **Why:** with `maxLength`/`maxItems` in the schema xAI does not reuse the prompt cache at all (every GM call reported 128 cached tokens); without them the same request reuses ~9k tokens.
- **Details:** [ex-tales-forge PR #36](https://github.com/whyse-ab/ex-tales-forge/pull/36)

## 2026-10-07: Elixir is the platform

- **Decision:** Tales Forge is built on Elixir: Phoenix LiveView, Ash, Oban and Jido. Decided by Fredrik, who funds the project.
- **Superseded in part:** the Ash part is superseded by [Ash removed for now; plain Ecto](#2026-10-07-ash-removed-for-now-plain-ecto-revisit-if-an-in-app-adventure-editor-needs-it) (2026-10-07).
- **Why:** the BEAM fits a soft real-time, always-on game with many concurrent sessions and agents.
- **Details:** [Why Elixir](why-elixir.md) (copy of the Google Doc [Why Elixir](https://docs.google.com/document/d/19w4sYfea-OamyPrnMk44hhbuVFDU9kKXirkqR_jjmtE))

## 2026-10-07: Decisions are recorded in this file

- **Decision:** decisions are recorded in this file, in this repo.
- **Why:** one place to see what was decided and why, with git history as the audit trail.

## 2026-10-07: Docs go straight to main

- **Decision:** documentation is committed straight to `main` in this repo, without pull requests; if something is wrong, undo it. Code still goes through pull requests, with Fredrik's OK before merge or deploy.
- **Why:** docs are cheap to fix and slow to review; code reaches players, so it keeps the review gate.
- **Details:** [Environments](environments.md) (how code reaches production)

## 2026-10-07: Call-type rule

- **Decision:** known structured input + structured output = Elixir function; unstructured input + structured output = Jev; prose output = LLM. Asking the LLM for structured output is a smell.
- **Why:** Elixir is exact, free and instant, Jev is fast and cheap, and the LLM is the slowest and most expensive; output length drives GM latency.
- **Details:** [Call types](call-types.md)

## 2026-10-07: GM pipeline direction

- **Decision:** Jev validates player input up front, so the GM prompt needs little hardening. Jev's intent plus Elixir's rules and rolls go to the GM as a typed struct with a short quote of the player's words. The GM uses a non-thinking model.
- **Why:** the GM only narrates prose, which makes turns faster and cheaper while keeping the player's tone.
- **Details:** [Call types: target turn pipeline](call-types.md#target-turn-pipeline)

## 2026-10-07: One Character type

- **Decision:** player characters and NPCs are technically identical (OCEAN personality, personality-filtered memory, Maslow level); only the controller differs (player or GM). NPCs run as their own Elixir agents with Jev gut reactions (System 1).
- **Why:** the GM can play an absent player's character with the same data and calls, and parties become possible later.
- **Details:** [Call types: character model](call-types.md#character-model)

## 2026-10-07: Measure cost and time per call type

- **Decision:** measure cost and time per call type (function, Jev, LLM) and per world/module, including cache hit rate.
- **Why:** so the call-type rule and pricing can be checked with numbers.
- **Details:** [Call types: recording call types and metrics](call-types.md#recording-call-types-and-metrics)

## 2026-10-07: Pricing direction (draft)

- **Decision:** no monthly subscription. Prepaid play time, billed only on GM response time; idle time is free. First character free. Working numbers: $1 per real hour, $3 starter, $5/$10/$20 top-ups.
- **Why:** players pay for what they use, and slow or casual play isn't punished.
- **Details:** [Pricing: a pool of play time](pricing-time-pool.md)

## 2026-10-07: All amounts in USD

- **Decision:** all amounts are in USD.
- **Why:** one currency for costs, prices and reports.

## 2026-10-07: Jev persona-affect scoring

- **Decision:** Jev scores persona affect 1-5 (frustrated to delighted) with confidence, per session and per turn, reading only player and GM spoken text, never hidden GM notes.
- **Why:** a cheap, typed signal of how a session felt, based only on what the player actually saw.
- **Details:** [Jev persona-affect scoring](jev-scoring.md)

## 2026-10-06: Character creation

- **Decision:** copy the working flow from tales-forge.ai, then move to a hybrid where each section (stats, background, social class, origin) offers own input or AI assist.
- **Why:** the old flow works today, and 4 of 5 personas preferred the per-section hybrid.
- **Details:** [Character creation port](character-creation-port.md), [persona preferences](character-creation-persona-prefs.md)

## 2026-10-06: The GM opens the scene

- **Decision:** the GM always opens the scene; players respond.
- **Why:** players start with something to react to instead of a blank prompt.

## 2026-10-06: One admin costs page

- **Decision:** all costs (Fly, Resend, domain, AI, GitHub) are shown on one admin costs page.
- **Why:** total running cost in one place.
- **Details:** [Infrastructure assets](infrastructure.md)

## 2026-10-06: Playtesting

- **Decision:** one end-to-end smoke test until all personas are ready, then intense bursts. Persona-bot time and tokens are measured separately from the game's own numbers.
- **Why:** don't spend on bot play before it's useful, and keep game cost figures clean.
- **Details:** [Design: playtest loop](design-playtest-loop.md), [Personas](personas.md)

## 2026-10-06: Branching and environments

- **Decision:** one always-deployable `main` with short-lived feature branches, per-PR preview apps, and a separate long-lived playtest Fly app. Bots need Fredrik's explicit OK before any deploy or merge of code.
- **Why:** production stays stable while bots and founders try changes safely.
- **Details:** [Environments](environments.md)

## 2026-10-06: Separate API keys per environment

- **Decision:** separate API keys per environment (xAI production vs playtest; TypeSafe per environment).
- **Why:** so costs split by environment, and one key can be revoked without breaking the other.
- **Details:** [Adding API keys and secrets to Fly](fly-secrets.md)

## 2026-10-06: Sign-in

- **Decision:** admin uses email magic links (no passwords), and logins last 30 days. Founders playtest via GitHub login, checked against the whyse-ab tales-forge team.
- **Why:** no passwords to store or leak, and founder access follows GitHub team membership.
- **Details:** [Setting up Resend](resend-setup.md), [Infrastructure assets](infrastructure.md)

## 2026-10-06: tales-forge.ai stays on Netlify for now

- **Decision:** tales-forge.ai stays on the existing Netlify site until the new Fly app is a working prototype.
- **Why:** players keep a working game until the replacement is ready.
- **Details:** [Infrastructure assets](infrastructure.md), [Environments](environments.md)

## 2026-10-05: North star

- **Decision:** the north star is the first paying customer the founders don't personally know.
- **Why:** everything is ordered by how much it brings that customer closer.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: No assigning tasks

- **Decision:** nobody assigns tasks to people; founders self-assign. Plans are ordered lists, most important first.
- **Why:** founders choose their own work; the order says what matters most.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: Fantasy first, own content first

- **Decision:** launch with fantasy only. The team builds the world and modules itself first; an author marketplace comes later.
- **Why:** prove the game in one genre with content we control before opening it up.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: Acquisition

- **Decision:** RPG forums first, then word of mouth.
- **Why:** forums bring the first players; sharing brings the next ones.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## Open questions

None right now. (Prose-only GM vs structured reply format: decided on 2026-10-08, see [the prose-only GM prototype is dropped](#2026-10-08-the-prose-only-gm-prototype-is-dropped-the-gm-has-one-structured-reply-mode).)
