# Social acts: founder survey 5 and the plan for the Jev comparison (2026-10-19)

This is the founder-labelled set for the G1 experiment in
[`analysis-social-levers.md`](../analysis-social-levers.md) (PR #479, "Riskiest
assumption and the experiment"). Fredrik approved the survey. Founders label
40 player lines. Later, Jev reads the same lines, and we score Jev against the
founder majority.

**Status:** the survey is built. Jev has not been run on these lines.
Fredrik sets the pass bar below **before** any Jev run.

> **Founders:** answer the survey before you read this doc or
> `scripts/survey-social/mapping.json`. They say which lines are scripted.

## The survey

| | |
| --- | --- |
| Definition (source of truth) | [`founder-survey-5-social.json`](../founder-survey-5-social.json) |
| Readable copy | [`founder-survey-5-social.md`](../founder-survey-5-social.md) |
| Builder | [`scripts/survey-social/`](../scripts/survey-social/) (`items_spec.py`, `extract_real.py`, `build_survey.py`) |
| Line origins | [`scripts/survey-social/mapping.json`](../scripts/survey-social/mapping.json), and `origin` / `source` on each section of the JSON |
| Page (production) | `/admin/founders/surveys/founder-survey-5-social`, and a tab on `/admin/founders/survey` |

It uses the founder-survey mechanism without changes (the same as founder
survey 4, `founder-survey-4-intent`). The app reads `docs/<id>.json` from `main`
through the GitHub Contents API and caches it for 60 s. A merge to `main` makes
the survey live on production. No deploy is necessary. The copy in
`priv/surveys/` is only the fallback snapshot. It ships with the next deploy.

### What founders answer, for each line

1. **The social act:** one of the 14 G1 labels, or `unclear`. The option text
   gives a one-line description of each label. Jev must get the same
   descriptions, word for word, in the comparison (`SOCIAL_ACTS` in
   `build_survey.py`).
   `none`, `request`, `offer`, `gift`, `thanks`, `compliment`, `flattery`,
   `joke`, `insult`, `threat`, `apology`, `promise`, `claim`, `refusal`.
2. **The target:** one of the people present, "everyone here", "no one in
   particular", or "unclear".
3. **The voice:** the step-1 `voice` levels of PR #481
   ([`2026-10-two-step-jev.md`](https://github.com/whyse-ab/ex-tales-forge/blob/bobby/exp-two-step-jev/docs/experiments/2026-10-two-step-jev.md),
   open): `whisper`, `talk`, `shout`, `none` (says nothing aloud), plus `unclear`.

`option_labels` map each option to `social_act`, `target` (a character slug,
`everyone`, `no_one`, or null) or `voice`. The results page, the CSV and the
Markdown export show these labels. The survey page does not.

Each line shows the minimal context: where the scene is, who is present, the
player's turn before, the tail of the GM narration before the line (at most 420
characters), and the line.

### Blind

- The survey page shows no Jev reading and no other founder's answer. Jev has
  not read these lines, so no reading exists to leak.
- The survey page does not show which lines are scripted. The app ignores the
  `origin` and `source` keys on each section. Real and scripted lines are
  shuffled together (fixed seed).
- The results page (`…/results`) shows all answers to any team member. The
  intro asks founders to open it only after they finish. The mechanism has no
  lock for this. Survey 4 is the same.

### The lines: 24 real, 16 scripted

**Real (24):** player lines from the 2026-10-18 playtest sessions. Production
had no turns on 2026-10-18 (Europe/Stockholm), so all real lines come from
playtest. The query is [`real_turns.sql`](../scripts/survey-social/real_turns.sql).
It ran inside `BEGIN TRANSACTION READ ONLY … ROLLBACK` on
`tales-forge-playtest-db-wa`. The same check ran on `tales-forge-db-wa`.

| Session (playtest) | Lines | What it was |
| --- | --- | --- |
| `3705591b` | 10 | The 38-input GameCharacter 10e script ("after" run, [transcript](../playtests/2026-10-18-10e-after/transcript.md)) |
| `6d938a30` | 7 | The offer and quote retest (short answers: "Yes.", "No, thank you.") |
| `253e26a5` | 3 | Trade retest at the inn |
| `3a27fdde`, `464229eb`, `643b8031`, `9a971f8d` | 1 each | Short QA runs at the inn |

What was kept: the player's line, the player's line before it, and the tail
of the GM narration before it. What was left out: the player character's name
(the survey says "a traveller"), the `founder` column, user rows, character
sheets, and all `ai_calls` rows (so no Jev reading). Presence comes from the
transcript state lines for `3705591b`, and from the GM narration for the other
sessions.

The real lines are mostly trades, questions and plain answers. PR #481 found
the same: these sessions have no insults, threats, jokes, whispers or shouts.

**Scripted (16):** lines written for this survey, in the same places and with
the same people. Together they cover insults (3), threats (3), shouts (3),
jokes (2), sarcasm (2), whispers (2), thanks (2), promises (2), requests (2),
and one each of flattery, compliment, apology, gift, offer, claim and refusal.
Several lines mix two acts on purpose (a sarcastic compliment, a whispered
threat, a shouted round of drinks). `covers` in `mapping.json` is what a line
was written to test. It is **not** a gold label. The founder majority is the
label.

## Proposed pass bar (Fredrik sets it before any comparison)

**Proposal:** Jev passes when its social act equals the founder majority on
**at least 80% of the scored lines**.

Details to confirm or change:

- **Majority:** more than half of the founders who answered the line pick the
  same act. A line with no majority is not scored for the act.
- **"Unclear" wins:** Jev agrees when its confidence on the act is below the
  G1 confidence gate (it would fall back to `none` and do nothing social), or
  when it returns `unclear`.
- **Scored set:** all 40 lines. Report real and scripted lines separately too.
- **Founder ceiling:** report founder-to-founder agreement first. If it is
  below 80%, the bar is above the ceiling, and Fredrik decides again before the
  run.
- **Guard rails (report, and proposed as extra fail conditions):** the count of
  harmful confusions (`joke` read as `insult`, `flattery` as `compliment`,
  `claim` as `none`), and confident-wrong reads (Jev confidence ≥ 0.8 and not
  the majority). Proposal: at most 2 harmful confusions, and at most 5% of
  lines confident-wrong.
- **Target and voice:** report agreement with the same majority rule. No bar is
  proposed for them in this round.

| Decision | Value |
| --- | --- |
| Pass bar on the social act | _Fredrik: ____ (proposed: ≥ 80% of scored lines)_ |
| Guard rails | _Fredrik: ____ (proposed: ≤ 2 harmful confusions, ≤ 5% confident-wrong)_ |
| Set on | _date_ |

## The later comparison (design only, no code in this PR)

Two systems read the same 40 lines. Both get the same state for each line: the
scene, the people present, the previous narration and the line. For the real
lines, the deal state and the listener state (liking, concerns) come from the
session at that turn. For the scripted lines, `items_spec.py` gets that state
before the run.

**System 1:** the current single Jev intent call, with the G1 `social_act`
question added (and `voice`, as PR #481 recommends). One call per line. It
gives a label and a confidence for each question.

**System 1 + System 2:** System 1 runs first. A System 2 reasoning pass runs
only when one or more triggers fire:

| Trigger | Proposed test (pure code, on System 1's output and the game state) |
| --- | --- |
| Low confidence | confidence < 0.8 on the goods (item, price, quantity) or on the social act |
| Two or more plausible readings | the second social act has p ≥ 0.25, or the top two are within 0.15 |
| An open deal | an NPC in the scene has an open quote, offer or toll the line can answer |
| A strong concern or liking at stake | the listener's liking toward the speaker is ≥ 0.6 or ≤ −0.6, or a concern with priority ≥ 7 touches the line |

System 2 reasons briefly **as the listener**: what the speaker meant, from her
point of view. It returns one reading (social act, target, voice) and a
confidence. It does not decide. **Code decides**, with a fixed rule set before
the run. Proposed rule: use System 2's reading when its confidence is higher
than System 1's on the same question. Otherwise keep System 1's reading. The
G1 confidence gate applies after that, the same for both systems.

**Report for each system:**

- agreement with the founder majority (social act, target, voice), all lines,
  then real and scripted separately;
- the pass or fail against the bar above, and the guard rails;
- for System 2: the trigger rate (share of lines, and which trigger fired), the
  lines it changed (right to wrong, and wrong to right);
- cost: tokens and USD for each line and each triggered line, from `ai_calls`
  (playtest key);
- latency: p50 and p95 added on triggered lines. System 2 runs after System 1,
  so its latency adds to the turn.

Out of scope here: the System 2 prompt, the model choice and the code. They
come in a later PR after Fredrik sets the bar and the founders answer.
