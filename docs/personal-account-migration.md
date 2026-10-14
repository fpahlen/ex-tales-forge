# Personal account migration – Whyse AB / Tales Forge

Date: 2026-10-14. Author: Grok Bot (read-only check of the box, Fly, GitHub and code).
Secret values are not in this document. Names only.

## 1. Goal and target structure

Goal: no part of Tales Forge or Workflow depends on Fredrik's personal accounts.

Target:
- **GitHub:** the org `whyse-ab` owns all repos. At least two founders are org owners. Bots use one GitHub App, `whyse-bots` (or one App per bot). No personal access tokens (PATs) in bots or CI.
- **Fly.io:** one org, `whyse`, owned by the company. Founders are members. All apps and databases are in this org. Deploy tokens are org- or app-scoped, not personal.
- **Email:** company aliases such as `ops@whyse.se`, `billing@whyse.se`, `bots@whyse.se`. Vendor accounts use these addresses.
- **Billing:** a company card. No more private card (Mastercard 1532) and no more utlägg.
- **Secrets:** one company vault (1Password or Infisical, see secrets card 1bdb4642). Every secret has an owner role, not a person.
- **People:** personal accounts are only members, with 2FA. They never own tokens, apps or billing.

## 2. Inventory

Status: **V** = Verified on 2026-10-14. **A** = Assumed (not checked).
Risk: what happens if Fredrik's account is lost, locked or he leaves.

