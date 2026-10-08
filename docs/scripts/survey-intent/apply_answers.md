# Applying founder survey 4 answers to the intent eval set (plan, not run yet)

Survey: [`founder-survey-4-intent.json`](../../founder-survey-4-intent.json), answered at
`https://tales-forge.fly.dev/admin/surveys/founder-survey-4-intent`. Fixture: ex-tales-forge PR #81,
`test/fixtures/intent_eval/items.jsonl` (12 **tune** items; never a holdout item).

Files in this folder:

| File | What it is |
| --- | --- |
| `select_items.py` | Picks the 12 items and fails if any is not in the tune split (stored split and the split recomputed from sha1(id)) or is an attack/safety item. |
| `jev_readings.exs` | Runs Jev (jev-1.13.0, playtest key) on just those items; output in `jev-readings-2026-10-08.json`. |
| `items_spec.py` | The scene text and suggested readings per item, each with its labels. |
| `build_survey.py` | Checks every reading's labels against gold, `acceptable_*` and Jev, dedupes, shuffles, writes the survey JSON and `mapping.json`. |
| `mapping.json` | Per question: item id, each option with its labels, where each label came from (`gold`, `acceptable`, `jev`), whether it is today's gold, and Jev's reading. |

## 1. Collect

1. Wait until every founder has answered (results page shows 4/4 complete), then set `status` to
   `closed` in the survey JSON (docs commit), so answers can't move while we label.
2. Download `/admin/surveys/founder-survey-4-intent/results.csv`. Each item has a column
   `Q<n> intent-<item id>` (the chosen option text) and `…: something-else`, `…: comment`.
   Once the ex-tales-forge `option_labels` PR is deployed, a `…: labels` column holds the chosen
   option's labels as JSON; until then, join the option text to `mapping.json` (exact text match;
   an option reworded after answers were given is matched through the stored survey snapshot of
   that version, so keep `version` honest).

## 2. Tally per item

For each item, count the answers (n = founders who answered it):

- each suggested reading (a set of labels: `action`, `target`, `later`, `later_target`; `when`
  follows from `later`);
- **Unclear** (`should_ask`);
- **Something else**: these are **reviewed by hand** (Case drafts, Fredrik decides). Each one is
  either mapped to one of the item's readings, mapped to a new label set (written into
  `mapping.json` under `manual`, with who decided), or set aside as not a reading (then it does
  not count towards n). Nothing is applied until every "something else" on that item is reviewed.

## 3. Turn the tally into labels

A **majority** means more than half of n (3 or 4 of 4 founders; 2 of 3).

| Outcome | Gold (`action`, `target`, `later`, `later_target`) | `acceptable_*` | `should_ask` |
| --- | --- | --- | --- |
| A reading has a majority, and Unclear is not the top answer | that reading | every other reading picked by at least one founder (a minority reading is plausible by construction: it was offered and someone chose it) | `false` |
| Unclear has the most votes (ties included), or no reading has a majority | the reading with the most votes (ties: keep today's gold if it is among them) | every reading picked by at least one founder | `true`, with `ask_between` = the two most-picked readings |

Details:

- Labels are written field by field: `gold.action`, `gold.target`, `gold.later`,
  `gold.later_target`; the other readings add their values to `acceptable_actions`,
  `acceptable_targets` and `acceptable_laters` (`{type, target}` pairs).
- Today's gold is **not kept as acceptable** unless a founder picked it or a "something else"
  answer was mapped to it. Every such drop is listed in the diff for Fredrik (it reverses Case's
  review and Fredrik's spot-check, so it gets a second look).
- `skill` is unchanged. If the new primary action makes the old skill meaningless (for example,
  `speak` → `move` with `skill: persuasion`), the item is flagged for a manual skill fix.
- `safety` is untouched (all 12 items are benign).
- Each changed item gets a `note` entry: `Founder survey 4 (2026-10-xx): 3/4 picked "<option>";
  1/4 "<option>"; was <old gold>`. `reviewed` stays `true`; `labeller` is unchanged.
- `should_ask` and `ask_between` are new gold fields. The fixture README schema and
  `TalesForge.IntentEval.validate/1` need them first (a small change on the intent-eval branch,
  or its follow-up if #81 has merged by then).

The changes go to ex-tales-forge as a PR (fixture + README), with a before/after table per item,
never straight to main, and only after Fredrik's OK on the diff.

## 4. Founder agreement report

Written to `docs/scripts/survey-intent/agreement-<date>.md`:

- Per item: n, the modal answer and its share (**agreement** = modal share; 4/4 = 1.00, 2/2 split
  = 0.50), the full split (each reading, Unclear, Something else), the resulting outcome
  (gold confirmed, gold changed, should-ask), and Jev's reading and confidence from
  `jev-readings-2026-10-08.json` (and from the latest `mix intent.eval` run, once re-run).
- Overall: mean agreement, the share of items with a majority, the share that came out should-ask,
  pairwise founder agreement and Fleiss' kappa over the 12 items (categories = the options of
  each item, Unclear included), and how often today's gold matched the founder majority.
- Field level: for items where founders split, which field they split on (action, target, or now
  vs later). That tells us which kind of ambiguity the game most needs to ask about.

## 5. Feeding the ask-band calibration

The design ([design-jev-intent §4](../../design-jev-intent.md)) acts above `T_act` (start 0.70),
asks below `T_ask` (start 0.45), and asks only when the top two readings would play out
differently. Calibration runs on the tune split only. The survey adds two things:

1. **Should-ask items as positives.** In `mix intent.eval`, an item with `should_ask: true` counts
   as a *justified* ask if Jev asks (confidence < `T_ask`) and its top two readings cover the
   founders' `ask_between` pair. If Jev acts on it, that turn counts as a miss in the clarifying
   table, even when the reading matches the plurality gold. Items with a clear majority count
   the other way: an ask there is an unneeded ask.
2. **Agreement as a calibration target.** For the 12 items, Jev's confidence is compared with
   founder agreement (reliability per item and the gap between the two). Items where founders
   agree 4/4 should land above `T_act`; 2/2 splits and Unclear wins should land below `T_ask`.
   `T_ask` is then chosen as before (ask rate on real-turn items ≤ 4%, at least half the asks
   justified), now with the should-ask items in the "justified" count.

Twelve items are too few to set thresholds on their own; they are a check on the band, and they
show whether Jev's low-confidence cases are the ones humans also find unclear. If the survey
shows a pattern (for example "plans said in a quote"), more tune items of that kind get labelled
the same way.

## 6. Order of work (when we run it)

1. Close the survey; export the CSV.
2. Hand-review every "something else" answer (Case drafts, Fredrik decides).
3. Run the tally script (to be written, `apply_answers.py`: reads the CSV + `mapping.json`, prints
   the per-item outcome and writes the patched `items.jsonl` to a scratch path; it refuses any
   item whose split is not tune).
4. Fredrik reviews the before/after table; then a PR to ex-tales-forge with the fixture change.
5. Re-run `mix intent.eval` (tune) and write the agreement report and the ask-band check.
