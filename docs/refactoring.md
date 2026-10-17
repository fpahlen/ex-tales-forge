---
title: Refactoring lessons
updated: 2026-10-17
---

# Refactoring lessons

What worked, and what went wrong, in the refactoring of 2026-10-16/17
(#324 to #348). The rules themselves are in
[Coding standards](coding-standards.md) and the gate is in
[Code health](health/README.md). This page has the patterns behind them,
each with the PR that showed it. Add a pattern here in the same PR as the
change that uses it.

A refactor changes no behaviour. `mix health.check` passes against the
base commit (no worse, usually better). Tests change only to follow a
function that moved or was deleted, never their assertions. Flag anything
a player or founder can see in the PR body.

## Prove it

- **Show that the output is the same, not only that the tests pass.** Run
  the old and the new code on the same inputs and compare the results:
  load main's version of the module under another name in a `mix run`
  script and call both on every combination of inputs that matters. For a
  page, render it on main and on the branch and `cmp` the HTML.
- **Put the health numbers before and after in the PR body**, and a
  one-line "Merge summary" that reads well on its own.
- **Run the checks on their own, or with `set -o pipefail`.** `mix test |
  tail` exits with `tail`'s code, so a failed check inside a `&&` chain
  lets the next step run.

## Dependencies

- **Move a pure read out of the cycle into a leaf module.** The NPC code
  called `Combat.carry/2` and `Context.dead?/2`, which put every NPC module
  in the big turn cycle. Both only read the npc_state they were given, so
  they moved to `Game.NpcState` (#325): cycles 78 → 67, compile-connected
  5 → 1.
- **The domain never calls the web layer.** Move what the domain needs into
  the domain (`Game.PlayPanel` from `PlayComponents`), or have the
  controller pass in the web value (the OAuth redirect URI) (#326).
- **A cycle that xref lists can hide others.** `mix xref graph --format
  cycles` lists only some cycles. A cut makes it list older paths between
  the same files, and those look new. The gate compares each cycle with
  the old tangles, because removing edges can't create a cycle (#327).

## Moving code

- **Delete forwarders; don't keep them.** When a function moves, move its
  callers and tests in the same PR and delete the old function. A
  temporary `defdelegate` is allowed only when moving every caller would
  make the PR too big. Say so in the PR body, and delete it in the next PR
  (#325 kept `Combat.carry/2` and `Context.dead?/2`; #328 deleted them).
  Doctests move with the function.
- **Products are independent.** Tales Forge and Workflow share no code.
  When both need the same thing (the health gate, the snapshot workflow),
  each repo gets its own copy and its own PR.

## Structs instead of long parameter lists

- **One struct is a pipeline accumulator,** like `Plug.Conn` or
  `Ecto.Changeset`. The caller fills in the inputs, small pure steps add
  the fields they compute (struct → struct, or `{:ok, struct}`), and the
  effects (Repo, PubSub, Oban, LLM calls) run at the edge, once.
- **Put the struct next to its only user.** Nest it in the module
  (`World.Lookup`, `JevIntent.Choice`, `Inventory.Transaction`), with a
  `@moduledoc`, `@type t` and `@enforce_keys` for the required fields.
- **One struct often removes several wide functions at once.** The helpers
  that took the same values take the struct instead:
  - `World.initial_state/8` → `/3` (#337)
  - `JevIntent.build_extraction/8` → `/1`, along with `parameters/6` and `put_numbers/5` (#341)
  - `Inventory.apply_trade/7` and `do_apply/7`, now one step per action (#342)
- **Watch the caller's complexity.** Building a struct literal adds to the
  caller's ABC score. When the caller goes over its ceiling, move the
  struct and the call it feeds into a small private step.

## The health gate

- **Compare with the base commit; commit no baseline.** While each PR
  rewrote `docs/health/baseline.json`, every two open PRs conflicted.
  Now CI measures the base in a worktree with that commit's own
  `mix health.check` and fails only when the PR is worse (#343). The proof
  was #341 and #342, which merged back to back without a conflict.
- **The base on main is the merge's first parent,** not whatever main is
  when the job runs. On a dispatched run it is the merge base with main
  (#336, #343).
- **The gate measures only the code we write.** It counts `lib/` only and
  exempts what a framework dictates: `@impl` callbacks, the `~p` edges into
  the router (#338), and application.ex starting the web children (#345).
- **Mark a change in counting in the history** (`counting` in each row),
  so a drop that comes from counting differently isn't read as refactoring.

## CI and the health history

- **Bot PRs need a non-`pull_request` run.** Since GitHub's change of
  2026-06-11, every `pull_request` run on a PR that `github-actions[bot]`
  opened waits for a human to approve it. The rolling history PR gets its
  Test and Dialyzer from a `workflow_dispatch` run instead (#333, #334).
- **No concurrency group on a job that must run for every merge.** The
  group cancelled all but one pending snapshot, which dropped history rows.
  Each run now measures its own merge and retries its push (#346).
- **`GITHUB_TOKEN` can't push a workflow file.** A snapshot that merged an
  older `health-snapshot.yml` into the branch was refused ("refusing to
  allow a GitHub App to create or update workflow"). Each attempt now
  rebuilds from the latest main and checks that only `history.csv` and
  `trend.svg` differ from it (#348).

## Process

- **Never stack PRs.** Every PR has base `main`. If a change needs another
  PR's code, wait until that PR is on main, then branch from main.
- **Never force-push and never rebase.** To update a branch, merge main
  into it.
- **Small PRs, one idea each,** so any order of merging works. When two PRs
  must land in a given order, say so in both bodies.
- **Delete before you add.** Before you write a module, look for code that
  can go instead, and for what Phoenix, Ecto, Oban or the standard library
  already do.