| # | Service | What uses Fredrik's personal account | How | Risk | Target | Effort | Order | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | GitHub org `whyse-ab` | `fpahlen` is the only org owner. Other 4 founders (`Hawkan-Fredriksson`, `jpa71`, `maxpahlen`, `tsjokvist`) are members with **read** on all 3 repos. | Owner / admin | High. One person can lock out the company. | 2+ owners. Founders get write or maintain. | S | 1 | V |
| 2 | GitHub on the box (Grok Bot, Case, Bobby, Gentry) | `gh` logs in as `fpahlen`. Git uses `gh auth git-credential`. Scopes: gist, read:org, repo, workflow. | Personal OAuth token in `/home/box/.config/gh/hosts.yml` | High. Bots act as Fredrik. He gets all their GitHub mail. Token has wide rights. | GitHub App `whyse-bots` with installation tokens, repo-scoped. | M | 4 | V |
| 3 | GitHub Actions in `ex-tales-forge` | Runs show `fpahlen` as actor (pushes come from his token). Repo secrets: `FLY_API_TOKEN`, `FLY_API_TOKEN_PLAYTEST`. Workflows also use `SECURITY_BOT_TOKEN`, `SECURITY_BOT_APP_ID`, `SECURITY_BOT_APP_PRIVATE_KEY`, `SECURITY_LANE_WEBHOOK_URL`, `SECURITY_LANE_WEBHOOK_KEY` (not on the repo; maybe org-level or missing). | Fly tokens made by Fredrik's Fly user (A). Actor = PAT owner. | Medium. If Fredrik's Fly user goes, deploys stop. | Fly deploy tokens from org `whyse`. Security lane uses the App. | S | 3 | V (secrets) / A (token owner) |
| 4 | GitHub App `tales-forge-idea-board` | Installed on `whyse-ab`. Owner of the App registration not checked. Used via Fly secrets `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY`. | App owner (A: Fredrik's personal account) | Medium. App owned by a person goes with the person. | Transfer App ownership to `whyse-ab`, or reuse as `whyse-bots`. | S | 2 | V (installed) / A (owner) |
| 5 | GitHub OAuth login (admin/team login) | Fly secrets `GITHUB_OAUTH_CLIENT_ID`, `GITHUB_OAUTH_CLIENT_SECRET`, `ADMIN_GITHUB_TEAM`. | OAuth App registration owner (A: `fpahlen`) | Medium. Login breaks for all if the app is removed. | OAuth App owned by `whyse-ab`. | S | 2 | A |
| 6 | GitHub tokens in app | Fly secrets `GITHUB_DOCS_TOKEN`, `GITHUB_FEED_TOKEN`. | PAT (A: Fredrik's) | Medium. | App installation token. | S | 5 | A |
| 7 | GitHub webhooks | `ex-tales-forge` hooks to `tales-forge.fly.dev/webhooks/github` and `tales-forge-playtest.fly.dev/webhooks/github`, secret `GITHUB_WEBHOOK_SECRET`. | Repo setting (not personal) | Low. | Keep. Move secret to vault. | S | 7 | V |
| 8 | Fly.io org | All apps are in org `personal` ("Fredrik Pahlen", type PERSONAL): `tales-forge`, `tales-forge-db`, `tales-forge-playtest`, `tales-forge-playtest-db`, `fly-builder-crimson-raindrop-2162`. Releases show `fredrik@whyse.se`. | Owner + billing (A: private card) | High. Company production runs in a private account. | Org `whyse`, company card, founders as members. | M | 6 | V |
| 9 | Fly on the box | `flyctl` uses a Fly token (`…@tokens.fly.io`) with access to the `personal` org. | Token from Fredrik's Fly user (A) | Medium. | Org-scoped token from `whyse`, in vault. | S | 6 | V |
| 10 | Fly app `whyse-workflow` | Not visible to the box token ("app not found"). It is in another org or another account. | Unknown | Unknown | Same `whyse` org. | S | 6 | V (not found) |
| 11 | Postgres (Fly) | `tales-forge-db`, `tales-forge-playtest-db` (1 GB volume, arn, encrypted) in org `personal`. Oban runs in this database (A). | Owner | High. Data lives in a private org. | Move with the apps to `whyse` (Fly app move, or new DB + dump/restore). | M | 6 | V |
| 12 | xAI API (LLM) | `XAI_API_KEY` on both apps. | Key owner (A: Fredrik's xAI account, private card) | Medium. Cost and key go with the person. | xAI team/company account, `billing@`, company card. | S | 8 | A |
| 13 | Typesafe / Intent APIs | `TYPESAFE_API_KEY`, `TYPESAFE_INTENT_API_KEY`, `INTENT_JEV`. | API key owner (A) | Medium. | Company account. | S | 8 | A |
| 14 | Email sending | Code supports `MAIL_ADAPTER`, `MAIL_API_KEY`, `MAILGUN_*`, `POSTMARK_API_KEY`, `RESEND_API_KEY`. None of these are set as Fly secrets. Prod mail is probably not on. | — | Low now. | When turned on: provider account on `ops@`, company domain. | S | later | V |
| 15 | Costs / product app peers | `COSTS_PEER_TOKEN`, `COSTS_PEER_URL`, `PRODUCT_APP_API_TOKEN`, `PRODUCT_APP_PERSONA_SCORES_URL`, `WORKFLOW_API_TOKEN` (code). | Shared app tokens (not personal) | Low. | Vault. | S | 7 | V |
| 16 | Admin access in app | `ADMIN_EMAILS` Fly secret (values not read). No hardcoded personal emails found in `config/` or `.github/` (only comments "Fredrik's OK", test fixtures with `fpahlen`). | Env list | Low. | Use `ADMIN_GITHUB_TEAM` only, or a company alias. | S | 7 | V |
| 17 | Bot token files on box | `/home/box/.config/tales-forge/`: `board-bot-token`, `case-board-token`, `gentry-qa-token`, `github-webhook-secret`, `product-app-api-token`. Also `/home/box/.config/basecamp/credentials.json`. | Files on box, which runs under Fredrik's Grok Bot account | Medium. | Vault; box reads from vault. | S | 7 | V |
| 18 | Grok Bot itself | The box, bots and connectors run under Fredrik's Grok Bot account. | Login + billing | High. All bots stop if his account stops. | Company Grok Bot account (if possible), `bots@` login, company card. | M | 9 | V (stated) |
| 19 | Google Drive / Calendar | Connectors use `fredrik.pahlen@gmail.com`. | Personal Google login | Medium. Company files in a private Drive. | Google Workspace on `whyse.se`, shared drive. | M | 9 | V (connector names) |
| 20 | Web push | `WEB_PUSH_VAPID_PRIVATE_KEY`, `WEB_PUSH_VAPID_PUBLIC_KEY`. | Self-made keys (not personal) | Low. | Vault. Do not rotate (breaks subscriptions). | S | 7 | V |
| 21 | Basecamp | Credentials on box. | Login owner (A: Fredrik) | Low–Medium. | Company account owner. | S | 9 | A |
| 22 | Billing in general | Fredrik pays with private Mastercard 1532 and claims utlägg. Code lists costs "from Fredrik" (5 seats x $4, SEK 2,318.75/yr, SEK 400/yr, ~$225/month). | Private card | Medium. Cash and bookkeeping risk. | Company card on every vendor. | S each | 10 | V (config) |
| 23 | DNS / domain | Apps use `*.fly.dev`. No Fly certs on any app. Owner of `whyse.se` not checked. | Registrar login (A) | Medium. | Registrar account on company. | S | 10 | A |

## 3. Migration steps (smallest risk first)

Each step: do it, check it, and know the rollback.

1. **Add a second GitHub org owner.** Make one more founder owner of `whyse-ab`. Give the other founders write.
   - Check: `gh api "orgs/whyse-ab/members?role=admin"` lists two people.
   - Rollback: change the role back to member.
2. **Make company email aliases.** `ops@`, `billing@`, `bots@` on `whyse.se`, sent to at least two founders.
   - Check: a test mail to each alias reaches two people.
   - Rollback: delete the alias.
3. **Set up the company vault** (decision on card 1bdb4642). Copy secret names from this document. Fill values from Fly/GitHub owners, not by printing them in chat.
   - Check: each name in section 2 has an entry and an owner role.
   - Rollback: none needed; old places still work.
4. **Move GitHub App and OAuth App to the org.** Transfer `tales-forge-idea-board` and the login OAuth App to `whyse-ab` (Settings > Developer settings > Transfer ownership).
   - Check: App page shows owner `whyse-ab`; login works on prod and playtest.
   - Rollback: transfer back (needs org owner).
5. **Create the `whyse-bots` GitHub App** (or extend the idea-board App). Install on the 3 repos with only needed rights. Store App ID and key in vault.
   - Check: a bot pushes a test branch; the commit actor is `whyse-bots[bot]`.
   - Rollback: keep the old `gh` login on the box until step 6 passes.
6. **Switch bots and the box from Fredrik's `gh` token to the App.** Replace `GITHUB_DOCS_TOKEN`, `GITHUB_FEED_TOKEN`, `SECURITY_BOT_TOKEN` with App tokens. Then revoke Fredrik's box token.
   - Check: a new Actions run shows the App as actor. Fredrik gets no bot mail.
   - Rollback: run `gh auth login` again as before.
7. **Create Fly org `whyse`.** Company card, founders as members (two admins).
   - Check: `flyctl orgs list` shows `whyse` for each founder.
   - Rollback: delete the empty org.
8. **Move playtest first.** Move `tales-forge-playtest` and `tales-forge-playtest-db` to `whyse` (`flyctl apps move`, or new DB with dump/restore). Make a new org deploy token for `FLY_API_TOKEN_PLAYTEST`.
   - Check: playtest deploy from Actions passes; playtest login and Oban jobs run.
   - Rollback: move apps back; restore old token.
9. **Move production** the same way in a quiet window, after a DB backup. Find and move `whyse-workflow` too. Replace `FLY_API_TOKEN` and the box Fly token.
   - Check: prod deploy passes; health page OK; data count before = after.
   - Rollback: restore from the backup into the old app; old token still valid until removed.
10. **Move LLM and API vendors** (xAI, Typesafe/Intent) to company accounts on `billing@` with company card. New keys, set on Fly, old keys revoked.
    - Check: app makes an LLM call; vendor dashboard shows company account.
    - Rollback: put old key back (do not revoke until check passes).
11. **Billing, domain, Google, Basecamp, Grok Bot.** Move each to company card and company login. Stop utlägg.
    - Check: next invoice goes to Whyse AB.
    - Rollback: card can be changed back.

## 4. Open questions for founders

1. Who is the second (and third) owner of GitHub and Fly?
2. Vault: 1Password or Infisical?
3. One `whyse-bots` App, or one App per bot (Case, Bobby, Gentry)? One App is simpler; per-bot gives clearer logs.
4. Does Whyse AB have Google Workspace on `whyse.se`? If not, do we want it?
5. Who owns the `whyse.se` domain at the registrar?
6. Can Grok Bot run under a company account? If not, who carries the risk?
7. Is there a company card now? Which vendors move first?
8. Where is `whyse-workflow` deployed (it is not in the `personal` Fly org seen by the box)?
9. Are `SECURITY_BOT_*` and `SECURITY_LANE_*` set at org level, or missing?

## 5. Things only Fredrik can do

- Make another founder owner of `whyse-ab`.
- Transfer GitHub App `tales-forge-idea-board` and the login OAuth App to the org.
- Create Fly org `whyse` (or approve), and move apps out of his `personal` org; give the company card on Fly.
- Log in to xAI, Typesafe and other vendors to transfer, add company card, or make new keys.
- Revoke his personal tokens (box `gh` token, Fly token, old PATs) after the checks pass.
- Change billing from Mastercard 1532 on each vendor; close the utlägg flow.
- Grok Bot account and Google connector changes (his logins).
