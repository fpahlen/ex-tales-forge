---
title: Setting up Resend (email)
updated: 2026-10-06
---

# Setting up Resend (email)

Not in use: admin sign-in links were removed on 2026-10-07 (ex-tales-forge PR #54, [decision](decisions.md#2026-10-07-github-team-sign-in-is-the-only-login-on-production-and-playtest)); sign-in is GitHub team only. Resend is kept for player mail later. The free plan is enough at our volume. Never put the API key in this repo or in chat.

## 1. Create the account

1. Sign up at [resend.com](https://resend.com) with a company address (e.g. fredrik@whyse.se), not a personal GitHub login.
2. Confirm the email Resend sends you.

## 2. Add and verify the domain

1. In Resend, open **Domains** and add `tales-forge.ai`. Pick an EU region if offered.
2. Resend shows a few DNS records (for sender verification and deliverability). Add them exactly as shown at the DNS provider for `tales-forge.ai`.
3. Back in Resend, click verify. DNS can take from minutes to a few hours to show up.

Until the domain is verified, Resend can only send to the account owner's own address, which is fine for a first test.

## 3. Create an API key

1. Open **API Keys** and create a key named e.g. `tales-forge-fly`, with **sending access** only.
2. Copy it once (Resend shows it only when created) and hand it over through Case's secure secret box, never in chat or in a file here.

## 4. Wire it into Fly

Case sets these as Fly secrets on the `tales-forge` app:

| Secret | Value |
|---|---|
| `MAIL_ADAPTER` | `resend` |
| `RESEND_API_KEY` | the key from step 3 |
| `ADMIN_MAIL_FROM` | a sender on the verified domain, e.g. `admin@tales-forge.ai` |

Then redeploy, request a sign-in link at `/admin`, and check it arrives.

## Who holds it

See [infrastructure.md](infrastructure.md) for who holds the login and where the key is stored.
