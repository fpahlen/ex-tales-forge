---
title: "Design: auto-merge, fewer but better decisions"
updated: 2026-10-18
status: ex-tales-forge auto lane built; workflow waits for the app install
---

# Design: auto-merge (ex-tales-forge and workflow)

**Status:** design, 2026-10-18. Built for ex-tales-forge (docs-only and health-history; see `docs/DEPLOY-FLY.md`, "Auto lane"). workflow waits until `whyse-merge-bot` is installed there. It covers both repos. This file is the only copy; `whyse-ab/workflow` gets the same rules when it is built (step 6).

**Intent (Fredrik):** fewer but better decisions. A PR whose safety CI can prove merges on its own. Fredrik approves only the PRs that are real decisions.

## Classes

1. **needs-founder** (the default). Fredrik approves and merges. **Every** PR is in this class unless it fits an `auto` row below. Some changed paths force it, whatever the label, title or the bot says:
   - `priv/repo/migrations/**`, data scripts, and any `Repo.query` or SQL file: migrations and data.
   - `mix.lock`, `mix.exs`, `package*.json`, `assets/vendor/**`: new or bumped deps. The security lane keeps its own carve-out, below.
   - `fly*.toml`, `Dockerfile`, `rel/**`, `config/runtime.exs`, `.github/**`: deploy and the lane rules themselves.
   - `priv/**` outside migrations (packs, NPCs, prompts, surveys): user-visible content.
   - Any deleted file outside `docs/` and `test/`, and `docs/decisions.md`.
   - The label `user-visible`. The bot sets it, and Case checks it in review. A label can only **add** this class, never remove it.
2. **auto**. CI is green, and a bot merges with no human:
   - **docs-only:** every changed path is under `docs/`, except `docs/decisions.md`.
   - **health-history:** head branch `health-history`, changing only `docs/health/history.csv` and `docs/health/trend.svg`.
   - **refactor with a byte-identical replay:** only `lib/**` and `test/**` change (no forced path), and the `Replay` check on the head sha says identical. **Until that check exists, refactors stay needs-founder** (see "Replay in CI").
3. **security**: unchanged. [`security-lane.yml`](https://github.com/whyse-ab/ex-tales-forge/blob/main/.github/workflows/security-lane.yml) and `TalesForge.DeployLanes.Security` keep their own rules.

A needs-founder PR starts its body with one line, `What you're deciding: ...`. The lane run adds a warning annotation when that line is missing. (A check that runs after CI from `workflow_run` doesn't show on the PR, so the warning appears on the lane run.)

## How it works (reuse, not new machinery)

1. **One merge workflow.** `security-lane.yml` already has the right shape: it runs after CI (`workflow_run`), looks up the PR for exactly that head sha, gives up if the PR has moved on, runs the rules **from main** (so a PR can't rewrite them for itself), and merges with a bot token. It gets a second lane, `auto`, with its rules in `TalesForge.DeployLanes`. Its path patterns are a new `[founder]` section in [`deploy-lanes.txt`](https://github.com/whyse-ab/ex-tales-forge/blob/main/.github/deploy-lanes.txt), parsed by the matcher that already exists. The class comes from the diff of the head sha, never from the bot's word.
2. **Every check, not only the required ones.** The auto lane merges only when every check run on the head sha is `success`, or skipped by design (the docs-only skip in `ci.yml`). Test (which includes the health ratchet) and Dialyzer are already required.
3. **Only the sha CI passed.** It merges with `gh pr merge --squash --match-head-commit <sha>`, the same as the security lane. **Why not GitHub's native auto-merge:** native auto-merge stays armed across pushes, and it merges whatever head next passes the *required* checks. Our classification would then have to be a required check too, and a commit pushed after classification could still go in. The #458 lesson: a PR can be merged at any moment, so what merges must be exactly what was checked. `--match-head-commit` pins the exact sha that was classified and checked. If anything was pushed since, GitHub refuses the merge, and the new head is judged on its own CI run.
4. **Bot token.** A merge made with `GITHUB_TOKEN` starts no CI on main, so no deploy follows. The merge uses the security lane's GitHub App secrets.
5. **After the merge:** ex-tales-forge lanes are unchanged: `playtest.yml` deploys playtest, and production still needs a founder's Approve (normal lane) unless the merge is admin-only or security. In **workflow, every merge to main deploys production** ([`deploy.yml`](https://github.com/whyse-ab/workflow/blob/main/.github/workflows/deploy.yml)). That is why its auto class starts with docs-only and health-history only.
6. **workflow** gets a copy of the classifier script and the merge job. It has no `DeployLanes` module or security lane today.

**Rollback** is one step: revert the squash commit with `gh pr revert` or `git revert`. A revert of an auto PR falls in the same class and merges itself. Nothing that touches data can be auto, so a revert never needs a data undo.

## Replay in CI (proof, not a claim)

Today the golden replay runs by hand: a patch, test files outside the repo, dumps compared on a dev box. A claim in a PR body is not proof. The [planned replay upgrade](plan-tf-refactor-2026-10-17.md) turns it into test-only files in the repo. After that, a `Replay` CI job on refactor-shaped PRs does this:

1. Checks out the base sha and the head sha.
2. Runs the same replay on each, with seeded dice and stubbed LLM, intent and Jev.
3. Writes canonical dumps (`:erlang.term_to_binary(term, [:deterministic])`) and compares their sha256.
4. Posts `Replay: identical <sha256>`, or fails with the first diff.

The auto lane requires that check to be `success` on the head sha. Until it runs in CI, refactors are needs-founder.

## Settings Fredrik must click

Read-only check on 2026-10-18 (`gh api`): `main` in both repos requires the checks Test and Dialyzer. There are no repo rulesets. ex-tales-forge requires no review; workflow requires reviews with 0 approvals. "Allow auto-merge" is off in both. The org rulesets could not be read (that needs the `admin:org` scope).

1. **Both repos:** create a GitHub App (Contents and Pull requests: read and write) and install it on both repos. Add the secrets `SECURITY_BOT_APP_ID` and `SECURITY_BOT_APP_PRIVATE_KEY`. They are missing today, so the security lane cannot merge yet either.
2. **No bypass and no ruleset change is needed** while `main` requires no approving review. If Fredrik later turns on "Require approvals", the App needs a bypass in that ruleset.
3. **Leave "Allow auto-merge" off.** Native auto-merge is not used (step 3).
