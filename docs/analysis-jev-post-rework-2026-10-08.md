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
- **Three runs hung and were dropped** (`a76294d9` and `1a995c9f` Lars T3, `0d1b8222` Paul T7). Each time the Tier 1 intent call (`purpose=intent`, `source=llm`) returned in 1.4–2.0 s, and then the turn logged nothing more until the run's turn timeout: no GM call, no NPC reaction, no error. 14 turns used the LLM intent path in the series (the baseline had 0), and 3 of them hung. **That points at the new move/intent path after Tier 1** (#68 `normalize_move`, the movement resolution, or what follows it), but it was not reproduced. Dropping them may bias Lars, since both of his hangs came at turn 3, while he was still in the inn.
- **Not an A/B on one deploy:** this compares a new day and deploy with yesterday's. Everything from #67–#73 changed at once: scene changes, inn world, antagonist, Brenna, rolls and growth. No single effect can be attributed.
- **Hindsight in turn scores:** as before. Hawk's late fight lifts his earlier turns.
- **Re-scored baseline:** Paul and Lotta's baseline scores come from a second Jev pass (±0.11 per session against the pilot). Their turn confidences are unknown.
- **Regex features:** the leave, inn, echo, tic, people and activity measures are heuristics. The leave regex misses many of the new move phrasings (§2). Activity types from player text are approximate.
- **The rubrics are the yardstick:** Hawk's danger scale rewards the gang's presence even without a fight. Paul's scale may penalise a less generous Brenna.

## 10. Recommendations

1. **Fix the hang first.** Add a timeout and logging around the step after a Tier 1 intent (movement resolution, triggers and the world tick). Replay the three runs (`a76294d9`, `0d1b8222` and `1a995c9f`). The hung turn's player text is not stored, so log the raw action on a timeout.
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
