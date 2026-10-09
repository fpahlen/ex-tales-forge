---
title: Environments and how changes reach production
updated: 2026-10-08
---

# Environments and how changes reach production

Status 2026-10-06: **production** and **playtest** are live. Production deploys automatically from `main` through GitHub Actions. PR previews are decided but not built yet.

## Branches

- `main` is what runs in production. Nobody pushes to it directly; everything goes in through a pull request. `main` is protected: the required CI checks **`Test`** and **`Dialyzer`** must both pass before anything lands on it.
- Each change gets a short-lived branch (`feature/...`, `fix/...`), a PR, and is deleted after merge.
- There is no long-lived `dev` or `staging` branch.

## The three environments

| | Production | Playtest | PR preview |
|---|---|---|---|
| Fly app | `tales-forge` | `tales-forge-playtest` ([tales-forge-playtest.fly.dev](https://tales-forge-playtest.fly.dev)) | `tales-forge-pr-<number>` (its own app) |
| App machine | shared-cpu-1x, 1 GB, 1 machine always on | shared-cpu-1x, 512 MB plus 512 MB swap, 1 machine always on | Small, created per PR |
| Database | `tales-forge-db` (own Fly Postgres) | `tales-forge-playtest-db`: own Fly Postgres (postgres-flex 18), single node, shared-cpu-1x 512 MB, 1 GB volume, always on | A database per PR **on the playtest cluster** `tales-forge-playtest-db`, dropped with the app |
| Runs | `main` | `main`, deployed automatically right after production (or by hand) | The PR's branch |
| Who uses it | Players, admins | Persona bots (self-play) and a few invited testers | Whoever reviews the PR |
| Admin data that lives only here | Founder surveys (`/admin/survey`, `/admin/surveys/*`) | Playtest runs (`/admin/playtest/*`) | Not built; its app name has no "playtest", so it would act as production (revisit when previews are built) |
| Lifetime | Always on | Long-lived, always on | Created when the PR opens, destroyed when it closes |
| AI key | Production `XAI_API_KEY` | Its own `XAI_API_KEY`, so bot cost is counted separately | None: mock narration |
| Status | Live | Live since 2026-10-06 | Decided, not built |

Region is `arn` (Stockholm) for all three. The `tales-forge.ai` domain stays on Netlify. No environment gets Fly certificates or DNS changes.

## How a change gets to production

1. Push a branch and open a PR. GitHub Actions runs the two required jobs: **`Test`** (compile with warnings as errors, format check, Credo strict, tests with coverage, the docs build and `mix hex.audit`) and **`Dialyzer`**.
2. Later (not built yet), a preview app also starts for the PR, with its link posted on the PR.
3. When the checks are green and the change is reviewed, merge to `main`.
4. On `main`, Actions (`.github/workflows/ci.yml`) runs the checks again and then deploys to `tales-forge`. Database migrations run first (`/app/bin/migrate`). Only one deploy runs at a time, and a running deploy is never cancelled. This is live.
5. Playtest then gets the same commit: `.github/workflows/playtest.yml` runs after every green CI run on `main` and deploys to `tales-forge-playtest`. It can also be started by hand (Actions → "Deploy to playtest"). It is a separate workflow, so a failed playtest deploy never fails or blocks production. (Workflow in ex-tales-forge PR #17; it needs the Actions secret `FLY_API_TOKEN_PLAYTEST`.)

A manual `fly deploy` is the fallback when Actions is down. It is the same command CI runs; see `docs/DEPLOY-FLY.md` in ex-tales-forge. For playtest: `fly deploy --remote-only --depot=false -c fly.playtest.toml -a tales-forge-playtest --ha=false`.

## What needs Fredrik's OK

- Merging anything to `main`, because a merge deploys to production.
- Creating or deleting Fly apps, databases, volumes, deploy tokens and GitHub secrets.
- Anything that adds cost, such as a bigger machine, an always-on playtest, or Managed Postgres.
- Inviting playtesters and giving out admin access (`ADMIN_EMAILS`, `ADMIN_GITHUB_TEAM`).

## Invited testers (later)

The founders are the first testers: they sign in to playtest with GitHub through the `whyse-ab/tales-forge` team, like production. Since ex-tales-forge PR #54 ([decision 2026-10-07](decisions.md#2026-10-07-github-team-sign-in-is-the-only-login-on-production-and-playtest)) that is the only login on both apps, and every page needs it. Email sign-in is gone. Outside testers will need a new decision (team membership or another login).
- A new AI key, or raising the spending cap on one.

## Costs (estimates, 2026-10-06)

Fly list prices for `arn` per 30 days: shared-cpu-1x is $2.28 with 256 MB, $3.84 with 512 MB and $6.95 with 1 GB. Volumes cost $0.15/GB-month, and a stopped machine costs only $0.15/GB-month of its disk image, which is a few cents for our apps. These are Fly's prices for the machines; AI usage is billed separately by xAI.

| Environment | Setup | Estimate per month |
|---|---|---|
| Production (today) | App 1 GB always on; DB 1 GB always on plus a 1 GB volume | ~$14 |
| Playtest app (live) | `tales-forge-playtest`: shared-cpu-1x 512 MB, 1 machine always on (swap is free) | ~$3.84 |
| Playtest DB (live) | `tales-forge-playtest-db`: shared-cpu-1x 512 MB always on ($3.84) plus a 1 GB volume ($0.15) | ~$3.99 |
| PR previews (not built) | About 4 PRs a month, 3 days each: own small app plus a database on the playtest cluster | ~$1.50 |
| **New cost in total** | Playtest ~$7.83 plus previews | **~$8 now, ~$9.50 with previews** |

Total new cost stays under $15/month in every option. Sources: [Fly pricing](https://fly.io/docs/about/pricing/), [Fly billing](https://fly.io/docs/about/billing/).

The admin costs page (`/admin/costs`, ex-tales-forge PR #28) shows these fixed costs next to actual AI spend for both environments. Its figures come from one config block, `config :ex_tales_forge, TalesForge.Costs` in ex-tales-forge's `config/config.exs` (USD per month or SEK per year); update it when the numbers here change. Domain and other hosting figures (SEK/year, from Fredrik 2026-10-06) are also in that block.

Why always on: production runs always on because waking from sleep failed there. The 256 MB database stalled under load in production. Our Fly Postgres type is no longer maintained by Fly, and its sleep mode only kicks in once the app has stopped and closed its connections. So playtest's app and database never sleep either.

Memory: at 512 MB with no swap, the playtest app was killed for running out of memory during boot. With 512 MB of swap it boots in about 25 s and runs with roughly 165 MB swapped out. If it feels slow, moving to 1 GB adds about $3/month.

## Secrets per environment (names only)

Values live in Fly secrets or GitHub Actions secrets, never in the repos.

**Production** (Fly app `tales-forge`): `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `ADMIN_EMAILS`, `ADMIN_GITHUB_TEAM`, `GITHUB_DOCS_TOKEN`, `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET`, `XAI_API_KEY`; later `MAIL_ADAPTER`, `RESEND_API_KEY`, `ADMIN_MAIL_FROM`. See [fly-secrets.md](fly-secrets.md).
GitHub Actions secret: `FLY_API_TOKEN`, a deploy token that only works on `tales-forge` (set).

**Playtest** (Fly app `tales-forge-playtest`, live). All values are its own, never copied from production, except the read-only `GITHUB_DOCS_TOKEN`:

| Name | Status |
|---|---|
| `DATABASE_URL` | Set (by `fly postgres attach tales-forge-playtest-db`) |
| `SECRET_KEY_BASE` | Set (newly generated) |
| `ADMIN_EMAILS` | Set (fredrik@whyse.se); unused since PR #54 |
| `ADMIN_GITHUB_TEAM` | Set (`whyse-ab/tales-forge`): the founders sign in with GitHub, same check as production |
| `XAI_API_KEY` | Set, live: a separate playtest key |
| `PHX_HOST` | Not a secret here: `tales-forge-playtest.fly.dev` is in `fly.playtest.toml` |
| `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET` | Set, from a second OAuth app with the playtest callback |
| `GITHUB_DOCS_TOKEN` | Set, same read-only token as production; needed for the team check |
| `MAIL_ADAPTER`, `RESEND_API_KEY`, `ADMIN_MAIL_FROM` | Not set (production has none either). Not needed: sign-in is GitHub team only (PR #54) |

GitHub Actions secret: `FLY_API_TOKEN_PLAYTEST`, a deploy token for `tales-forge-playtest` only (set).

**PR previews** (decided, not built): each preview is its own Fly app with its own database on the playtest cluster `tales-forge-playtest-db`. App and database are destroyed when the PR closes. Secrets: `DATABASE_URL` (set when the database is attached), and `SECRET_KEY_BASE`, newly generated for each preview by the workflow and never stored anywhere else. `PHX_HOST` is the preview's own `.fly.dev` name. Optional: `ADMIN_EMAILS`. No AI key, so the game master gives mock narration, and no mail key.
GitHub Actions secret: a Fly token that can create and destroy apps, which is broader than a deploy token (see the open decisions).

## Decided (2026-10-06)

- Playtest keeps 1 machine always running, and so does its database (~$8/month in total).
- Previews get their own app and a per-PR database on the playtest cluster, with no AI key, destroyed when the PR closes.
- `main` is protected with the required check `Test` (`Dialyzer` has since been added as a second required check; see [Coding standards](coding-standards.md)). Production deploys automatically from `main` through Actions; playtest follows right after.

## Open decisions

- Whether previews live in a separate Fly organization so their app-creating token can't touch production.
- How outside testers sign in to playtest later (a separate tester list, plus a mail key). The founders already use the GitHub team.
