# Turn pipeline replay fixtures and harness spec

These fixtures test the turn pipeline refactor. The design is
`tales-forge-docs/docs/design-turn-pipeline.md` (approved by Fredrik,
2026-10-12, commit `4c1adae`). Section 9 is the eval plan. Case owns these
fixtures. Bobby builds the code. Gentry runs the sessions against them.

## Status: all pending

Every fixture has `"status": "pending"`. The code that they test is not on
main yet. `replay_test.exs` gives each fixture the ExUnit tag `:pending`.
`test_helper.exs` excludes that tag, so CI stays green.

- Run the pending replays with `mix test --include pending`.
- `pending_on` names the PRs that a fixture waits for. Each key is one PR in
  section 8 of the design.
- When all PRs in `pending_on` are on main, remove the tag for that fixture.
- `fixture_test.exs` checks the fixture shape. It is not pending. It runs on
  main now.

| `pending_on` key | Design section 8 step | Flag |
|---|---|---|
| `replay_harness` | This spec (see below) | none |
| `outcome_record` | 1. Outcome record (PR #199) | `TURN_OUTCOME_RECORD` |
| `premise_first` | 2. Premise first | `TURN_PREMISE_FIRST` |
| `state_from_mechanics` | 3. State from mechanics and the prose post-check | (none named) |
| `npc_memory` | 4. NPC memory and repetition guard | `NPC_DIALOGUE_MEMORY` |
| `catalogue_v2` | 5. Catalogue v2 | `JEV_CATALOGUE_V2` |
| `clarification_v2` | 6. Clarification v2 | (none named) |
| `history_strip` | 7. h-fa06 history strip | (none named) |

## Relation to the PR 1 replay files

PR #199 (Bobby) adds `test/fixtures/turn_replay/gentry_0caf.json` and
`issue_180.json`. Case owns those files from now on. They test PR 1 and run
in CI now. This directory adds only what they do not cover:

- The later stages (premise first, NPC memory, catalogue v2, history strip).
- Multi-turn checks.
- The new catalogue and the rules.

A fixture with `extends` replays a turn from those files with the target
expectations. When a later PR changes the PR 1 expectation (for example,
turn 5 becomes a rejected `equip`), update the PR 1 file in that PR.

The 0caf turns 3 and 4 and the #180 `h-fp14-sell` case are not repeated
here. The PR 1 files cover them.

## Categories

| Category | Count | What it covers |
|---|---|---|
| `gentry_regression` | 6 | Gentry session 0caf: compound rest, NPC repetition, the key gift, the armor claim, a sale across 2 turns |
| `issue_180` | 5 | #180: "the X I bought", "wearing X", NPCs before the premise check, h-fa06 over 3 turns, and a true-claim control |
| `catalogue_v2` | 18 | `rest` with a lodging price, `work`, `equip`, `give`, 1 to 3 ordered actions, `none_fits` |
| `rules` | 12 | No time for a rejected action, skill growth, prose/record mismatch |

## Credit

Gentry (QA) found the session 0caf failures and drafted the #180 items
h-fp12, h-fp13, h-fp14 and h-fa06 (draft PR #180). The fixtures with
`reused_from` use that text and context, and `credit` names the source.
The replay fixtures add the expected outcome record. Labels are agent drafts
(`"reviewed": false`) until Case reviews them.

## Item schema

Each line of `items.jsonl` is one fixture. The fields follow
`test/fixtures/intent_eval` where they can.

- `id`, `source`, `subsource`, `category`, `split` (always `tune`),
  `labeller`, `reviewed`, `note`: as in intent_eval.
- `context`: the start state. It uses the intent_eval context, plus
  `clock_minute` (the game clock in minutes) and `skills` (skill levels).
  A fixture can add state, for example a ground item. The
  fixture owns that state.
- `turns`: a list of 1 or more turns. The harness plays them in order on one
  session.
- `turns[].text`: the player input.
- `turns[].dice`: optional. A list of roll results (`"fail"` or
  `"success"`) for the skill checks in that turn.
- `turns[].gm_mock_prose`: optional. The mock GM returns this prose. Use it
  to test the post-check.
- `turns[].expect`: the expected result. See below.
- `status`, `pending_on`, `design_ref`, `description`, `reused_from`,
  `credit`: tracking fields.

### `expect`

The harness asserts the outcome record and the books. It does not assert the
prose words. The only prose checks are the post-check count and the
forbidden words for h-fa06.

| Key | Assertion |
|---|---|
| `intent.actions` | Jev returns these actions in this order (action and target). An empty list means "do not check". |
| `intent.none_fits` | The top class is `none_fits` (true) or is not (false). |
| `premise.rejected_claims` | Stage 2 rejects each claim in the list. An empty list means stage 2 rejects nothing. |
| `outcome.accepted` | The actions that stage 3 accepts, in order. |
| `outcome.rejected` | Each rejected action and its reason. |
| `outcome.coins_delta_copper` | The coin change in copper. An integer is exact. `">0"` and `">=0"` are bounds. `"any"` skips the check. `"-lodging_price"`: the coins go down by the lodging price that the world carries, and that price is above 0. |
| `outcome.items_added`, `outcome.items_removed` | The exact item ids that change. |
| `outcome.clock` | `"none"`: the clock does not move. `"advances"`: it moves. `"same_as:<id>"`: it moves the same as in that fixture. `"unspecified"`: no check. |
| `outcome.location_id` | The location after the turn. `null` or `"any"` skips the check. `"-lodging_price"`: the coins go down by the lodging price that the world carries, and that price is above 0. |
| `outcome.skill_changes` | The exact skill changes. `{}` means no skill changes. |
| `post_check.mismatches` | The number of prose/record mismatches. |
| `npc.<id>` | `no_repeat_of_memory`, `input_has_premise_findings`, `no_free_items`, `lines_must_not_contain`. |
| `history.must_not_contain` | The history that the next turn reads does not contain these words. `no_marked_copy` means the server stores no marked copy. |
| `gm_prompt` | `has_rejections`: the GM prompt holds these rejected actions. `rejection_phrasing`: the prompt uses the fixed template. |
| other keys | `coins_after`, `inventory_after`, `inventory_lacks`, `equipped`, `transfers`, `rest`, `stage_order`, `llm_calls`, `gm_prompt_note`, `intent_actions_max`, `mismatch_kinds`, `fixture_fails`. Each one is a direct check on the state or the record. |

## Harness spec

The harness is `TalesForge.TurnPipeline.Replay`. It does not exist yet.
Bobby or Case adds it with the first PR that turns a fixture on.

1. `Replay.run(item)` returns `:ok` or `{:error, failures}`.
2. The harness builds a session from `context` and the world in
   `test/fixtures/intent_eval/worlds.json`.
3. The harness uses the mock LLM provider. It never calls a live LLM.
   Jev runs from recorded readings or a stub that returns `expect.intent`.
4. The mock GM returns `gm_mock_prose` when it is set. Otherwise it returns
   prose that matches the record.
5. The harness plays each turn through the 5 stages in order. It records
   the stage order and the LLM calls.
6. After each turn, the harness compares the outcome record, the books and
   the history with `expect`.
7. The harness runs the post-check (design section 5) on each turn. One or
   more mismatches fail the fixture. A fixture with `fixture_fails: true`
   tests the checker: it passes when the checker reports the expected
   mismatch kinds.
8. The harness rolls dice from `dice` when it is set. It fails on a check
   that has no scripted result.
9. The harness sets the flags in `pending_on` to on for the run. It resets
   them after the run.

## Rules from the design (section 2, section 9 and section 11)

- A rejected action costs no game time.
- A skill improves only after a failure in that exact skill. Rest and work
  give no growth. Work gives coins only.
- Each prose/record mismatch counts as 1 bug. One mismatch fails the replay.
- An injection on turn N does not appear in any line on turn N+1 or N+2.
- A sale on turn N matches the coins on turn N+1.
