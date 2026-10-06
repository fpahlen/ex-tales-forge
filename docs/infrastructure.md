---
title: Infrastructure assets
updated: 2026-10-06
---

# Infrastructure assets

Everything Tales Forge runs on, in one place. "Login held by" says who can get in today, not who is responsible for anything. Never write secret values here; only say where they are stored.

## Now

| Asset | What it's for | Status | Cost | Login held by | Secret stored in |
|---|---|---|---|---|---|
| Domain `tales-forge.ai` | Game and admin addresses | Exists | Yearly renewal (check registrar) | Fredrik | Shared vault (todo) |
| GitHub organization `whyse-ab` | Holds `ex-tales-forge`, `tales-forge-docs`, `text-forge`; founders in one team | Created as `whyse-ab` (Team plan); ex-tales-forge and tales-forge-docs moved 2026-10-06, text-forge still under `fpahlen` | Team plan (branch protection included) | Fredrik | — |
| Fly.io account and app `tales-forge` | Hosts the game and its admin, region `arn` (Stockholm) | Live at tales-forge.fly.dev (org personal, account fredrik@whyse.se); deployed from PR #15 branch | ~$6–7/month (shared-cpu-1x, 1 GB, always on; auto-stop caused failed cold starts) | Fredrik | Shared vault (todo) |
| Postgres on Fly | Sessions, decisions, comments | Self-run Fly Postgres `tales-forge-db` (arn), attached | ~$6/month (shared-cpu-1x, 1 GB; 256 MB stalled under load. Unsupported; managed ~$38/month later if needed) | Fredrik | Fly secret `DATABASE_URL` |
| Resend | Sends sign-in links now, player mail later | Not created | Free at current volume | — | Fly secret `RESEND_API_KEY` |
| xAI API keys | AI game master | Production key live; separate playtest key live on `tales-forge-playtest` | Usage-based; the main per-session cost | Fredrik | Fly secret `XAI_API_KEY` (one per app) |
| Table `ai_calls` (each app's Postgres) | AI cost per LLM call: tokens, model, cost (micro-USD), latency, status, linked to game session and turn; feeds the playtest spending caps | In review ([ex-tales-forge PR #19](https://github.com/whyse-ab/ex-tales-forge/pull/19)); created by the release migration on deploy | Free (existing Postgres) | — | — (no new secret; cost read from `XAI_API_KEY` responses) |
| GitHub docs token | Lets the admin import from `tales-forge-docs` and check `whyse-ab/tales-forge` team membership | Live (fine-grained, contents read + Members read) | Free | Fredrik | Fly secret `GITHUB_DOCS_TOKEN` |
| GitHub OAuth app *Tales Forge Admin* | "Sign in with GitHub" on the admin (email links stay as fallback) | Live since v13 (2026-10-06), registered under `whyse-ab` | Free | Fredrik | Fly secrets `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET` |
| GitHub Actions CI and prod deploy | Tests every PR; deploys `main` to `tales-forge` after the tests pass ([environments](environments.md)). `main` is protected: required check `Test` | Live (`.github/workflows/ci.yml`, merged in PR #16) | Free (public repo) | Fredrik | Actions secret `FLY_API_TOKEN` (deploy token for `tales-forge`, set) |
| Fly app `tales-forge-playtest` | Long-lived playtest for persona bots and, later, invited testers; tracks `main` (deployed right after prod by `.github/workflows/playtest.yml`, ex-tales-forge PR #17) | Live at [tales-forge-playtest.fly.dev](https://tales-forge-playtest.fly.dev) since 2026-10-06: arn, shared-cpu-1x 512 MB plus 512 MB swap, 1 machine (`801e9ef6136178`) always on | ~$3.84/month | Fredrik | Fly secrets on `tales-forge-playtest` (`DATABASE_URL`, `SECRET_KEY_BASE`, `ADMIN_EMAILS`, `ADMIN_GITHUB_TEAM`, `XAI_API_KEY`, `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET`, `GITHUB_DOCS_TOKEN`); Actions secret `FLY_API_TOKEN_PLAYTEST` (set) |
| Postgres `tales-forge-playtest-db` | Playtest database; later also holds one database per PR preview | Live: self-run Fly Postgres (postgres-flex 18.1, same type as prod), arn, single node, shared-cpu-1x 512 MB, 1 GB volume, machine `d8d1116b5d1918`, always on, attached to `tales-forge-playtest` | ~$3.99/month ($3.84 machine plus $0.15 volume) | Fredrik | Fly secret `DATABASE_URL` on `tales-forge-playtest`; superuser password not stored |
| Fly PR preview apps `tales-forge-pr-<n>` | One throwaway app per open PR, with its own database on `tales-forge-playtest-db`, no AI key, destroyed on close | Decided, not built | ~$1.50/month est. | — | Generated per app; Actions secret for a Fly app-creating token (not created) |
| Google Drive folder | Shared docs and persona form until migrated here | Exists ([folder](https://drive.google.com/drive/folders/1tlNoL8WZJPgbFQVT4SipKi9odGnQM_PB)) | Free | Fredrik | — |
| Shared password vault | Logins and secrets not stuck in one head | Not chosen | Depends on tool | — | — |

## Later

| Asset | What it's for | When |
|---|---|---|
| Self-play bots on playtest | Measure bot cost per session apart from real players, using the playtest app's own `XAI_API_KEY` (key exists) | When self-play starts (November) |
| Error and uptime monitoring (e.g. Sentry free tier plus an uptime check) | Know when the game breaks | Before outside players arrive |
| Stripe | Module purchases and prepaid credits | Before the first paying customer |

## To retire

| Asset | Why | When |
|---|---|---|
| Netlify site for tales-forge.ai | Old React app | When the Elixir rewrite replaces it |
| Supabase project | Old app's database and auth | Same time, after any data worth keeping is exported |

## GitHub sign-in for the admin

The admin login page offers "Sign in with GitHub" once both OAuth secrets are set; email magic links keep working either way.

OAuth app settings (GitHub → Settings → Developer settings → OAuth Apps → New OAuth App):

| Setting | Value |
|---|---|
| Application name | Tales Forge Admin |
| Homepage URL | https://tales-forge.fly.dev |
| Authorization callback URL | https://tales-forge.fly.dev/admin/auth/github/callback |
| Device flow | Off |
| Scopes | `read:org user:email` (requested by the app at sign-in; nothing to tick on the OAuth app) |

Who gets in: anyone whose *verified* GitHub email is in `ADMIN_EMAILS`, plus, only if `ADMIN_GITHUB_TEAM` is set, active members of that team (pending invites don't count). Removing someone from `ADMIN_EMAILS` or the team, or unsetting `ADMIN_GITHUB_TEAM`, ends their access within about 5 minutes; nobody's GitHub token is stored.

Secrets: `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET`, optional `ADMIN_GITHUB_TEAM`. Team access also needs `GITHUB_DOCS_TOKEN` to read `whyse-ab` members (fine-grained token: organization permission *Members: read*; classic token: `read:org`).

## Fly secrets checklist

`DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `ADMIN_EMAILS`, `ADMIN_MAIL_FROM`, `MAIL_ADAPTER`, `RESEND_API_KEY` (or `POSTMARK_API_KEY`), `GITHUB_DOCS_TOKEN`, `XAI_API_KEY`; optional `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET`, `ADMIN_GITHUB_TEAM`. Steps are in `docs/DEPLOY-FLY.md` in ex-tales-forge.

Playtest (`tales-forge-playtest`) only needs `DATABASE_URL` and `SECRET_KEY_BASE` to boot. It has `ADMIN_EMAILS`, `ADMIN_GITHUB_TEAM`, its own `XAI_API_KEY`, and GitHub sign-in (second OAuth app plus `GITHUB_DOCS_TOKEN`) too; `PHX_HOST` is in `fly.playtest.toml`. Per-secret status: [environments](environments.md#secrets-per-environment-names-only) and [fly-secrets](fly-secrets.md#playtest-tales-forge-playtest).
