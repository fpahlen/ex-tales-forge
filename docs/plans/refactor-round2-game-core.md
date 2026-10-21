# Refactor round 2: game core

Base: origin/main c296bf7. I checked the count with `mix health.check --out` on main: **73 complex functions** (Credo cyclomatic > 9 or ABC > 30). All 23 functions in scope are on that list. Target after round 2: **50**.

## Rules for every PR
- Write characterization tests first, in their own commit. Behaviour does not change: same return values, same error messages.
- Delete before adding. Each PR ends net down on health: the complex count drops, there are no new cycles, no web refs, and no new wide functions (4+ params).
- A file may grow by at most max(10%, 3 lines). If it grows, the PR body says why.
- New data goes in `%Struct{}` with defaults on every field. Functions match on `%Struct{}`.
- Pure core: anything that touches the filesystem, an Agent, or the World lookup stays at the edge, and the logic is a pure function behind it.
- Turn-critical files (action_handler, movement, premise_check, and intent, which feeds them) get playtest-safe tests: behaviour through the public turn path, using the `test/support/turn_pipeline` replay fixtures, with no LLM calls. The API keys are unset, as in the gate.

## PRs, most important first

1. **Action type tables** (schemas.ex `action_type_atom` cyc 22, action_handler.ex `resolve_type` ABC 48 / cyc 16). Count: 73 -> 71.
   - `action_type_atom`: replace the case with a module attribute map `@action_types %{"observe" => :observe, ...}` plus `Map.get(@action_types, type, :other)`. Delete the case.
   - `resolve_type`: a data table `@handlers` from action_type to a `%HandlerSpec{handler, notes, hints, skill, ticks?}` row (defaults on every field). A small `build/2` fills in target, skill and ticks. The skill-gated observe/interact/other/freeform pair and the combat default stay as two named clauses. Keep the `no_move` head.
   - Tests: a table test that maps every action_type to its HandlerResult, taken from current main, plus 2-3 turn replays (move, wait, inventory).
   - Risk: the stub/inventory lists come from attributes, so the table must be built from them and not copied, or they drift.

2. **Intent `inventory_target`** (cyc 11). 71 -> 70. Collapse `:sell`, `:spend` and `:train` into one `in` clause, or use a map from action to parameter key (`item_id`/`npc_id`/nil). Turn replay tests for buy/drop/sell.

3. **Movement `mentioned_places`** (ABC 43). 70 -> 69. Add `%PlaceHit{id, hops, pos, term}`. Extract `hits_for/3` (one place gives its hits) and `rank/1` (the sort key). Turn tests: "go to the cut" vs "cut off the chill", and the tie broken by hops.

4. **PremiseCheck `kill_subject`, `sentence_claims`** (ABC 41, 35). 69 -> 67.
   - `kill_subject`: split it into `find_person/2` and `front_status/2`, which return a tagged result, and `verdict/2`.
   - `sentence_claims`: make the claim finders a list `@finders [&coin_claims/1, ...]`, with kill_claims wrapped for its arity-2 form, then flat_map. Delete the `++` chain.
   - Risk: finder order affects the sort tie-break, so keep the list order. Use the existing premise replay tests plus new kill/claim characterizations.

5. **Pack** (`load` 54, `validate_graph!` 38, `chain!` 33, `position!` cyc 10). 67 -> 63.
   - `load`: split into `read_pack!(dir, features)`, which returns a `%Pack.Raw{adventure, extensions, locations, npcs, fronts}` (the filesystem edge), then `validate!(raw)`, then a pure `build(raw, features)`.
   - `validate_graph!`: split into `check_start!`, `check_exits!` and `check_doors!`.
   - `chain!`: one `step/3` that returns `{:done | {:next, parent} | {:error, msg}}`, plus a raise wrapper.
   - `position!`: three tiny checkers (`check_at!`, `check_scale!`, `check_cell!`).
   - Tests: pack_test already covers the happy path. Add a test for each error message (exact string).

6. **World `collect`, `prompt_lines`** (ABC 62, 41). 63 -> 61.
   - `collect`: a pure `specs(world, defs)` that returns `[%AgentSpec{id, role, kind}]`. The `ensure`/Agent calls stay in a thin `collect`. This is the effect at the edge.
   - `prompt_lines`: a `%Budget{lines: [], count: 0, chars: 0}` struct and `add_agent(budget, agent)`.
   - Risk: collect touches processes. The test checks specs as a pure function, and one test goes through the Agent.

7. **Progression `resolve_rest` + SkillSplit `split`** (ABC 59, 38). 61 -> 59.
   - `resolve_rest`: `%RestAcc{char, attempts: [], pending: [], rolls}`, plus `eligible_skills(char, only)` and `step(skill, acc, reflected)`. Fix `pending ++ [skill]` so the order stays the same.
   - `split`: extract `perform_parts/3`, `learned_lp/2` and `resolution/3`.

8. **WorldSim `apply_threshold`, `apply_matching_events`** (ABC 41, 36). 59 -> 57.
   - `apply_threshold`: a guard predicate `threshold_fact(front, clock, defn)` that returns `{:ok, row}` or `:skip`. The update stays separate.
   - `apply_matching_events`: lift the fn into `apply_event/3` that returns `{cur, acc}`.

9. **OutcomeRecord `item_deltas` + ProseCheck `items`** (ABC 37, 35). 57 -> 55.
   - `item_deltas`: `delta_entry(id, before, after, names)` returns `{:gained | :lost, entry}` or nil, then a split by tag.
   - `items`: extract `candidate_phrases(lower, paid?)` and `unexplained?(phrase, gained)`.

10. **Text helpers: NpcMemory `lines`, Gestures.Forms `verb`, Rest `rest_place?`** (ABC 49, 48, 34). 55 -> 52.
    - `lines`: one `quote_line(prose, match, npcs)` per match.
    - `verb`: a `suffixes(base)` rule list that returns `{third, ing, past}` stems. Use a table test of about 20 verbs first.
    - `rest_place?`: pure `lodging?(location)`. The location fallback to World.location stays at the edge.

11. **Catalogue `give` + Prices `by_amount`** (ABC 33, 36). 52 -> 50.
    - `give`: `give_item/3` and `give_coin/3`.
    - `by_amount`: `fill_up/3` and `narrow_down/2`.

## Risks
- Exact error and notes strings feed prompts and tests, so the characterization tests must assert the full strings.
- Order-sensitive accumulators (`++ [x]`, sort tie-breaks) are easy to change by accident. Each one gets a test that pins the order.
- New helper structs must not be public API. Keep them nested or `@moduledoc false` so no new xref edges or cycles appear.
- Files that are already big (intent 799, premise_check 777, pack 726) can grow when helpers are extracted. Offset that by deleting the old branches in the same PR, and state any growth in the PR body.
- The health gate counts by function name: a helper that ends up over the limits (ABC > 30) shows up as a new complex function and fails the gate. Run `mix health.check --base origin/main` before each push.
- PR 1 and PR 2 touch the turn path. Run the playtest replay suite, and do not merge them together.
