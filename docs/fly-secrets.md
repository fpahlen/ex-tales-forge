---
title: "Adding API keys and secrets to Fly"
updated: 2026-10-06
---

# Adding API keys and secrets to Fly

API keys, passwords and tokens go into **Fly secrets**, never into the code or `fly.toml`. Fly stores them encrypted and gives them to the app as environment variables. Setting or changing a secret restarts the app, which takes about 10 seconds.

App: `tales-forge`, org `personal`, account fredrik@whyse.se.

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

## Which secrets the app uses

| Name | What it's for | Set? (2026-10-06) |
|---|---|---|
| `DATABASE_URL` | Connection to the Postgres app `tales-forge-db` | Yes (set by `fly postgres attach`) |
| `SECRET_KEY_BASE` | Signs sessions and cookies. Rotating it logs everyone out | Yes |
| `PHX_HOST` | Public host name (`tales-forge.fly.dev`) | Yes |
| `ADMIN_EMAILS` | Comma-separated emails allowed into the admin | Yes, fredrik@whyse.se only |
| `GITHUB_DOCS_TOKEN` | Read-only GitHub token so the admin can import this docs repo | Yes |
| `XAI_API_KEY` | AI game master (xAI). Without it the GM gives mock narration | Yes (since 2026-10-06) |
| `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | Optional other AI providers | No |
| `MAIL_ADAPTER` | Email provider for magic links, e.g. `resend` | No, see [Resend setup](resend-setup.md) |
| `RESEND_API_KEY` | Resend sending key | No |
| `ADMIN_MAIL_FROM` | Sender address for login emails (default `admin@tales-forge.ai`) | No |

Mailgun and Postmark (`MAILGUN_API_KEY`, `MAILGUN_DOMAIN`, `POSTMARK_API_KEY`) are also supported by the code but not used.

## Good habits

- Use a separate key per environment (local `.env` vs Fly) and per provider account, so one can be revoked without breaking the other.
- Give keys the smallest permissions that work (e.g. sending-only for Resend, read-only contents for GitHub).
- When someone leaves or a key may have leaked: create a new key at the provider, `fly secrets set` it, then revoke the old one.
- Record new secret names (never values) in this table and in [infrastructure.md](infrastructure.md).
