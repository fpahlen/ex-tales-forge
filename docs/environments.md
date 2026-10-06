---
title: Environments and how changes reach production
updated: 2026-10-06
---

# Environments and how changes reach production

This is the approved plan. **Only production exists today.** Playtest and PR previews are planned and not created yet. Automatic deploys are waiting on the `ci-deploy` branch in ex-tales-forge being merged and on a deploy token.

## Branches

- `main` is what runs in production. Nobody pushes to it directly; everything goes in through a pull request.
- Each change gets a short-lived branch (`feature/...`, `fix/...`), a PR, and is deleted after merge.
- There is no long-lived `dev` or `staging` branch.

## The three environments

| | Production | Playtest | PR preview |
|---|---|---|---|
| Fly app | `tales-forge` | `tales-forge-playtest` | `tales-forge-pr-<number>` |
| Database | `tales-forge-db` (own Fly Postgres) | Own small Fly Postgres in `arn` | Small throwaway database, deleted with the app |
| Runs | `main` | `main`, after production (or a manual promote) | The PR's branch |
| Who uses it | Players, admins | Persona bots (self-play) and a few invited testers | Whoever reviews the PR |
| Lifetime | Always on | Long-lived; can sleep when idle | Created when the PR opens, destroyed when it closes |
| AI key | Production `XAI_API_KEY` | Its own `XAI_API_KEY`, so bot cost is counted separately | None (mock narration), or a capped key |
| Status | Live | Planned, not created | Planned, not created |

Region is `arn` (Stockholm) for all three. The `tales-forge.ai` domain stays on Netlify. No environment gets Fly certificates or DNS changes.

## How a change gets to production

1. Push a branch and open a PR. GitHub Actions runs the checks: compile with warnings as errors, format check, Credo, tests, and `mix hex.audit`.
2. Later, a preview app also starts for the PR, with its link posted on the PR.
3. When the checks are green and the change is reviewed, merge to `main`.
4. On `main`, Actions runs the checks again and then deploys to `tales-forge`. Database migrations run first (`/app/bin/migrate`). Only one deploy runs at a time, and a running deploy is never cancelled.
5. Playtest then gets the same build, either automatically after production or with a manual "promote".

A manual `fly deploy` is the fallback when Actions is down. It is the same command CI runs; see `docs/DEPLOY-FLY.md` in ex-tales-forge.

## What needs Fredrik's OK

- Merging anything to `main`, because a merge deploys to production.
- Creating or deleting Fly apps, databases, volumes, deploy tokens and GitHub secrets.
- Anything that adds cost, such as a bigger machine, an always-on playtest, or Managed Postgres.
- Inviting playtesters and giving out admin access (`ADMIN_EMAILS`, `ADMIN_GITHUB_TEAM`).
- A new AI key, or raising the spending cap on one.

## Costs (estimates, 2026-10-06)

Fly list prices for `arn` per 30 days: shared-cpu-1x is $2.28 with 256 MB, $3.84 with 512 MB and $6.95 with 1 GB. Volumes cost $0.15/GB-month, and a stopped machine costs only $0.15/GB-month of its disk image, which is a few cents for our apps. These are Fly's prices for the machines; AI usage is billed separately by xAI.

| Environment | Setup | Estimate per month |
|---|---|---|
| Production (today) | App 1 GB always on; DB 1 GB always on plus a 1 GB volume | ~$14 |
| Playtest app | 512 MB, always 1 running / sleeps when idle | $3.84 / ~$0.50–2 |
| Playtest DB | 256 MB plus a 1 GB volume, always on / sleeps after 1 h idle | $2.43 / ~$0.50–1.50 |
| PR previews | About 4 PRs a month, 3 days each: app plus its own tiny DB / app plus a database on the playtest Postgres | ~$2.50 / ~$1.50 |
| **New cost in total** | Cheapest to most expensive | **~$3 to ~$9** (~$10.50 if the playtest DB needs 512 MB) |

Total new cost stays under $15/month in every option. Sources: [Fly pricing](https://fly.io/docs/about/pricing/), [Fly billing](https://fly.io/docs/about/billing/).

Sleeping (autostop) caveats: production runs always on because waking from sleep failed there. The 256 MB database stalled under load in production. Our Fly Postgres type is no longer maintained by Fly, and its sleep mode only kicks in once the app has stopped and closed its connections.

## Secrets per environment (names only)

Values live in Fly secrets or GitHub Actions secrets, never in the repos.

**Production** (Fly app `tales-forge`): `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `ADMIN_EMAILS`, `ADMIN_GITHUB_TEAM`, `GITHUB_DOCS_TOKEN`, `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET`, `XAI_API_KEY`; later `MAIL_ADAPTER`, `RESEND_API_KEY`, `ADMIN_MAIL_FROM`. See [fly-secrets.md](fly-secrets.md).
GitHub Actions secret: `FLY_API_TOKEN`, a deploy token that only works on `tales-forge` (not created yet).

**Playtest** (Fly app `tales-forge-playtest`, planned): `DATABASE_URL`, its own `SECRET_KEY_BASE`, `PHX_HOST` (`tales-forge-playtest.fly.dev`), its own `XAI_API_KEY`, its own `ADMIN_EMAILS` and `ADMIN_GITHUB_TEAM`, and `GITHUB_DOCS_TOKEN`. "Sign in with GitHub" there needs a second OAuth app with its own `GITHUB_OAUTH_CLIENT_ID` and `GITHUB_OAUTH_CLIENT_SECRET`, because an OAuth app only accepts its own callback address. Mail secrets are only needed if testers sign in by email.
GitHub Actions secret: `FLY_API_TOKEN_PLAYTEST`, a deploy token for `tales-forge-playtest` only.

**PR previews** (planned): `DATABASE_URL` (set when the database is attached), and `SECRET_KEY_BASE`, newly generated for each preview by the workflow and never stored anywhere else. `PHX_HOST` is the preview's own `.fly.dev` name. Optional: `ADMIN_EMAILS`. No AI key by default, so the game master gives mock narration, and no mail key.
GitHub Actions secret: a Fly token that can create and destroy apps, which is broader than a deploy token (see the open decisions).

## Open decisions

- Who creates the Fly deploy token(s) and adds them as GitHub Actions secrets.
- Whether playtest keeps 1 machine always running (~$4) or sleeps when idle (~$1, slower first visit, and self-play has to run through the web, not only as background jobs).
- Previews: their own tiny database or a database on the playtest Postgres, and whether previews live in a separate Fly organization so their token can't touch production.
