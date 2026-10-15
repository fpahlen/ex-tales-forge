---
title: Coding standards
updated: 2026-10-09
---

# Coding standards

**Principle (Fredrik):** humans may need to understand the code one day. Code written by people or by coding bots must explain itself, be typed and be tested, and CI enforces this so a PR that breaks it can't merge.

Applies to [ex-tales-forge](https://github.com/whyse-ab/ex-tales-forge). Tooling: [PR #43](https://github.com/whyse-ab/ex-tales-forge/pull/43).

## The rules

1. **`@moduledoc` on every module.** Say what the module is for and how it fits into the system (the turn pipeline, who calls it, what it owns). Use `@moduledoc false` only for real internals, such as a helper used by one module.
2. **`@doc` on every public function.** Say what it returns and when it fails, not how it works line by line. Mark internal functions that are public only for tests with `@doc false`. Add a doctest (`iex>` example) where an example says it faster than prose and the function is pure.
3. **`@spec` on every public function**, checked by **Dialyzer** (dialyxir). Give structs a `@type t`, and use `Struct.t()` in specs rather than `%Struct{}`.
4. **Credo strict** (`mix credo --strict`), no new issues.
5. **Formatted** (`mix format --check-formatted`).
6. **ExDoc**: `mix docs` builds a browsable docs site from the above, and it must build without warnings.
   Each release also builds it (Docker builder stage) and serves it to admins only at `/admin/code-docs`, behind the same admin login as `/admin/costs`. Live in production and playtest since 2026-10-07 (PR #44). Locally, `mix docs -f html -o priv/code_docs` makes it show up there.
7. **Tests for every change.** A bug fix gets a test that fails without the fix. Coverage is tracked with `mix test --cover`, and CI fails below the threshold in `mix.exs`. Raise the threshold as coverage grows; never lower it to make a PR pass.
8. **CI enforces 1–7** (the Test and Dialyzer jobs). Both must be required checks on `main`, so a failing PR can't merge, and production deploys only after both pass.

## Existing code: backfill gradually

- The rules apply in full to new modules and to every function a PR touches.
- Older modules are backfilled module by module, starting with the core: the GM turn (`Game.TurnProcessor`, `Game.Context`, `Game.Prompts`), `LLM`, the Character/Person side (`Game.NpcReactions`, the NPC agents) and the world agents (`World`, `World.*`).
- Enforcement follows the backfill: once a module has `@doc` and `@spec` on every public function, add it to the `Readability.Specs` file list in `.credo.exs` and to `test/ex_tales_forge/coding_standards_test.exs`. Modules not on those lists are the legacy baseline.
- **Admin code gets lighter gates** (decision 2026-10-09 "A fast deploy lane for admin work", [#107](https://github.com/whyse-ab/ex-tales-forge/pull/107), merged): files on the `[admin]` list in `.github/deploy-lanes.txt` (surveys, costs, playtest admin pages, `/team`) need formatting and tests only. Credo skips them, and they are not on the `@spec`/`@doc` lists. Game and shared code keep every rule above. Game and shared code must never depend on admin modules (`mix deploy.check_boundaries` in CI).
- Dialyzer runs on the whole app. A warning we accept goes in `.dialyzer_ignore.exs` with a reason; the file is empty today.

## Commands

```bash
mix precommit       # everything CI runs: compile, format, Credo, tests + coverage, docs, Dialyzer
mix dialyzer        # first run builds the PLT in priv/plts (a few minutes)
mix test --cover    # coverage summary; HTML report in cover/
mix docs            # docs site in doc/index.html
```

## Status (2026-10-07)

- Dialyzer: 0 warnings. The first run found 22, all fixed. One was a real bug: full ISO timestamps were dropped when importing decisions.
- Coverage: 73.3% (threshold 72%).
- Backfilled: `LLM`, `Game.TurnProcessor`, `Game.Context`, `Game.Prompts`, `Game.NpcReactions`, `World`, `World.Agent`, `World.Extract`, `World.Prices`. Every module has a `@moduledoc`.
