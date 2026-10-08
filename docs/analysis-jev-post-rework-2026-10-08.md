---
title: "Analysis: Jev after the inn-world, scene-change and Brenna rework (2026-10-08)"
updated: 2026-10-08
status: analysis
---

# Analysis: Jev after the inn-world, scene-change and Brenna rework (2026-10-08)

**Question:** ex-tales-forge #67–#73 shipped the fixes the [2026-10-07 baseline](analysis-jev-baseline-2026-10-07.md) asked for. They record scene changes when the character leaves (#68), add places and people around the inn (`INN_WORLD`, #72) and the Tinjacks antagonist on world time (`WORLD_ANTAGONIST`, #73), make more attack phrasings roll (#71), stop Brenna's echo and tics (#70), switch growth to 1 LP = one attempt (#67) and make the Jev rubric stricter for Paul and Lotta (#69). A small series on playtest with the new code is compared here with the baseline. Paul and Lotta use the new rubric on both sides. What moved?

**Short answer:** The mechanics changes worked. The scores barely moved, and 5 runs per persona can only show large effects.

1. **Leaving the inn works now.** 12 of 23 runs left the inn with a recorded scene (18 scene changes; the baseline recorded none). After a leave attempt, the next GM turn still describes the inn or Brenna on **3 of 13** attempts (23%), against **38 of 59** (64%) in the baseline. Read by hand, none of the three snaps back to Brenna's bar: two are not real attempts, and in the third the GM narrates the yard but no scene is recorded.
2. **Echo and tics are mostly gone.** The GM repeats an 8-word run of the player's line on **5.0%** of turns, against 22.2% (Lotta: 20% against 52%). "On the house" is down from 75% to **22%** of runs, and every remaining case is tied to help, a job or a safe return ("if you lend a hand"). "Tilts her head toward" is down from 36/65 runs to **4/23**. **"Wipes her hands" is still in 13 of 23 runs (57%)** even though #70 bans it, and new gestures took the old ones' place.
3. **The Tinjacks act on their own in every run.** Incident at turn 3 and confrontation at turn 6 in **23 of 23** runs. Rusk and Cobb come to the inn for their toll and are named in 16 runs. **Hawk:** session 3.34 against 3.02 (+0.32, 95% CI −0.41…+1.03). His runs **without a fight** rise from 2.54 to **3.14 (+0.60, CI +0.01…+1.05)**. His floor went from 1.78 to 3.08, and his turns 11–12 from about 2.4 to about 3.0. But only **1 of 5** Hawk runs rolled a fight, on the last turn (a failure against Cobb). Nobody broke the gang.
4. **Scores, like for like:** Paul 4.77 against 4.73 (session), Lotta 4.21 against 4.31, Lars 4.05 against 4.04, Ronny\* 4.09 against 4.37. No session difference is distinguishable from zero. **Paul's turn mean is slightly lower:** 4.24 against 4.36 (−0.12, CI −0.21…−0.03; turns 1–5 −0.10, CI −0.17…−0.04).
5. **Growth now happens:** **20 attempts and 13 levels gained in 23 runs** (0.57 levels per run), against 0 attempts in 65 runs. There is no runaway: at most **+4 levels in a run** (Lars, melee +3 from 4 combat rolls). Ronny rolled nothing and gained nothing.
6. **New problem: turns that hang.** 3 of 26 runs stopped on the turn timeout (Lars twice at turn 3, Paul once at turn 7). Each time the Tier 1 intent call had just returned (`source=llm`), and then nothing more was logged. The series ended with **Paul 5, Hawk 5, Lotta 5, Lars 4 and Ronny 4** completed runs (23 of 25).

**Cost:** 26 runs (23 done + 3 timed out) cost **$2.74**: game $2.10, persona $0.64, Jev $0.006. Per completed run that is **$0.114** (baseline: $0.093). Game cost per run is up 29%.

