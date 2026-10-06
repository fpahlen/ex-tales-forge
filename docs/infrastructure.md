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
| xAI API key | AI game master | Exists | Usage-based; the main per-session cost | Fredrik | Fly secret `XAI_API_KEY` |
| GitHub docs token | Lets the admin import from `tales-forge-docs` | Not created | Free | Fredrik | Fly secret `GITHUB_DOCS_TOKEN` |
| GitHub OAuth app *Tales Forge Admin* | "Sign in with GitHub" on the admin (email links stay as fallback) | Live since v13 (2026-10-06), registered under `whyse-ab` | Free | Fredrik | Fly secrets `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET` |
| Google Drive folder | Shared docs and persona form until migrated here | Exists ([folder](https://drive.google.com/drive/folders/1tlNoL8WZJPgbFQVT4SipKi9odGnQM_PB)) | Free | Fredrik | — |
| Shared password vault | Logins and secrets not stuck in one head | Not chosen | Depends on tool | — | — |

## Later

| Asset | What it's for | When |
|---|---|---|
| Separate API keys for self-play bots | Measure bot cost per session apart from real players | When self-play starts (November) |
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
