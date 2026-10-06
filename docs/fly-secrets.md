---
title: "Adding API keys and secrets to Fly"
updated: 2026-10-06
---

# Adding API keys and secrets to Fly

API keys, passwords and tokens go into **Fly secrets**, never into the code or `fly.toml`. Fly stores them encrypted and gives them to the app as environment variables. Setting or changing a secret restarts the app, which takes about 10 seconds.

Apps: `tales-forge` (production) and `tales-forge-playtest` (playtest), org `personal`, account fredrik@whyse.se. Each app has its own secrets; never copy a value from one to the other. The tables below cover production first, then [playtest](#playtest-tales-forge-playtest).

## Option 1: the Fly dashboard (easiest)

1. Sign in at [fly.io](https://fly.io/dashboard) as fredrik@whyse.se.
2. Open the app **tales-forge** and go to **Secrets** ([direct link](https://fly.io/apps/tales-forge/secrets)).
3. Add a secret with the name from the table below and paste the value.
4. Deploy the secret. The app restarts with the new value.

## Option 2: the command line

On your own computer, with [flyctl installed](https://fly.io/docs/flyctl/install/):

```sh
fly auth login                                   # once, opens the browser
fly secrets set XAI_API_KEY=xai-... -a tales-forge
fly secrets list -a tales-forge                  # shows names only, never values
fly secrets unset SOME_NAME -a tales-forge       # remove one
```

Tip: put a space before the command so it doesn't end up in your shell history (works in most shells), or use `fly secrets import -a tales-forge` and paste `NAME=value` lines, then press Ctrl-D.

## Option 3: ask a bot

Ask Case or Bobby to add a key. You get a masked input box in the chat, so the value never appears in the conversation, and the bot sets it on Fly for you.

## Which secrets the app uses (production, `tales-forge`)

| Name | What it's for | Set? (2026-10-06) |
|---|---|---|
| `DATABASE_URL` | Connection to the Postgres app `tales-forge-db` | Yes (set by `fly postgres attach`) |
| `SECRET_KEY_BASE` | Signs sessions and cookies. Rotating it logs everyone out | Yes |
| `PHX_HOST` | Public host name (`tales-forge.fly.dev`) | Yes |
| `ADMIN_EMAILS` | Comma-separated emails allowed into the admin | Yes, fredrik@whyse.se only |
| `GITHUB_DOCS_TOKEN` | Fine-grained GitHub token (owner `whyse-ab`): read-only contents so the admin can import this docs repo, plus organization *Members: read* for the admin team check | Yes |
| `XAI_API_KEY` | AI game master (xAI). Without it the GM gives mock narration | Yes (since 2026-10-06) |
| `GITHUB_OAUTH_CLIENT_ID` | "Sign in with GitHub" on the admin: Client ID of the GitHub OAuth app *Tales Forge Admin* (see [infrastructure.md](infrastructure.md#github-sign-in-for-the-admin)). Without it and the secret, only email links work | Yes (live since v13, 2026-10-06) |
| `GITHUB_OAUTH_CLIENT_SECRET` | Client secret of the same OAuth app | Yes (live since v13, 2026-10-06) |
| `ADMIN_GITHUB_TEAM` | Optional. A GitHub team as `org/team-slug`, e.g. `whyse-ab/tales-forge`; its active members can sign in to the admin with GitHub. Unset = team access off (only `ADMIN_EMAILS` counts). Needs `GITHUB_DOCS_TOKEN` to be able to read `whyse-ab` members | Yes: `whyse-ab/tales-forge` (since v15, 2026-10-06) |
| `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | Optional other AI providers | No |
| `AI_CAP_SESSION_USD`, `AI_CAP_DAY_USD` | Optional AI spending caps in USD, per game session and per day (since midnight Stockholm time). Not set = that cap is off. Not secret, but set the same way (ex-tales-forge PR #20) | No, not set = off |
| `PLAYTEST_RUNNER_ENABLED` | Turns on the persona bot runner (ex-tales-forge PR #23) when set to `true`. Not secret, but set the same way | **Never** set in production |
| `MAIL_ADAPTER` | Email provider for magic links, e.g. `resend` | No, see [Resend setup](resend-setup.md) |
| `RESEND_API_KEY` | Resend sending key | No |
| `ADMIN_MAIL_FROM` | Sender address for login emails (default `admin@tales-forge.ai`) | No |

Mailgun and Postmark (`MAILGUN_API_KEY`, `MAILGUN_DOMAIN`, `POSTMARK_API_KEY`) are also supported by the code but not used.

## Playtest (`tales-forge-playtest`)

Same names as production, with **separate values** (never copied from prod), except `GITHUB_DOCS_TOKEN`, which is the same read-only whyse-ab token. [Dashboard](https://fly.io/apps/tales-forge-playtest/secrets); on the command line use `-a tales-forge-playtest`.

| Name | Set? (2026-10-06) |
|---|---|
| `DATABASE_URL` | Yes, set by `fly postgres attach tales-forge-playtest-db` (database `tales_forge_playtest` on the playtest cluster) |
| `SECRET_KEY_BASE` | Yes, newly generated for playtest |
| `ADMIN_EMAILS` | Yes, fredrik@whyse.se only. Invited testers come later, here or through a separate tester list |
| `ADMIN_GITHUB_TEAM` | Yes, `whyse-ab/tales-forge`. Active team members (the founders) can sign in with GitHub; pending invites don't count |
| `XAI_API_KEY` | Yes, live: a separate playtest key (added by Case), so bot and tester cost is counted apart from production |
| `PHX_HOST` | Not a secret: `tales-forge-playtest.fly.dev` is in `fly.playtest.toml` |
| `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET` | Yes, from a second OAuth app for playtest (callback `https://tales-forge-playtest.fly.dev/admin/auth/github/callback`) |
| `GITHUB_DOCS_TOKEN` | Yes, the same fine-grained whyse-ab token as production (contents read, Members read). Used for the team check and "Sync from repo" |
| `MAIL_ADAPTER`, `RESEND_API_KEY`, `ADMIN_MAIL_FROM` | No, so magic-link emails aren't sent on playtest |
| `AI_CAP_SESSION_USD`, `AI_CAP_DAY_USD` | Yes, since 2026-10-06: $1.00 per session, $10.00 per day. Changing them needs Fredrik's OK |
| `PLAYTEST_RUNNER_ENABLED` | Not yet. Set to `true` after ex-tales-forge PR #23 is merged and deployed, so persona bot runs can be started here |

GitHub Actions secret for deploying playtest: `FLY_API_TOKEN_PLAYTEST`, a deploy token for `tales-forge-playtest` only (Fly dashboard → tales-forge-playtest → Tokens, or `fly tokens create deploy -a tales-forge-playtest`). Set.

## Good habits

- Use a separate key per environment (local `.env` vs Fly) and per provider account, so one can be revoked without breaking the other.
- Give keys the smallest permissions that work (e.g. sending-only for Resend, read-only contents for GitHub).
- When someone leaves or a key may have leaked: create a new key at the provider, `fly secrets set` it, then revoke the old one.
- Record new secret names (never values) in this table and in [infrastructure.md](infrastructure.md).