*Update 2026-10-08:* a confidence-aware reading of these scores (only the scores Jev is sure about count) is in [Update 2026-10-08: confidence-aware reading](#update-2026-10-08-confidence-aware-reading). It leaves the session deltas unchanged and makes Hawk's turn-level gain clear.

---

## Data and method

| | Runs | Turn scores | Personas (runs) | Window (CEST) |
|---|---|---|---|---|
| Series `post-rework-2026-10-08` on Fly `tales-forge-playtest` | 23 completed (+3 timed out, left out) | 240 | Paul, Lotta and Hawk 5 each; Lars and Ronny 4 each. 10 turns each, Hawk 12 | 06:18–07:27 (completed runs end 07:22) |
| Baseline `baseline-2026-10-07` (same app, SHA `2a6589e`) | 65 | 676 | 13 per persona, 10 turns each, Hawk 12 | 2026-10-07 19:29–21:33 |

- **Driver:** `/workspace/compare/drive.sh` is a copy of `/workspace/baseline/drive.sh` with `SERIES=post-rework-2026-10-08` and `ROUNDS=5`. It runs round-robin (paul, hawk, lotta, lars, ronny) and stops on any run that doesn't count as done. It stopped three times on a turn timeout (§9). It was resumed twice, and the third stop (round 5, Lars) ended the series. The day cap ($25) and xAI credits never bound. The playtest day's spend was $2.74 at the end, all from this series.
- **Run conditions** (all 26 runs; from `playtest_runs.git_sha` and `flags`, and from `world_state.features`):
  - git SHA **`9e7d447ca04642379d253da50a90dcefa107a93e`** (merge of #73; contains #67–#73), playtest release v59;
  - `variant=default`, `npc_reactions=on`, `world_agents=off`, `llm_provider=xai`, `gm_model` and `intent_model` = `grok-4.20-0309-non-reasoning`, Jev `jev-1.13.0`;
  - session features `inn_world, antagonist` in 26 of 26 runs. The run's `flags` field doesn't record `INN_WORLD` or `WORLD_ANTAGONIST` yet, so take them from the session;
  - rubric hashes: Paul `fd84ebb` and Lotta `ce84a1a` (new in #69), Lars `fc771be`, Hawk `129f728` and Ronny `e8f0786` (all unchanged).
- **Characters:** the same as the baseline (#60): Corvin Ashdown (Paul), Hilde Stonebrook (Lotta), Taren Swiftbrook (Lars), Brannoc Hale (Hawk) and Maxx Goldhand (Ronny). All runs are `tin_valley`.
- **Baseline re-scored with the new rubric** (Paul and Lotta, 26 runs). [`scripts/jev-rescore/rescore.exs`](scripts/jev-rescore/rescore.exs) ran on ex-tales-forge `main`'s `AffectLevels` (identical to #69's head) against the stored baseline transcripts. It used Jev only (52 calls: old and new rubric) and made no game calls. Raw rows: [`scripts/jev-rescore/rescore-baseline-2026-10-07-main.json`](scripts/jev-rescore/rescore-baseline-2026-10-07-main.json). Hawk, Lars and Ronny keep their stored scores, since their rubrics didn't change.

  | Baseline, 13 runs each | session mean (sd) | turn mean | turns 1–5 | turn argmax counts (130 turns) |
  |---|---|---|---|---|
  | Paul, old rubric | 4.66 (0.60) | 4.69 | 4.82 | 2: 1, 3: 4, 4: 1, 5: 124 |
  | **Paul, new rubric** | **4.73 (0.41)** | **4.36** | **4.27** | 2: 1, 4: 74, 5: 55 |
  | Lotta, old rubric | 4.41 (0.07) | 4.16 | 4.14 | 4: 130 |
  | **Lotta, new rubric** | **4.31 (0.28)** | **3.91** | **3.74** | 3: 23, 4: 97, 5: 10 |

  This reproduces the [pilot](jev-scoring.md#stricter-top-for-paul-and-lotta-2026-10-07) within ±0.11 per session (the same transcripts, so the gap is Jev's own run-to-run noise).
- **Scoring:** as before, Jev makes one call per run, and the turn scores have hindsight. The new series was scored automatically on deploy (first pass used). For re-scored baseline runs the turn confidences are unknown and left empty.
- **Scripts:** [`scripts/jev-compare/`](scripts/jev-compare/):
  - `export.exs` now also exports scenes, session events, fronts and session features;
  - `compare.py` gained `--reference` and `--rescore`;
  - `baseline_extra.py` runs on the new series;
  - new `post_rework.py` holds the head-to-head sections below.
  
  Text features are regexes. Every example quoted here was read.
- **Statistics:** bootstrap 95% CIs over runs (5000 resamples). Turn means and turns 1–5 are **one mean per run**.
- Data on the box: `/workspace/compare/final/` holds `jev_export.json`, `series.json` (both series), `series_done.json` (completed runs only), `report.md`, `post.md`, `extra.md`, `runs.csv`, `turns.csv` and `spend.txt`, with `all/` for all 26 runs including the timeouts. The driver log is `/workspace/compare/drive.log`. Nothing was written to any database.

---

## 1. Per persona: deltas

| Persona | n new / base | Session new vs base | Δ session (95% CI) | Turn mean new vs base | Δ turn (95% CI) | Turns 1–5 new vs base | Δ T1–5 (95% CI) | SD new |
|---|---|---|---|---|---|---|---|---|
| Paul (new rubric) | 5 / 13 | 4.77 vs 4.73 | +0.04 (−0.15…+0.31) | 4.24 vs 4.36 | **−0.12 (−0.21…−0.03)** | 4.17 vs 4.27 | **−0.10 (−0.17…−0.04)** | 0.11 |
| Lotta (new rubric) | 5 / 13 | 4.21 vs 4.31 | −0.10 (−0.50…+0.31) | 3.84 vs 3.91 | −0.07 (−0.28…+0.13) | 3.70 vs 3.74 | −0.04 (−0.12…+0.04) | 0.49 |
| Lars | 4 / 13 | 4.05 vs 4.04 | +0.01 (−0.27…+0.28) | 3.70 vs 3.66 | +0.04 (−0.22…+0.25) | 3.71 vs 3.60 | +0.11 (−0.23…+0.38) | 0.23 |
| Hawk | 5 / 13 | 3.34 vs 3.02 | +0.32 (−0.41…+1.03) | 2.10 vs 1.93 | +0.17 (−0.06…+0.38) | 1.63 vs 1.61 | +0.02 (−0.10…+0.13) | 0.45 |
| Ronny\* | 4 / 13 | 4.09 vs 4.37 | −0.28 (−0.77…+0.22) | 4.33 vs 4.44 | −0.11 (−0.55…+0.28) | 4.26 vs 4.40 | −0.14 (−0.82…+0.35) | 0.52 |
| Paul, Lotta, Lars, Hawk, persona-balanced | | | +0.07 (−0.16…+0.29) | | | | | |

\* Ronny is the anti-persona (high = the game resisted his exploits). He is kept out of every delight average.

- **Nothing moves clearly at the session level.** With n = 4–5, a CI is about ±0.3 to ±0.7, so only effects of half a level or more could show.
- **Paul is slightly lower turn by turn** (−0.12; T1–5 −0.10, CI clear of zero). His session score is unchanged. His argmax is 5 on 19 of 50 turns (38%), against 55/130 (42%) in the re-scored baseline. He stays at the inn in 5 of 5 runs and talks Rusk down instead of exploring. The cause isn't clear from 5 runs. One candidate is that Brenna now charges and gives less ("Generosity's earned around here, preacher"), and Paul's rubric rewards the world treating him warmly as a preacher.
- **Lotta spreads more:** SD 0.49 against 0.28. Her argmax is 3 on 18/50 turns (36%; baseline 18%) and 5 on 8/50 (16%; baseline 8%). Her best run (`d5955e53`, 4.85) jumps from about 3.8 to 4.8–4.9 at turns 7–9. Her worst (`67dc6268`, 3.63) sinks to about 3.3 in turns 7–10.
- **Hawk rises late, not early:** T1–5 is unchanged (+0.02). Turns 6–12 are up +0.28 (CI −0.11…+0.62). Turns 11–12 average 2.89 and 3.15, against 2.47 and 2.32. That matches the Tinjacks arriving at turn 6 (§4).
- **Ronny dips** in `50a3c41a` (3.44): he scores 2.5–2.9 at turns 3–6 before recovering to 4.6–4.8. This rests on 4 runs.

By turn (mean score; Paul and Lotta on the new rubric):

| Turn | Paul base | Paul new | Lotta base | Lotta new | Lars base | Lars new | Hawk base | Hawk new | Ronny\* base | Ronny\* new |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 4.11 | 4.02 | 3.47 | 3.46 | 3.36 | 3.68 | 1.55 | 1.49 | 4.35 | 4.48 |
| 2 | 4.20 | 4.02 | 3.61 | 3.68 | 3.50 | 3.87 | 1.64 | 1.61 | 4.26 | 4.47 |
| 3 | 4.30 | 4.17 | 3.73 | 3.78 | 3.64 | 3.33 | 1.61 | 1.71 | 4.37 | 4.17 |
| 4 | 4.32 | 4.41 | 3.92 | 3.79 | 3.67 | 3.98 | 1.54 | 1.74 | 4.49 | 4.06 |
| 5 | 4.42 | 4.21 | 3.96 | 3.77 | 3.84 | 3.69 | 1.72 | 1.61 | 4.54 | 4.11 |
| 6 | 4.44 | 4.38 | 4.00 | 3.91 | 3.69 | 3.54 | 1.79 | 1.90 | 4.46 | 3.97 |
| 7 | 4.29 | 4.17 | 4.15 | 3.94 | 3.60 | 3.44 | 1.82 | 1.97 | 4.43 | 4.42 |
| 8 | 4.41 | 4.17 | 4.10 | 3.95 | 3.67 | 3.72 | 2.02 | 2.18 | 4.44 | 4.52 |
| 9 | 4.57 | 4.32 | 4.08 | 4.13 | 3.98 | 3.96 | 2.25 | 2.37 | 4.50 | 4.52 |
| 10 | 4.55 | 4.53 | 4.09 | 3.96 | 3.67 | 3.82 | 2.41 | 2.60 | 4.51 | 4.53 |
| 11 | | | | | | | 2.47 | **2.89** | | |
| 12 | | | | | | | 2.32 | **3.15** | | |

- **Runs per arm for a future A/B** (80% power, from the new SDs): about Lars 4 per arm for Δ0.5 (10 for Δ0.3); Hawk 13 (36); Lotta 16 (43); Ronny 17 (48). Paul's session SD is 0.11, so use his turn means. Hawk's bimodality has softened (SD 0.45, against 1.20).

## 2. Leaving the inn

| | Leave attempts (runs with one) | Next GM turn still describes the inn or Brenna (regex) | Runs ending on an inn turn | Recorded scene changes | Runs that left the inn (recorded) |
|---|---|---|---|---|---|
| Baseline (65 runs) | 65 (40/65) | **38 of 59 (64%)** | 58% | 0 | 0 |
| New (23 runs) | 13 (8/23) | **3 of 13 (23%)** | 48% | 18 | **12 (52%)** |

- **The three remaining "inn" turns, read by hand:**
  - Paul `26d2424a` T4 ("…before I set out") is a plan, and #68 correctly keeps him there;
  - Lotta `d5955e53` T1 ("head for a stool") is not a leave at all;
  - Lotta `d5955e53` T5 ("head out the yard door toward the western slope") does move: the same reply opens the yard door onto Mags at the woodpile, after a line about Brenna. But no scene change was recorded (the run's only scene is the inn), and in T6 she walks back into the common room. **No run answered the player as Brenna after they had left.**
- **The leave regex misses many moves now.** Players go "into the yard", "up the cut" and "to Caldern's corner", which #68's movement verbs catch but the old regex doesn't. Recorded scenes are the better measure from now on.
- **Places reached** (runs with a recorded scene): Valley Inn 23, Market Square 7, the orc approach 4, the inn yard 2, the west road 2, the mine workings 2, the old adit 1. **Brask's forge and Maude's cottage: 0.**
- Per persona:
  - **Lars** leaves most (west road and old adit `ef7e5f27`, the orc approach twice);
  - **Paul never leaves** (0 of 5);
  - Hawk leaves in 3 of 5 runs, Lotta in 3 of 5 and Ronny in 2 of 4.

## 3. Echo and banned tics

| | Baseline (65 runs, 676 turns) | New (23 runs, 240 turns) |
|---|---|---|
| GM repeats an 8-word run of the player's line (turns) | 22.2% (Lotta 52.3%, Hawk 24.4%, Lars 16.9%, Ronny 13.8%, Paul 3.1%) | **5.0%** (Lotta 20.0%, Ronny 2.5%, Hawk 1.7%, Lars 0%, Paul 0%) |
| "on the house" (runs) | 49/65, 75% (the baseline doc counted 77%); 13.6% of turns | **5/23, 22%**; 2.9% of turns |
| "tilts her head toward" (runs) | 36/65 | **4/23** ("tilts her/his head" in any form: 44/65 → 6/23) |
| "wipes her hands" (runs) | 50/65 (77%) | **13/23 (57%)**, banned in #70 but still there |
| "hands on her apron" / "leans on the counter" / "a fresh mug" (runs) | 27 / 31 / 36 of 65 | 0 / 0 / 5 of 23 |
| "eyes narrow" (runs) | 11/65 (17%) | 5/23 (22%), mostly Brenna or Rusk "narrowing just a fraction" |

- **Lotta's echo is down but not gone.** 12 echo turns in all, 5 of them in one run (`ae982014`: "You step up to the bar, brushing snow from your cloak", word for word, T1–T3). Her first-person "I do X" lines still invite restating.
- **"On the house" now comes with a reason:** "stew's on the house tonight if you lend a hand", "the first round's on the house if you come back breathing", or "for the help with the keg earlier". That is what #70 asked for. All 5 runs with the phrase tie it to help, a job or a return.
- **New recurring gestures** (4-grams in the most runs, out of 23): "leans an elbow on" 11, "leans a hip against (the bar)" 10, and Cobb's "shifts his weight, knuckles whitening" 10–12. The banned list works phrase by phrase, and the model moves to the next phrase.

## 4. Hawk's conflict: the Tinjacks

- **On world time, in every run:** the Tinjacks' `trouble` clock fired the incident (the watchman clubbed) at turn 3 and the confrontation (the road toll at the inn) at turn 6 in **23 of 23 runs**. In 3 runs it also fired the escalation (the wagon burning), because the player was away from the inn at trouble 12: 2 Hawk runs (`434c1f95` and `7d3c831f`, at the orc approach and the mine) and 1 Lars run (`ef7e5f27`). In those two Hawk runs the toll fact was replaced by the burning one, and Hawk never met the gang.
- **Who meets them:** Rusk is named in 16 runs and Cobb in 14. A gang member is named in Paul 5/5, Lotta 5/5, Hawk 3/5, Lars 2/4 and Ronny 2/4, first at turn 4–6 on average. Pip is named in 6 runs. **No run broke the gang** (`beaten` stayed 0).
- **Fights and rolls:**
  - Hawk: **1 fight roll in 5 runs**. In `5fbba495` T12 he draws his knife on Cobb and rolls 18, a failure ("Cobb is already moving"). In `619d6e33` and `d244fd50` he stares Rusk and Cobb down from turn 6 to 12 without attacking.
  - Lars: **8 combat rolls in 2 runs, against orcs at the orc approach** (`4dcf1759`: 3 partial successes and 1 success; `772ed381`: 1 failed ranged roll, 2 partials and 1 failure).
  - No fight was narrated without a roll in the runs read (#71 works).

| Hawk | Runs | Session mean | Min–max |
|---|---|---|---|
| Baseline, no fight roll | 10 | 2.54 | 1.78–4.78 |
| Baseline, fight roll | 3 | 4.61 | 4.13–4.86 |
| **New, no fight roll** | 4 | **3.14** (+0.60, CI +0.01…+1.05 vs baseline) | **3.08–3.26** |
| **New, fight roll** | 1 | 4.14 | — |

- **Danger without a fight now scores about 3 ("closing in")**, where it used to score 2 ("foreshadowed"). The gang at the inn is a concrete threat, so Hawk no longer bottoms out. But **he still spends turns 1–5 on chores and talk** ("lend a hand clearing plates", chopping carrots): his chores rate is 3 of 5 runs, against 23% before, because Brenna's "lend a hand" hook is unchanged. His T1–5 is still 1.63. The gang arrives at turn 6 at the earliest, which leaves 6 turns for a fight he rarely starts.

## 5. New places and people; activity types

Runs in which the GM names each person (new series; none of the new people exist in the baseline):

| Person | Paul (5) | Lotta (5) | Lars (4) | Hawk (5) | Ronny (4) | All (23) |
|---|---|---|---|---|---|---|
| Tam (stable lad) | 0 | 2 | 0 | 1 | 0 | 3 |
| Mags (drover) | 1 | 3 | 0 | 1 | 0 | 5 |
| Hilde Brask (smith) | 0 | 0 | 0 | 0 | 0 | **0** |
| Maude (herb-wife) | 0 | 2 | 0 | 1 | 1 | 4 |
| Rusk / Cobb | 5 / 5 | 5 / 4 | 2 / 1 | 2 / 2 | 2 / 2 | 16 / 14 |
| Pip | 1 | 1 | 2 | 1 | 1 | 6 |

Activity types reached (share of runs; places from recorded scenes, otherwise a regex on the player's lines, so approximate):

| Activity | Baseline (65) | New (23) | Where the change is |
|---|---|---|---|
| Talk | 94% | 100% | — |
| Trade | 25% | 22% | Ronny 3/4 haggles |
| **Explore** | 14% | **43%** | Lars 4/4, Hawk 3/5, Lotta 2/5, Ronny 1/4 (the yard, the market, the west road, the mine, the adit) |
| Sneak | 12% | 26% | Lars 2/4 (Pip, the adit) |
| Fight | 28% | 13% | Lars 2/4 (orcs), Hawk 1/5 |
| Lore | 0% | 0% | — |
| Crafts and chores | 18% | 17% | Hawk 3/5 (still chores), Lotta 1/5 (kegs for Brenna, then Mags's job) |
| Heal and rest | 11% | 0% | — |
| Distinct types per run | 2.0 | 2.2 | |

- **Exploring is the clear gain:** the west road, the old adit (Lars) and the yard and goat track with Tam and Mags (Hawk, Lotta). Lotta's best runs are with Mags and Tam.
- **The forge and the cottage are unused:** nobody went to Hilde Brask or Maude's cottage, and lore stays at 0. 10–12 turns may be too short for places that are two exits away when Rusk takes over the inn at turn 6.

## 6. Rolls and outcomes

| | Baseline | New |
|---|---|---|
| Roll rate (turns) | 6.2% (42/676) | 6.7% (16/240) |
| Runs with at least one roll | 34% | 35% |
| Failure / partial / success | 23 / 5 / 14 | 5 / 7 / 4 |
| Per persona (roll rate) | Lars 16.9%, Hawk 5.8%, Ronny 4.6%, Lotta 2.3%, Paul 1.5% | Lars 20%, Lotta 6%, Paul 6%, Hawk 3.3%, Ronny 0% |
| Skills rolled (new) | | melee combat 8, tracking 4, deception 2, climbing 1, ranged combat 1 |

- **Rolling is about as rare as before.** Fights with the Tinjacks rarely start, so #71 has little to act on.
- **One roll looks misclassified:** Paul `3f7777a6` T7 rolls **climbing** (failure) for a speech to Rusk ("Rusk, my good fellow, a toll upon a wandering preacher…").

## 7. Skill growth under the new rule (#67)

| | LP per run | Attempts | Levels gained | Levels per run | Max levels in one run |
|---|---|---|---|---|---|
| Baseline (#64 rule), 65 runs | 1.00 (CI 0.53…1.58) | 0 | 0 | 0.00 | 0 |
| **New (1 LP = 1 attempt), 23 runs** | 0.91 (CI 0.35…1.61) | **20** | **13** | **0.57** | **4** |

Per persona (new): Lars 2.1 LP, 2.0 attempts, 1.5 levels per run; Paul 1.0 / 1.0 / 0.8; Lotta 1.0 / 1.0 / 0.4; Hawk 0.5 / 0.4 / 0.2; **Ronny 0 / 0 / 0**.

- **65% of attempts succeed**, as expected at low skill levels (d20 ≥ level).
- **No runaway growth:**
  - The largest run is Lars `772ed381`: 4 combat rolls → 5 attempts → melee +3 and ranged +1. That is about what a real fight should give.
  - Ronny, whose baseline LP peaked at 13.5 in one run, rolled nothing in 4 runs.
  - Watch a long or grindy fight: every roll now pays out at once.
- By skill (LP / levels): melee 8.5 / 6, tracking 5.5 / 2, deception 4 / 3, ranged 2 / 1, climbing 1 / 1.
- A social persona now sees a level now and then: Paul gained 4 levels in 5 runs, all from rolls on deception (2) and the misread climbing roll (1).

## 8. Cost

| Series | Runs | Game | Persona bot | Jev (scorer) | Total | Per run |
|---|---|---|---|---|---|---|
| **New, all runs** | 26 | **$2.10** (incl. `npc_reaction` $0.016) | **$0.64** | **$0.006** | **$2.74** | $0.105 |
| New, completed runs only | 23 | $2.01 (incl. `npc_reaction` $0.015) | $0.61 | $0.005 | $2.62 | **$0.114** (game 0.087, persona 0.027, Jev 0.0002) |
| The 3 timed-out runs | 3 | $0.09 | $0.03 | $0.0003 | $0.12 | |
| Baseline | 65 | $4.38 | $1.64 | $0.014 | $6.03 | $0.093 (game 0.067, persona 0.025) |

- Per completed run (game / persona): Hawk $0.095 / 0.031; Lotta 0.087 / 0.027; Paul 0.086 / 0.027; Ronny 0.084 / 0.023; Lars 0.082 / 0.025. Jev is 0.0002–0.0003 for everyone.
- **Game cost per run is up 29%** ($0.087 against $0.067), within the estimate (about $2.5 for 25 runs). The likely cause is bigger prompts (new people, perceived facts, the scene block) and up to three NPC reactions when Rusk and Cobb are present.
- **The database matches:** the playtest day's spend (`ai_calls`, Stockholm day, at 07:30 CEST) was game $2.0991, persona $0.6378 and scorer $0.0057. That is exactly the series. $2.74 of the $25 cap; the cap was left unchanged.
- **The baseline re-score** (52 Jev calls) ran from the box with the TypeSafe key, so it is not in `ai_calls`. At the baseline's $0.0002 per scorer call it is about $0.01.

## 9. Limitations

- **5 runs per persona is small** (Lars and Ronny 4). Only effects of about half a level show. The Hawk no-fight gain (+0.60) is the only score delta with a CI clear of zero apart from Paul's small turn dip. Both need confirmation.
- **Three runs hung and were dropped** (`a76294d9` and `1a995c9f` Lars T3, `0d1b8222` Paul T7). Each time the Tier 1 intent call (`purpose=intent`, `source=llm`) returned in 1.4–2.0 s, and then the turn logged nothing more until the run's turn timeout: no GM call, no NPC reaction, no error. 14 turns used the LLM intent path in the series (the baseline had 0), and 3 of them hung. **That points at the new move/intent path after Tier 1** (#68 `normalize_move`, the movement resolution, or what follows it), but it was not reproduced. Dropping them may bias Lars, since both of his hangs came at turn 3, while he was still in the inn. *Update 2026-10-08:* the cause has been found and fixed. The intent call answered `"parameters": null`, and the rules step crashed on it (`BadMapError`) inside the turn job. The job was retried and dropped without a log line, so the turns looked hung. The fix is [ex-tales-forge #79](https://github.com/whyse-ab/ex-tales-forge/pull/79) (merge `ccd5379`, prod v75, playtest v63). Crashed turns now show as failed turns and failed runs. The numbers in this analysis are unchanged.
- **Not an A/B on one deploy:** this compares a new day and deploy with yesterday's. Everything from #67–#73 changed at once: scene changes, inn world, antagonist, Brenna, rolls and growth. No single effect can be attributed.
- **Hindsight in turn scores:** as before. Hawk's late fight lifts his earlier turns.
- **Re-scored baseline:** Paul and Lotta's baseline scores come from a second Jev pass (±0.11 per session against the pilot). Their turn confidences are unknown.
- **Regex features:** the leave, inn, echo, tic, people and activity measures are heuristics. The leave regex misses many of the new move phrasings (§2). Activity types from player text are approximate.
- **The rubrics are the yardstick:** Hawk's danger scale rewards the gang's presence even without a fight. Paul's scale may penalise a less generous Brenna.

## 10. Recommendations

1. **Fix the hang first** (done 2026-10-08 in [#79](https://github.com/whyse-ab/ex-tales-forge/pull/79): a `parameters: null` crash, see §9). Add a timeout and logging around the step after a Tier 1 intent (movement resolution, triggers and the world tick). Replay the three runs (`a76294d9`, `0d1b8222` and `1a995c9f`). The hung turn's player text is not stored, so log the raw action on a timeout.
2. **Bring the fight to Hawk earlier, or let him start it:**
   - drop Brenna's "lend a hand" chore hook for action personas (still 3/5 of Hawk's runs);
   - and/or let the confrontation come at trouble 3–4.

   His no-fight floor rose to about 3.1. A fight still lifts him to about 4.1.
3. **Rotate the tics again, or ban gestures by pattern rather than by phrase:** "wipes her hands" (57% of runs, despite the ban), "leans a hip / an elbow" and Cobb's "knuckles whitening". Lotta's opening echo is the last echo hotspot.
4. **Make the forge and the cottage reachable within a session:** Hilde, Maude and lore were reached 0 times. Give Brenna or Tam a concrete reason to send the player there before turn 6.
5. **Check the misread roll** (climbing on a speech to Rusk) and why Ronny rolled nothing in 4 runs.
6. **Record `INN_WORLD` and `WORLD_ANTAGONIST` in `playtest_runs.flags`** next to `npc_reactions` and `world_agents`.
7. **Measurement:**
   - use recorded scenes, not the leave regex, from now on;
   - for the next A/B, run both arms on one deploy (`variant: "baseline"`), with at least 10 runs per arm for Lars and 15–20 for Hawk, Lotta and Ronny;
   - use Paul's turn means.

## Update 2026-10-08: confidence-aware reading

**Summary.** From today we count only the scores Jev is sure about (confidence ≥ 0.7) in the headline, and report the share it is unsure about separately ([decision](decisions.md#2026-10-08-jev-scores-are-read-as-a-score-by-confidence-matrix-not-a-plain-average)). Read that way, the main conclusion stands: **no persona's session score moved by an amount we can tell from zero.** Two things change. **Hawk's gain gets clearer:** on the turns Jev is sure about he is up +0.32 (95% CI +0.15…+0.47; the plain average said +0.17, CI −0.06…+0.38), at every cutoff. Jev is also unsure far less often about him (27% of turns against 50%). He moved from "confidently no danger" towards "closing in" (level 3), but he still almost never gets a confidently high turn (1 of 60). **Ronny's dip disappears** (session −0.28 becomes +0.01), because it came from sessions Jev wasn't sure about. With only 1 sure session in the new series, that is not a finding either way. Paul's turn dip (−0.12) can't be re-checked like for like: the stricter re-score of the baseline kept no turn confidences. Lotta has too few sure turns on the stricter rubric to read at 0.7.

*Added 2026-10-08:* Paul's and Lotta's baseline has since been re-scored with turn confidences kept, so their turn deltas can now be read this way ([below](#added-2026-10-08-paul-and-lotta-at-turn-level-like-for-like)). Paul's dip is about the same size (−0.08 to −0.11) and borderline at 0.7. Lotta still has too few sure turns at 0.7 and is flat at 0.6. The conclusion above stands.

**Method.** Existing scores only: no new runs and no Jev calls. The score set is the one this analysis used: Paul and Lotta on the stricter #69 rubric on both sides (the baseline re-scored, §Data and method), the others on their unchanged rubrics.

- **High** = score ≥ 3.5 (nearest level 4–5, "works"), **low** = score ≤ 2.5 (nearest level 1–2, "broken"), in between = level 3, reported as confident-middle. **Confident** = confidence ≥ 0.7 (sensitivity: 0.6 and 0.8). **Unsure** = below it: the low-confidence share. Same definitions as the [baseline update](analysis-jev-baseline-2026-10-07.md#update-2026-10-08-confidence-aware-reading).
- **Headline** = mean of the confident turns (or sessions). **Deltas** are new minus baseline, with bootstrap 95% CIs over runs (5000 resamples; whole runs are resampled and the statistic recomputed). The "old" columns are the plain-average deltas of §1, recomputed by the same script. Their CIs differ from §1 by at most 0.03, which is bootstrap noise.
- ⚠ = too few to say anything: fewer than 20 confident turns or 3 runs with one on a side (turns), or fewer than 3 confident sessions on a side.
- **Gap:** the re-score of the baseline's Paul and Lotta runs (`rescore.exs`) stored their session confidence but not their turn confidences. They are not in the playtest database either (the re-score ran from the box, and the database holds only the stored rubric's rows for those runs; checked read-only today). So for Paul and Lotta the turn-level deltas under the new reading are n/a. Their session deltas and the score bands without confidence (below) are like for like. *Added 2026-10-08: filled by a second re-score that keeps turn confidences, [below](#added-2026-10-08-paul-and-lotta-at-turn-level-like-for-like).*
- Script: [`scripts/jev-confidence/`](scripts/jev-confidence/) (`confidence_matrix.py`; full output in `results-2026-10-08.md`).

**Persona deltas, old vs new reading** (cutoff 0.7; n = confident sessions or turns, new/base):

| Persona | Session Δ, plain (old) | **Session Δ, confident only** | Turn Δ, plain (old) | **Turn Δ, confident only** | Unsure turns, new vs base |
|---|---|---|---|---|---|
| Paul | +0.04 (−0.15…+0.31) | −0.07 (−0.17…+0.03), n=5/12 | **−0.12 (−0.21…−0.03)** | n/a: no baseline turn confidences | 46% vs unknown |
| Lotta | −0.10 (−0.50…+0.34) | +0.07, n=1/2 ⚠ | −0.07 (−0.28…+0.14) | n/a: no baseline turn confidences | 86% vs unknown |
| Lars | +0.01 (−0.27…+0.28) | +0.08 (−0.30…+0.48), n=3/7 | +0.04 (−0.22…+0.25) | −0.03 (−0.27…+0.16), n=24/59 | 40% vs 55%: **−15 pp (−27…−2)** |
| Ronny\* | −0.28 (−0.77…+0.20) | +0.01, n=1/4 ⚠ | −0.11 (−0.55…+0.28) | −0.02 (−0.14…+0.03), n=12/54 ⚠ | 70% vs 58%: +12 pp (−24…+42) |
| Hawk | +0.32 (−0.38…+1.04) | +0.29 (−0.49…+1.06), n=5/12 | +0.17 (−0.06…+0.38) | **+0.32 (+0.15…+0.47)**, n=44/78 | 27% vs 50%: **−23 pp (−36…−12)** |

\* Ronny is the anti-persona: high = the game resisted his exploits.

**Sensitivity** (the same deltas at 0.6 and 0.8):

| Persona | Session ≥ 0.6 | Session ≥ 0.8 | Turn ≥ 0.6 | Turn ≥ 0.8 |
|---|---|---|---|---|
| Paul | −0.07 (−0.17…+0.03), n=5/12 | −0.02 (−0.11…+0.09), n=3/11 | n/a | n/a |
| Lotta | +0.15 (−0.31…+0.58), n=3/7 | n=1/1 ⚠ | n/a | n/a |
| Lars | +0.05 (−0.25…+0.32), n=4/12 | n=1/3 ⚠ | +0.06 (−0.22…+0.26), n=28/85 | −0.07 (−0.36…+0.13), n=17/33 ⚠ |
| Ronny\* | n=1/5 ⚠ | n=0/0 ⚠ | −0.04 (−0.16…+0.02), n=19/72 ⚠ | n=7/35 ⚠ |
| Hawk | +0.32 (−0.39…+1.03), n=5/13 | n=2/9 ⚠ | **+0.28 (+0.10…+0.45)**, n=57/136 | **+0.32 (+0.07…+0.51)**, n=29/37 |

Low-confidence share of turns (unsure), per dataset:

| Persona | Baseline < 0.6 / **< 0.7** / < 0.8 | New < 0.6 / **< 0.7** / < 0.8 | Turns at confidence 0 (base / new) |
|---|---|---|---|
| Paul | unknown on the stricter rubric (old rubric: 9% / 17% / 34%) | 30% / **46%** / 64% | — / 1 |
| Lotta | unknown on the stricter rubric (old rubric: 1% / 8% / 46%) | 40% / **86%** / 90% | — / 0 |
| Lars | 35% / **55%** / 75% | 30% / **40%** / 57% | 0 / 0 |
| Ronny\* | 45% / **58%** / 73% | 52% / **70%** / 82% | 6 / 4 |
| Hawk | 13% / **50%** / 76% | 5% / **27%** / 52% | 0 / 0 |

*Added 2026-10-08:* on the stricter rubric (second re-score) the baseline shares are Paul 22% / **51%** / 70% and Lotta 34% / **75%** / 95%, with 1 and 0 turns at confidence 0.

The new series as a matrix (turns, cutoff 0.7; sessions in brackets):

| Persona | Turns (sessions) | Plain mean | Headline ≥ 0.6 / **≥ 0.7** / ≥ 0.8 | Confident-high | Confident-low | Confident-middle | Unsure | Session headline ≥ 0.7 |
|---|---|---|---|---|---|---|---|---|
| Paul | 50 (5) | 4.24 | 4.29 / **4.29** / 4.23 ⚠ | 27 (54%) | 0 | 0 | 23 (46%) | 4.77 (n=5) |
| Lotta | 50 (5) | 3.84 | 3.86 / **4.23** ⚠ / 4.52 ⚠ | 6 (12%) | 0 | 1 (2%) | 43 (86%) | 4.85 (n=1) ⚠ |
| Lars | 40 (4) | 3.70 | 3.85 / **3.89** / 3.90 ⚠ | 23 (57%) | 1 (2%) | 0 | 16 (40%) | 4.03 (n=3) |
| Ronny\* | 40 (4) | 4.33 | 4.71 ⚠ / **4.78** ⚠ / 4.86 ⚠ | 12 (30%) | 0 | 0 | 28 (70%) | 4.72 (n=1) ⚠ |
| Hawk | 60 (5) | 2.10 | 2.13 / **2.17** / 2.22 | 1 (2%) | 34 (57%) | 9 (15%) | 16 (27%) | 3.34 (n=5) |

Score bands without confidence (like for like for every persona, including Paul and Lotta): share of turns ≥ 3.5 is Paul 100% vs 99%, Lotta 78% vs 89% (−11 pp, CI −24…+2), Lars 80% vs 72%, Ronny 90% vs 95% and Hawk 2% vs 6%. No persona has a turn share ≤ 2.5 that changed by more than the noise (Hawk 78% vs 87%, −8 pp, CI −18…+3).

What changes and what doesn't:

- **Sessions: no change in the conclusion.** Under either reading no session delta is distinguishable from zero. Paul goes from +0.04 to −0.07 (CI −0.17…+0.03), Lars stays flat, Hawk stays about +0.3 with a wide CI. Lotta (1 vs 2 sure sessions) and Ronny (1 vs 4) have too few sure sessions at 0.7 to say anything. At 0.6, Lotta has 3 vs 7: +0.15 (−0.31…+0.58).
- **Hawk: the turn-level gain is now clear,** +0.32 (+0.15…+0.47) at 0.7, +0.28 at 0.6, +0.32 at 0.8. In the baseline, his unsure turns sat a little above his sure ones (2.00 vs 1.85), so the plain average hid part of the change. In the new series, Jev is sure "closing in" (level 3) on 9 turns (15%), against 3 of 156 (2%) before. The gain is "less nothing", not "it works": confident-high is still 1 turn in 60.
- **Ronny: the −0.28 session dip was an unsure dip.** 3 of his 4 new sessions are below 0.7. The turns behind `50a3c41a`'s dip (T3–T6 at 2.54–2.91, §1) all have confidence 0: Jev leaned to "Unlocked" (0.38–0.47) but put most of the rest on levels 4–5. On sure turns he is flat (−0.02), but on 12 sure turns in 4 runs. His unsure share went up (58% → 70%), with a CI from −24 to +42 pp.
- **Paul: the turn dip can't be confirmed or ruled out this way.** His stricter-rubric baseline has no turn confidences. In the new series 46% of his turns are unsure, mostly a split between level 4 (0.45) and 5 (0.40), the border the stricter rubric added. His sure turns average 4.29 against 4.24 for all turns. *Added 2026-10-08: now checked like for like: about the same size, borderline at 0.7 ([below](#added-2026-10-08-paul-and-lotta-at-turn-level-like-for-like)).*
- **Lotta: the stricter rubric made Jev unsure about her.** 86% of her new turns are below 0.7, mostly a split between level 3 ("pleasant but interchangeable", 0.35) and 4 ("about her", 0.48), the border #69 added. 30 of 50 turns still pass 0.6. So for Lotta on this rubric a 0.7 cutoff leaves too little to read. Her low-confidence share can only be compared with other stricter-rubric runs, not with the old 8%.
- **Lars: Jev is surer about him** (unsure 55% → 40%, −15 pp, CI −27…−2). He also explored more in the new series (§5); whether that is the reason isn't shown. His sure-turn score is flat.

### Added 2026-10-08: Paul and Lotta at turn level, like for like

Fredrik approved a second re-score of the baseline's Paul and Lotta runs with the stricter rubric, this time keeping the turn confidences. It counts as re-scoring existing data, which the decision covers.

- **How it ran:** [`rescore.exs`](scripts/jev-rescore/rescore.exs) ran from the box against the stored baseline transcripts, from an ex-tales-forge checkout of `main` (`ccd5379`), with `mix run --no-start`. That means the app, its database connection and its jobs never started, and nothing was written to the playtest database or any other. The script now takes `RUBRICS=new` and also stores the turn confidences, the probabilities, the rubric hash and Jev's usage.
- **Cost:** 26 Jev calls for **$0.0067**, Jev's own usage figure (159,693 input tokens). No game or persona-bot calls.
- **Rubric:** the hashes `fd84ebb` (Paul) and `ce84a1a` (Lotta) match the new series.
- **Raw rows:** [`scripts/jev-rescore/rescore-baseline-2026-10-08-conf.json`](scripts/jev-rescore/rescore-baseline-2026-10-08-conf.json). Full output: `scripts/jev-confidence/results-2026-10-08-conf.md`.

**Second pass vs first pass** (same transcripts, same rubric, so the gap is Jev's own noise):

- Turn means are 4.37 vs 4.36 (Paul) and 3.91 vs 3.91 (Lotta). Single turns differ by 0.03 on average and by at most 0.14. Sessions are 4.74 vs 4.73 and 4.30 vs 4.31.
- In the tables below, both sides of the Paul and Lotta reading come from the same pass: scores and confidences. The "old" column stays on the first pass, as in §1, and the plain delta on the second pass is shown next to it.

| Persona | Turn Δ, plain (old, 1st pass) | Plain, 2nd pass | Confident only ≥ 0.6 | **Confident only ≥ 0.7** | Confident only ≥ 0.8 |
|---|---|---|---|---|---|
| Paul | −0.12 (−0.21…−0.03) | −0.13 (−0.21…−0.03) | −0.11 (−0.19…−0.03), n=35/101 | **−0.08 (−0.17…+0.01)**, n=27/64 | −0.11 (−0.27…+0.07), n=18/39 ⚠ |
| Lotta | −0.07 (−0.28…+0.14) | −0.07 (−0.28…+0.13) | −0.05 (−0.27…+0.14), n=30/86 | +0.31 (−0.51…+0.69), n=7/33 ⚠ | +0.32 (−0.27…+0.58), n=5/7 ⚠ |

The stricter-rubric baseline as a matrix (turns, cutoff 0.7):

| Persona | Turns | Plain mean | Headline ≥ 0.6 / **≥ 0.7** / ≥ 0.8 | Confident-high | Confident-low | Confident-middle | Unsure |
|---|---|---|---|---|---|---|---|
| Paul | 130 | 4.37 | 4.40 / **4.37** / 4.34 | 64 (49%) | 0 | 0 | 66 (51%) |
| Lotta | 130 | 3.91 | 3.91 / **3.92** / 4.21 ⚠ | 28 (22%) | 0 | 5 (4%) | 97 (75%) |

Low-confidence share of turns, new vs baseline, stricter rubric on both sides:

| Persona | < 0.6 | **< 0.7** | < 0.8 |
|---|---|---|---|
| Paul | 30% vs 22%: +8 pp (−5…+19) | 46% vs 51%: −5 pp (−13…+4) | 64% vs 70%: −6 pp (−17…+6) |
| Lotta | 40% vs 34%: +6 pp (−13…+24) | 86% vs 75%: +11 pp (−10…+31) | 90% vs 95%: −5 pp (−25…+9) |

Sessions on the second pass, confident only:

- **Paul:** −0.07 (−0.16…+0.03) at 0.6 and at 0.7 (n=5/12), and −0.02 (−0.11…+0.09) at 0.8.
- **Lotta:** +0.19 (−0.30…+0.64) at 0.6 (n=3/6). Too few at 0.7 and 0.8.

What it shows:

- **Paul's turn dip is about the same size under the new reading, and no clearer:** −0.11 at 0.6 (CI clear of zero), −0.08 at 0.7 (CI just reaches zero), and −0.11 at 0.8 (too few new turns). Read it as "maybe a tenth of a level lower turn by turn", not as a confident change. His session is flat.
- **Lotta is still unreadable at 0.7:** only 7 sure turns in the new series. At 0.6 (30 vs 86 turns) she is flat (−0.05).
- **Paul's and Lotta's high unsure shares come from the rubric, not the rework.** On the stricter rubric Jev was already unsure on 51% of Paul's and 75% of Lotta's baseline turns (old rubric: 17% and 8%). The splits sit on the borders #69 added: Paul's unsure turns split between level 4 (0.46) and 5 (0.47), Lotta's mostly between 3 (0.28) and 4 (0.51). The new series is about the same (46% and 86%), and neither change can be told from zero.
- **The verdict doesn't change.** Sessions show no change, Hawk's turn gain is clear, Ronny's dip came from unsure scores, Paul is perhaps 0.1 lower turn by turn, and Lotta can't be read at 0.7.

### Added 2026-10-08: confidence-weighted headline and sharper Paul/Lotta borders

**Summary.** Fredrik approved two follow-ups.

1. **New headline.** The headline Jev score is now the confidence-weighted average: every turn counts, and unsure turns count less. The share of unsure turns (confidence < 0.7) is shown next to it.
2. **Sharper borders.** Paul's border between level 4 and 5 and Lotta's between 3 and 4 were sharpened so Jev would stop wavering there.

What the re-score shows:

- **Lotta: it worked.** Jev is unsure on 39% of her baseline turns and 30% of her post-rework turns, against 75% and 86% before. It is now mostly sure she is at level 3, "pleasant but interchangeable", so her scores drop by about 0.6.
- **Paul: it didn't work.** Jev is now unsure on about 73% of his turns, against about 50%. In his typical turn the NPC answers an open question with vivid new detail, and Jev still can't decide whether that is "an answer" (level 4) or "a surprise" (level 5).
- **The persona deltas tell the same story under either rubric and either headline.** Paul is about 0.1 lower turn by turn (weighted −0.10, CI −0.22…−0.01). Lotta is flat. No session moved.

**What changed** (ex-tales-forge [PR #80](https://github.com/whyse-ab/ex-tales-forge/pull/80), not merged; [decisions](decisions.md#2026-10-08-the-headline-jev-score-is-a-confidence-weighted-average)):

- **Headline** = `sum(score × confidence) / sum(confidence)` over a persona's (or a run's) turns, on the 1–5 scale. The unsure share (confidence < 0.7) sits next to it, and the high / low / unsure breakdown at 0.7 underneath. This refines the cutoff headline above: the 0.7 cutoff now only marks a score as unsure.
- **Paul 4 vs 5:** 4 = the reply *only answers him* (information he asked for, a price, a room, a welcome, a gift). 5 = at least two kinds of evidence, *each visible in this turn's narration*. A surprise is "a new fact, event or arrival he did not ask about"; a consequence is "something changes because of a choice of his; an answer alone is not a consequence". Asked-for information, warmth, gifts and prices never count. Examples:
  - level 4: he asks what proof Osric wants and Brenna tells him (`9e1c1d34` T4);
  - level 5: he offers to help and Brenna puts him to stir the stewpot, then volunteers a black iron door seen in the cut (`93213b5e` T4).
- **Lotta 3 vs 4:** 3 = the reply *would read the same for any traveller who said her line*: her name used, her order served, her question answered, a job offered to anyone. 4 = it picks up something particular to her character that another traveller would not get. Examples:
  - level 3: Brenna welcomes "Hilde", names the price and mentions the bounty (`a9585b54` T1);
  - level 4: she says she is more at home in the wilds, and Brenna says the job in the wilds might suit her better than swinging a pick (`f33a16a8` T2).
- **Rubric versions:** paul `jev-affect-v1-7862783` (was `fd84ebb`), lotta `jev-affect-v1-989546a` (was `ce84a1a`).
- **Re-score:** the baseline's 26 Paul and Lotta runs and the 10 post-rework ones, from the stored transcripts. It ran on the box from the PR branch with `mix run --no-start`, so nothing was written to any database. That was 36 Jev calls for **$0.0120** (Jev's own usage figure; 285,629 input tokens), with no game or persona-bot calls. Raw rows: [`rescore-baseline-2026-10-08-sharp.json`](scripts/jev-rescore/rescore-baseline-2026-10-08-sharp.json) and [`rescore-post-rework-2026-10-08-sharp.json`](scripts/jev-rescore/rescore-post-rework-2026-10-08-sharp.json). Full output: [`results-2026-10-08-sharp.md`](scripts/jev-confidence/results-2026-10-08-sharp.md).

"#69" below is the rubric this analysis used: for the baseline, the second re-score with turn confidences; for post-rework, the stored scores. "Sharp" is the new rubric, re-scored on both sides.

**Unsure share (confidence < 0.7) and weighted headline, per dataset:**

| Persona | Rubric | Unsure, baseline | Unsure, post-rework | **Weighted, baseline** | **Weighted, post-rework** | Plain mean, base / post |
|---|---|---|---|---|---|---|
| Paul | #69 | 51% | 46% | 4.39 | 4.26 | 4.37 / 4.24 |
| Paul | sharp | **72%** | **74%** | 4.44 | 4.34 | 4.37 / 4.21 |
| Lotta | #69 | 75% | 86% | 3.92 | 3.86 | 3.91 / 3.84 |
| Lotta | sharp | **39%** | **30%** | 3.28 | 3.28 | 3.33 / 3.34 |
| Lars | unchanged | 55% | 40% | 3.73 | 3.76 | 3.66 / 3.70 |
| Ronny\* | unchanged | 58% | 70% | 4.62 | 4.58 | 4.44 / 4.33 |
| Hawk | unchanged | 50% | 27% | 1.90 | 2.12 | 1.93 / 2.10 |

**Deltas, post-rework minus baseline** (95% CI, bootstrap over runs):

| Persona | Rubric | Turn plain mean Δ | **Turn weighted Δ** | Unsure share Δ | Session weighted Δ |
|---|---|---|---|---|---|
| Paul | #69 | −0.13 (−0.21…−0.04) | **−0.12 (−0.20…−0.05)** | −5 pp (−14…+4) | −0.04 (−0.15…+0.08) |
| Paul | sharp | −0.16 (−0.30…−0.01) | **−0.10 (−0.22…−0.01)** | +2 pp (−12…+13) | −0.03 (−0.13…+0.09) |
| Lotta | #69 | −0.07 (−0.28…+0.13) | **−0.06 (−0.29…+0.18)** | +11 pp (−11…+31) | −0.05 (−0.52…+0.38) |
| Lotta | sharp | +0.01 (−0.25…+0.30) | **0.00 (−0.22…+0.30)** | −9 pp (−36…+19) | −0.08 (−0.74…+0.77) |
| Lars | unchanged | +0.04 (−0.22…+0.25) | +0.03 (−0.22…+0.23) | −15 pp (−26…−2) | +0.02 (−0.26…+0.28) |
| Ronny\* | unchanged | −0.11 (−0.54…+0.28) | −0.04 (−0.22…+0.14) | +12 pp (−23…+42) | −0.17 (−0.68…+0.19) |
| Hawk | unchanged | +0.17 (−0.06…+0.39) | **+0.22 (+0.01…+0.41)** | −23 pp (−35…−12) | +0.34 (−0.42…+1.05) |

**Breakdown at 0.7, Paul and Lotta (turns):**

| Persona | Rubric | Dataset | Confident-high | Confident-middle | Confident-low | Unsure |
|---|---|---|---|---|---|---|
| Paul | #69 | baseline / post | 64 (49%) / 27 (54%) | 0 / 0 | 0 / 0 | 66 (51%) / 23 (46%) |
| Paul | sharp | baseline / post | 36 (28%) / 13 (26%) | 0 / 0 | 0 / 0 | 94 (72%) / 37 (74%) |
| Lotta | #69 | baseline / post | 28 (22%) / 6 (12%) | 5 (4%) / 1 (2%) | 0 / 0 | 97 (75%) / 43 (86%) |
| Lotta | sharp | baseline / post | 5 (4%) / 3 (6%) | 74 (57%) / 32 (64%) | 0 / 0 | 51 (39%) / 15 (30%) |

What it shows:

- **Lotta: the border works, and it moves her down a level.** On the sharpened rubric her most likely level is 3 on 115 of 130 baseline turns and 43 of 50 post-rework turns. Her sure turns sit firmly at 3 (mean probabilities .01 / .81 / .14 for levels 2 / 3 / 4). In plain words, Jev now says the GM rarely answers *Hilde* in particular: replies use her name, serve her order and answer her question, but seldom pick up her dwarf or druid side or her earlier deeds. Her weighted headline drops from 3.92 to 3.28. That is a change of yardstick, not of the game, and both sides moved alike (delta 0.00).
- **Paul: the border still doesn't separate his turns.** His unsure turns are an even split between level 4 (0.42) and 5 (0.45), and his most likely level moved towards 5 (71 of 130 baseline turns, against 56 on the #69 rubric).
  - **Why.** Jev returns no rationales (the API gives only scores, confidences and probabilities), so this comes from the vectors and from reading the turns. Paul asks broad questions ("have any of your patrons lost kin?"), and the NPCs answer with vivid facts he could not have known: Old Jarek's boy, eyes like hot coals, a miner joining in unasked (`f756f876` T3, T5 and T6, confidence 0.49–0.57). Whether that is "information he asked for" (4) or "a surprise" and "an NPC acting on their own goals" (5) is a judgment the wording can't settle. Most of his turns are both.
  - **Hindsight adds to it.** Jev sees the whole transcript when it scores a turn, so evidence from nearby turns can leak in.
  - **Options for Fredrik, not done here:**
    - make level 5 require one particular kind of evidence (for example a consequence of his choice);
    - score turns without hindsight;
    - or leave Paul's border as it is and rely on the weighted headline.
- **The deltas don't change:**
  - **Paul:** about −0.1 turn by turn under every rubric and headline (weighted −0.10, CI −0.22…−0.01 sharpened; −0.12, CI −0.20…−0.05 on #69).
  - **Lotta:** flat.
  - **Hawk:** the weighted headline keeps his turn gain clear of zero (+0.22, CI +0.01…+0.41), smaller than the cutoff reading's +0.32.
  - **Sessions:** none moved.
- **Weighted vs cutoff headline:** the weighted headline stays close to the plain mean, because unsure turns still count: within about 0.1 for most personas, and up to 0.25 higher for Ronny, whose unsure turns are his low ones. It never runs out of turns, unlike Lotta's 7 at the cutoff.

\* Ronny is the anti-persona: high = the game resisted his exploits.

### Added 2026-10-08: Paul's level 5 needs a consequence of his own choice or discovery

**Summary.** Fredrik decided Paul's 4-vs-5 border ([decision](decisions.md#2026-10-08-pauls-level-5-needs-a-consequence-of-his-own-choice-or-discovery), [PR #80](https://github.com/whyse-ab/ex-tales-forge/pull/80), not merged): a vivid answer or a new fact is a 4. A 5 needs a consequence of his own choice or discovery, where the world reacts: an NPC acts on what he learned, or a door opens because he asked.

What the re-score shows:

- **The baseline is settled.** Jev is unsure on 33% of his baseline turns, against 51% on #69 and 72% on the first sharp version.
- **Post-rework, much less so** (48% unsure).
- **The weighted headline and the deltas don't change:** Paul is about 0.1 lower turn by turn and no different per session.

**Rubric:** paul `jev-affect-v1-df3c861`, replacing the first sharp version `7862783`. Lotta, Lars, Hawk and Ronny are unchanged. Examples from real turns:

- **Level 4:** he asks whether patrons lost kin, and Brenna tells him of Old Jarek's boy, orcs with eyes like hot coals and something older below (`f756f876` T3).
- **Level 5:** he offers his preacher's hands, and Brenna puts him to stir the stewpot (`93213b5e` T4).

**Re-score:** Paul's 13 baseline runs (his part of the 26-run Paul/Lotta set) and his 5 post-rework runs, from stored transcripts. It ran on the box from the PR branch with `mix run --no-start` and wrote nothing to any database. That was 18 Jev calls for **$0.0062**. Raw rows: [`rescore-baseline-2026-10-08-paul-consequence.json`](scripts/jev-rescore/rescore-baseline-2026-10-08-paul-consequence.json) and [`rescore-post-rework-2026-10-08-paul-consequence.json`](scripts/jev-rescore/rescore-post-rework-2026-10-08-paul-consequence.json). Full output: [`results-2026-10-08-paul-consequence.md`](scripts/jev-confidence/results-2026-10-08-paul-consequence.md); everything above its new section is unchanged.

**Paul, three rubric versions** (unsure = confidence < 0.7):

| Rubric | Unsure, baseline | Unsure, post-rework | **Weighted, baseline** | **Weighted, post-rework** | Session weighted, base / post |
|---|---|---|---|---|---|
| #69 (`fd84ebb`) | 51% | 46% | 4.39 | 4.26 | 4.82 / 4.78 |
| first sharp (`7862783`) | 72% | 74% | 4.44 | 4.34 | 4.89 / 4.86 |
| **consequence (`df3c861`)** | **33%** | **48%** | **4.41** | **4.27** | 4.88 / 4.86 |

**Deltas, post-rework minus baseline** (95% CI, bootstrap over runs, seed + 3):

| Rubric | **Turn weighted Δ** | Unsure share Δ | Session weighted Δ |
|---|---|---|---|
| #69 | −0.12 (−0.20…−0.05) | −5 pp (−14…+5) | −0.04 (−0.15…+0.07) |
| first sharp | −0.10 (−0.21…0.00) | +2 pp (−13…+13) | −0.03 (−0.12…+0.08) |
| **consequence** | **−0.14 (−0.24…−0.03)** | **+15 pp (+2…+28)** | −0.01 (−0.09…+0.08) |

This bootstrap uses its own seed, so the #69 and first-sharp CIs differ from the section above by up to 0.01. The point estimates are the same.

**Breakdown at 0.7 (turns):**

| Rubric | Dataset | Confident-high | Confident-middle | Confident-low | Unsure |
|---|---|---|---|---|---|
| #69 | baseline / post | 64 (49%) / 27 (54%) | 0 / 0 | 0 / 0 | 66 (51%) / 23 (46%) |
| first sharp | baseline / post | 36 (28%) / 13 (26%) | 0 / 0 | 0 / 0 | 94 (72%) / 37 (74%) |
| consequence | baseline / post | 87 (67%) / 26 (52%) | 0 / 0 | 0 / 0 | 43 (33%) / 24 (48%) |

**Level probabilities on the consequence rubric:**

| Dataset | Most likely level 1/2/3/4/5 (turns) | Sure turns: level 4 / level 5 | Mean p of levels 4 / 5, unsure turns |
|---|---|---|---|
| baseline | 0 / 0 / 3 / 75 / 52 | 49 / 38 | 0.47 / 0.43 |
| post-rework | 0 / 0 / 0 / 30 / 20 | 19 / 7 | 0.42 / 0.40 |

What it shows:

- **The rule works where it applies.** Jev now separates "told something" from "the world reacted" on most turns: 87 of 130 baseline turns are sure, 49 at level 4 and 38 at level 5. On the first sharp version only 36 were sure.
- **The headline and the deltas don't move.** The weighted headline is within 0.03 of the #69 one on both sides. Paul's turn-level dip stays about −0.1 and is now clear of zero (−0.14, CI −0.24…−0.03). His sessions don't move.
- **Why some turns stay unsure.** Jev returns no rationales, so this comes from the vectors and from reading the turns. Of the 43 unsure baseline turns:
  - **25 sit just below the cutoff** (confidence 0.6–0.69).
  - **35 are still a 4-vs-5 split** (p4 + p5 ≥ 0.8). They are turns where it is debatable whether the world reacted to *his* choice. Examples:
    - a free first ale "for a polite stranger" (`761713eb` T1, 0.50 / 0.48): a gift, which never counts, but given because of his manner;
    - a turn where his question about two watchers makes them get up and demand a toll (`26d2424a` T7, 0.23 / 0.64): a consequence of his asking, but a hostile one, on a scale of frustrated to delighted.
  - **6 baseline and 7 post-rework turns carry ≥ 0.3 on levels 1–3.** These are turns where the play itself limped. In `761713eb` T8, for example, he pleads with Osric but the GM has him speak to Brenna.
- **Why post-rework is murkier.** Post-rework, unsure turns rise by 15 pp (CI +2…+28). Its runs bring more threats and confrontations: by a rough keyword count (toll, club, blade, fight, outside and the like), 70% of post-rework Paul turns against 48% in the baseline. Those are the turns where "the world reacts" and "would he be delighted" pull apart. Five post-rework runs is a small base, so read this as a hint, not a finding.

Reproduce: `python3 docs/scripts/jev-confidence/confidence_matrix.py /workspace/baseline/final /workspace/compare/final > results.md`. *Added 2026-10-08:* add `--rescore-conf docs/scripts/jev-rescore/rescore-baseline-2026-10-08-conf.json` for the Paul and Lotta turn-level reading, and see the script's [README](scripts/jev-confidence/README.md) for the re-score command. *Added 2026-10-08:* `--sharp-base` / `--sharp-post` with the two `*-sharp.json` files add the weighted headline and the sharpened rubric. *Added 2026-10-08:* `--paul-cons-base` / `--paul-cons-post` with the two `*-paul-consequence.json` files add Paul's consequence rubric.

## Appendix: reproducing

```bash
# 0. re-score the baseline's Paul and Lotta runs with the new rubric (Jev only), from an ex-tales-forge checkout of main
EXPORT=/workspace/baseline/final/jev_export.json OUT=rescore-baseline-2026-10-07-main.json \
  mix run docs/scripts/jev-rescore/rescore.exs
# 1. export (read-only) on the playtest machine
./put.sh docs/scripts/jev-compare/export.exs /tmp/export.exs
flyctl machine exec 801e9ef6136178 -a tales-forge-playtest "/app/bin/ex_tales_forge rpc 'Code.eval_file(\"/tmp/export.exs\")'"
flyctl ssh sftp get /tmp/jev_export.json final/jev_export.json -a tales-forge-playtest
# keep the two series; series_done.json = completed runs only (status finished)
# 2. analysis
python3 compare.py final/series_done.json --reference baseline-2026-10-07/default \
  --rescore rescore-baseline-2026-10-07-main.json --out final/report.md --csv final
python3 post_rework.py final final/series_done.json > final/post.md
python3 baseline_extra.py final final/series_done.json post-rework-2026-10-08 > final/extra.md
```

Script changes in this commit (`docs/scripts/`):

- `jev-compare/export.exs`: also exports `scenes` (location and time), `events` (session events; `gm_reasoning` payloads left out), `fronts` (status and runtime state, including `stages_fired`), and the session's `features` and `location_id`.
- `jev-compare/compare.py`:
  - `--reference COHORT` (the default is still `elara`);
  - `--rescore FILE` replaces the stored first pass with the re-scored new-rubric session and turn scores for the runs in the file.
- `jev-compare/post_rework.py` (new): per-persona deltas with CIs (session, turn mean, turns 1–5), leaving the inn (regex and recorded scenes), echo and tics, the Tinjacks (stages, first mention, fights), people and activity types, rolls, growth, cost and run conditions.
- `jev-rescore/rescore-baseline-2026-10-07-main.json` (new): the re-score rows used here (26 runs × old and new rubric).
