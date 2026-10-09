---
title: "Architecture baseline: ex-tales-forge main at 2f27ff1"
updated: 2026-10-09
status: baseline
---

# Architecture baseline: ex-tales-forge `main` at `2f27ff1`

**Baseline** of [whyse-ab/ex-tales-forge](https://github.com/whyse-ab/ex-tales-forge) `main` at `2f27ff1` (#85, 2026-10-09), reviewed 2026-10-09 in the spirit of *The Pragmatic Programmer* (Hunt and Thomas): DRY, orthogonality, broken windows, reversibility, and the team's own rules ([call types](call-types.md), state written only by Elixir rules and Jev, each thing lives in one place, docs/specs/tests for every module). It was a read-only sweep of the whole codebase, not of one PR.

Every merge to `main` from here on gets a review like this, measured against this baseline ([decision 2026-10-09](decisions.md#2026-10-09-pragmatic-programmer-architecture-review-on-every-merge-to-ex-tales-forge-main)). **Each refactor below lands as its own PR, and each PR needs Fredrik's OK** like any other code change.

## 1. Verdict

The codebase is in reasonable health for a young project. Most modules have docs, there are about 811 tests, golden-prompt and prefix tests exist, CI runs Dialyzer, and LiveViews mostly delegate to contexts. The trouble is in three places:

- **The intent pipeline and the AI-call plumbing** (Jev and the LLM). They grew by copy-paste and feature flags, so adding a fallback intent provider or latency probes today would mean touching five or more places.
- **The team's own rules.** The LLM is still asked for structured output in several places, and the GM's reply still writes state.
- **Adventure-specific knowledge.** Tin Valley and Crossroads details are hard-wired in code instead of living in the packs.

## 2. Top findings, ranked by impact

Size: S = small, M = medium, L = large.

### 1. The intent pipeline has three readers and no shared interface (L)

- **Where:** `Game.Intent` (heuristic plus the Tier 1 LLM), `Game.JevIntent` plus `TalesForge.IntentJev` (two near-identical names for one job), and the routing in `GameSessions.resolve_and_enqueue*/jev_outcome/build_player_action/maybe_shadow`.
- **What's wrong:**
  - `GameSessions` holds two parallel paths covering off/shadow/on, clarifications and shadow mode.
  - The text `"\nClarification: "` is glued onto the message in three places.
  - `TurnProcessor.next_turn_number/1` runs a database query up to three times per message.
  - A fallback provider would become a fourth branch.
- **Fix:** add an `IntentReader` behaviour (heuristic, tier1, jev, fallback) behind one `Intent.Pipeline.resolve/3` that returns `{:act, …}` or `{:ask, …}`, and keep `GameSessions` to enqueueing only.

### 2. The Jev client is copy-pasted four times, and estimated costs are recorded as provider-billed (M)

- **Where:** `IntentJev.post_within/record_call`, `NpcReactions.call_one/record`, `Playtest.JevScorer.call_jev/record_usage`, `IntentEval.Readers`.
- **What's wrong:**
  - The model name `"jev-1.13.0"` is hard-coded five times.
  - The price ($0.042 per 1M input tokens) is hard-coded three times, with two different formulas.
  - Timing and the `AICalls.record` call are duplicated in each copy.
  - Each copy turns its estimate into `cost_ticks`. `AICalls.cost/2` treats `cost_ticks` as the provider's bill, so estimated costs are stored with `cost_source: "provider"`.
  - `JevScorer` never records failed calls.
- **Fix:** one `TalesForge.Jev` wrapper that handles the deadline, timing, cost recording and per-session latency. The model goes in config and the price in `:llm_prices`. This is the natural home for the latency probes.

### 3. `TalesForge.LLM` hard-wires providers, and the Anthropic path is broken (M)

- **What's wrong:**
  - Providers are picked by string prefix, and the base URLs, the 120 s timeout and the 1.5 s probe timeout are hard-coded.
  - `Config` and AGENTS.md advertise `anthropic`, but `resolve_tier_model` returns `"anthropic/…"` and `request/4` rejects it as `{:unsupported_model, _}`.
  - Without an xAI key, `ollama_reachable?` makes an HTTP probe every time a model is resolved.
  - The module owns the reply schemas for six purposes, and its moduledoc is one line long.
- **Fix:** a provider table in config (base URL, key name, timeout) plus a small provider behaviour; drop or implement Anthropic and Ollama; move each schema to the module that uses it.

### 4. The call-type rule and the state-ownership rule are both broken (M–L)

- **Where:** `LLM.complete_intent` (Tier 1), `complete_persona`, `complete_scorer`, `complete_fact_extract` (`World.Extract`).
- **What's wrong:**
  - All four ask the LLM for structured JSON, which the rule calls a smell. The scorer, for example, returns 1–5 scores plus evidence.
  - The GM reply schema still carries `npc_memory_updates`, which `NPC.apply_gm_updates/3` writes into NPC memory.
  - It also carries `context_summary`, which `TurnProcessor.maybe_apply_context_summary` writes to `world_state["situation_lines"]`. That feeds back into the next intent context.
  - So the LLM writes state.
- **Fix:** produce memory and summary with Jev or Elixir after the turn, and retire Tier 1 once Jev-on is proven. The direction is already decided ([Stateful world: four design answers](decisions.md#2026-10-08-stateful-world-four-design-answers), answer 4); the code has not caught up yet.

### 5. Adventure content is hard-coded in Elixir (M)

- **What's wrong:**
  - The Crossroads world is an Elixir map in `Game.World`. Its places also exist as `priv/adventures/crossroads_ledger/world/*.md`.
  - Its NPCs exist both in `priv/npcs/*.json` and in the pack's `npcs/marta_kellen.md`.
  - `"tin_valley"` gets special `case` branches in `NPC.seed_session`, `Fronts`, `GameSessions`, `Context`, `HomeLive` and `CreateCharacterLive`.
  - `"weary_pilgrim"`, `"crossroads_ledger"` and `["marta_kellen"]` are used as fallbacks in about 8 places. `Inventory` falls back to `weary_pilgrim` even in Tin Valley.
- **Fix:** make Crossroads a full pack, add one `Pack.catalog/0`, and delete the fallbacks.

### 6. "Pure game logic" isn't pure, and the intent context is an untyped map (M–L)

- **What's wrong:**
  - `Repo` is used in 7 `Game.*` modules: `SceneProcessor` (5 calls), `TurnProcessor`, `Context`, `NpcReactions`, `Perception`, `Fronts`, `Fronts.Moves`.
  - `Inventory` calls `NPC.stock_map/persist_stock_updates`, which hit the database in the middle of a rule.
  - `IntentJev.with_narration` pulls data from the database through `NpcReactions.last_narration`.
  - The intent context is a 22-key string-keyed map built in two places (`Context.build_intent_context`, `IntentEval.build_context`) and enriched in a third.
- **Fix:** a typed `IntentContext`/`TurnInput` struct loaded once at the edge, with `Game.*` reduced to data in, data out.

### 7. `Game.Inventory`, the money and items rules, is a blind spot (M)

- **What's wrong:**
  - 743 LOC marked `@moduledoc false`, yet it exposes 15 public functions with 0 `@spec`.
  - `do_apply` is about 120 lines; `validate_transaction`, `resolve_action` and `apply_trade` are each about 70 and re-derive the same buy/trade facts.
  - Price lookup is duplicated in `Intent.stock_price`.
  - Only 11 tests target it directly.
- **Fix:** split into a pure `Inventory.Transaction` (validate, then apply, returning changes) plus a persistence step; add docs, specs and property tests.

### 8. Errors are swallowed (S–M)

- 34 `rescue`/`catch` sites, against the rule "rescue only domain exceptions". The worst:
  - `IntentJev.shadow` (`rescue _ -> :ok`) and `safe_validate` (`_ -> nil`).
  - `AICalls.record` rescues everything, so cost rows can vanish silently.
  - `Characters.mirror` swallows double-write failures, and the upcoming read switch depends on that data.
- **Fix:** let these crash under `Task.Supervisor` and add telemetry counters for mirror and ai_call failures.

### 9. Old paths and things living in two places (M each)

- **Baseline variant:** 35 branches across 15 modules, 13 of them in `intent.ex`.
- **`sanitize_summary`:** a pointless alias of `sanitize_quote`; `@quoted` and `@quoted_speech` are the same regex.
- **Collab:** the decision queue stores decisions in Postgres, and "export back to Markdown is a TODO" (the UI flash even says so). That gives decisions a second home besides `docs/decisions.md`.
- **NPC memory:** stored in both `npc_instances.runtime_state` and `character_memories`. `Playtest.CharacterChanges` (1,130 LOC) has to guess who wrote a memory from its text.
- **Fix:** set retire-by dates for the baseline arm and Tier 1, decide Collab's fate, and add a memory `source` field.

### 10. Spec debt and scattered GitHub/env access (S–M)

- **Specs:** core contexts have none. `NPC` (24 public functions), `AICalls` (23), `Costs` (23), `Admin` (22), `GameSessions` (13) all have 0.
- **GitHub REST client:** hand-rolled 5 times (`AdminAuth.GitHub`, `Survey.Source`, `Collab.Importer` ×2, `Collab.Files`).
- **Env reads:** `Admin.DecisionLive.Index` reads env vars directly, as do `Collab.Files` and `RunMeta`, bypassing `Config`.
- **Role detection:** `AppRole` asks `Costs.playtest?/1` which app it is, which points the dependency the wrong way.
- **Fix:** one GitHub client, all env through `Config`, and spec backfill starting with the core contexts.

No remaining code syncs with the old app. The only sync left is `mix tales.sync_docs`, which pulls this docs repo into Collab (finding 9).

## 3. Test gaps

- No test names the 6 Jido NPC action modules, `Game.Fronts.Rules`, `Playtest.Reports`, `Playtest.PlayerView` or `AICalls.Steps`.
- `Inventory` is thin (finding 7).
- `JevIntent`, `Intent` and `TurnProcessor` are reasonably covered.

## 4. Quick metrics

| Metric | Value |
|---|---|
| `lib/` | 183 files, about 197 modules, about 33.5k LOC |
| `test/` | 108 files, about 17.5k LOC, about 811 `test` blocks |
| Coverage gate | 72% |
| Largest modules | `playtest/character_changes` 1130, `game/intent` 811, `character_creation` 778, `create_character_live` 763, `game/inventory` 743, `llm` 718, `intent_jev` 683, `game/turn_processor` 643, `game/pack` 593, `game_sessions` 580 |
| `@moduledoc` | 169/183 files (92%). Missing or `false`: `Inventory`, `ActionHandler`, 6 NPC actions, `PlayComponents`, `AdminComponents`, `Collab.Markdown`, 2 Collab schemas, `Application` |
| `@spec` | 372 specs for 1,024 public functions (about 36%). Only 42 files (23%) have specs on 80% or more of their functions; Credo's specs check covers about 29 files |
| Doctests | `iex>` examples in 34 files; 27 test files run `doctest` |
| Longest functions | Mostly HEEx `render` (`PlaytestLive.Show` about 288 lines, `CostsLive` about 229). In logic code: `Inventory.do_apply` about 120, `ActionHandler.resolve` about 100, `TurnProcessor.run_steps` about 70 |

The metrics are rough: line counts and regex counts over `lib/` and `test/`, not a tool run.

## 5. Suggested order for refactor PRs

Each is a separate PR in ex-tales-forge and needs Fredrik's OK to merge.

1. **`TalesForge.Jev` wrapper plus the cost-source fix** (S–M). Removes the duplication and is where the per-session latency probes go.
2. **LLM provider config; drop or implement Anthropic and Ollama** (M). The base for the fallback provider.
3. **`IntentReader` behaviour and `Intent.Pipeline`, moving routing out of `GameSessions`** (L). The fallback intent provider then lands as one new module.
4. **Error-handling cleanup and telemetry for mirror and ai_call failures** (S).
5. **Typed `IntentContext`/`TurnInput`; move Repo calls out of `Game.*`** (M–L).
6. **Split `Inventory`, with docs, specs and tests** (M).
7. **Crossroads as a full pack; delete the adventure hard-codes** (M).
8. **Move GM memory and summary writes to Jev or Elixir; retire Tier 1** (M–L), following the 2026-10-08 stateful-world answers and their order relative to Jev intent PR 2.
9. **Ongoing:** retire the baseline arm when it closes, decide what to do with Collab, one GitHub client, spec backfill for `NPC`, `GameSessions`, `AICalls` and `Costs`.
