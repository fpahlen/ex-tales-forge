---
title: Decision log
updated: 2026-10-08
---

# Decision log

Decisions made by the founders. Newest at the top. Each entry: date, decision, why, link to details. Changing a decision means adding a new entry that supersedes the old one.

Open questions waiting for a decision live in the [decision queue](../decisions/README.md); once decided, they are recorded here.

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
  - Status: not started; no PR yet.
- **Why:** in 62% of runs the player tries to leave the inn, and after 38 of 65 such attempts the GM is still describing the inn or Brenna on the next turn. In Paul's two weakest runs the GM walks him to the Market Square and then answers his speech to Osric as Brenna, back at the bar; neither run registered a scene change. With only the inn to play in, each persona runs out of things it likes (Hawk gets chores, Lars's adventure is deferred).
- **Details:** [Analysis: Jev baseline 2026-10-07, §4 and recommendation 1](analysis-jev-baseline-2026-10-07.md), [Design: world agents](design-world-agents.md), [PR #68](https://github.com/whyse-ab/ex-tales-forge/pull/68) (scene changes), [PR #72](https://github.com/whyse-ab/ex-tales-forge/pull/72) (inn world, `INN_WORLD`)

## 2026-10-07: Hawk gets real conflict: a minor antagonist who acts on their own

- **Decision (Fredrik, via Case):** Hawk gets real conflict. A **minor antagonist** stirs up trouble in or near the village and **acts on their own**, whether or not the player engages. This follows the living-world and factions direction: an agent with a goal and a plan that moves on world time. It is **not a scripted fight**.
  - This builds on [To try: living world](#2026-10-07-to-try-living-world) and makes a small first case of it a decision for Tin Valley.
  - Status: not started; no PR yet.
- **Why:** Hawk almost never meets danger. His turn mean is 1.93, only 4 of 13 runs reach a turn scoring 3 or more (never before turn 8), and his session score is 2.54 without a fight roll against 4.61 with one. Brenna's "lend a hand" hooks have him hauling kegs. A scripted fight would fix the number once; an antagonist who moves on their own gives danger that the player's choices change.
- **Details:** [Analysis: Jev baseline 2026-10-07, §1, §4 and recommendations 2–3](analysis-jev-baseline-2026-10-07.md), [Design: world agents, living world](design-world-agents.md#living-world-design-to-try), [PR #73](https://github.com/whyse-ab/ex-tales-forge/pull/73) (Tinjacks antagonist, `WORLD_ANTAGONIST`), [PR #71](https://github.com/whyse-ab/ex-tales-forge/pull/71) (fights roll)

## 2026-10-07: Skill growth: spend 1 LP for one improvement attempt (supersedes the tiered thresholds)

- **Decision (Fredrik, via Case):** a new skill growth rule.
  - Spending **1 LP buys one improvement attempt** on that skill.
  - Roll **d20**. If the result is **equal to or higher than the current skill level**, the skill gains **+1**.
  - More LP means more attempts.
  - This **supersedes** the progression part of [Skill rules ported from the old game](#2026-10-07-skill-rules-ported-from-the-old-game-signature-skills-up-to-7-growth-no-longer-stalls) ([#64](https://github.com/whyse-ab/ex-tales-forge/pull/64)): the 5 / 7 / 10 / 15 LP tier thresholds, the failure requirement, the rest requirement and the tiered thresholds are gone. It also supersedes item 4 ("growth pace stays as it is for now") of [Skill rules: the open questions answered](#2026-10-07-skill-rules-the-open-questions-answered). LP are still earned per roll as before, including the stat bonus.
  - Status: [ex-tales-forge #67](https://github.com/whyse-ab/ex-tales-forge/pull/67) is open and waits for Fredrik's approval; not merged or deployed. In it: attempts happen at the end of every turn (every whole LP is spent), a trainer gives one free attempt at +5, and the Expert −3 / Master −5 modifiers are removed. The `baseline` variant keeps the #64 rule.
- **Why:** skill growth has stopped. The baseline averages about 1.0 LP per run, and there were **0 improvement attempts in 65 runs**: an attempt needed 5 LP, a failure and a rest of an hour, and almost no run had all three. With one attempt per LP, every LP is a visible chance to grow, and the d20 ≥ level roll slows growth naturally as a skill gets higher (a success chance of (21 − level)/20).
- **Details:** [Analysis: Jev baseline 2026-10-07, §6 and recommendation 7](analysis-jev-baseline-2026-10-07.md), [character creation port: growth rule replaced](character-creation-port.md#growth-rule-replaced-2026-10-07-1-lp--one-improvement-attempt), [PR #67](https://github.com/whyse-ab/ex-tales-forge/pull/67)

## 2026-10-07: How the GM plays Brenna: no default echo, no stock tics

- **Decision (Fredrik, via Case):**
  - The GM does **not** echo or restate the player's line by default. It answers the action instead of re-narrating it.
  - Echoing the player's last few words is allowed only as a **deliberate, rare negotiator move** by a character, to draw the player out ("…the old shaft?"). It is never a turn opener by habit.
  - Brenna's "on the house" generosity default goes. A freebie needs a reason in the story.
  - The stock gesture "tilts her head (toward)" goes, along with the other new tics the baseline found.
  - This refines the prose rules in [Brenna is a warm, chatty barkeep](#2026-10-07-brenna-is-a-warm-chatty-barkeep-a-lead-by-turn-2-gm-prose-cleanup): "no echoing the player's words" stays, and the rare deliberate echo is now the one exception. Brenna stays warm and chatty.
  - Status: PR open, [ex-tales-forge #70](https://github.com/whyse-ab/ex-tales-forge/pull/70), not merged.
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
  - Status: PR open, [ex-tales-forge #69](https://github.com/whyse-ab/ex-tales-forge/pull/69), not merged.
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
