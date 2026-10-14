# Personal account migration – Whyse AB / Tales Forge

Date: 2026-10-14. Author: Grok Bot (read-only check of the box, Fly, GitHub and code).
Secret values are not in this document. Names only.

## 1. Goal and target structure

Goal: no part of Tales Forge or Workflow depends on Fredrik's personal accounts.

Target:
- **GitHub:** the org `whyse-ab` owns all repos. At least two founders are org owners. Bots use one GitHub App, `whyse-bots` (or one App per bot). No personal access tokens (PATs) in bots or CI.
- **Fly.io:** one org, `whyse`, owned by the company. Founders are members. All apps and databases are in this org. Deploy tokens are org- or app-scoped, not personal.
- **Email:** company aliases such as `ops@whyse.se`, `billing@whyse.se`, `bots@whyse.se`. Vendor accounts use these addresses.
- **Billing:** a company card. No more Fredrik's private card and no more utlägg.
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
| 22 | Billing in general | Fredrik pays with Fredrik's private card and claims utlägg. Code lists costs "from Fredrik" (5 seats x $4, SEK 2,318.75/yr, SEK 400/yr, ~$225/month). | Private card | Medium. Cash and bookkeeping risk. | Company card on every vendor. | S each | 10 | V (config) |
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
- Change billing from Fredrik's private card on each vendor; close the utlägg flow.
- Grok Bot account and Google connector changes (his logins).

## 6. Step-by-step instructions

Rules: one action per step. Never paste secret values in chat, tickets or this doc. Put them only in the vault or in the target system.
Who: **Fredrik only**, **Any founder**, or **Bobby** (bot work on the box, after a human gives access).
"Check in UI" = the path could not be verified against official docs on 2026-10-14. Confirm it in the UI before you follow it.

Important correction to section 3, step 8–9: Fly docs say `fly apps move` **does not work for Fly Postgres apps**. Move the database with a new Postgres app in the target org and a dump/restore (task 6.11). Also, apps in different Fly orgs do not share a private network. Move the database before or together with its app.

### 6.1 Add a second GitHub org owner (inventory #1, step 1)

- Who: Fredrik only.
- Prerequisites: founders agree on the owner(s) (open question 1). The new owner has 2FA on.

1. Open `https://github.com/orgs/whyse-ab/people`.
2. Find the founder.
3. Click the "..." menu on their row.
4. Click **Change role**.
5. Select **Owner**.
6. Click **Change role** to confirm.
7. Repeat for a third owner if agreed.

Or with the CLI (as an org owner):

1. Run `gh api -X PUT orgs/whyse-ab/memberships/<username> -f role=admin`.

Give the other founders write access (per repo):

1. Open `https://github.com/whyse-ab/<repo>/settings/access`.
2. Find the founder.
3. Change the role from **Read** to **Write** (or **Maintain**).
4. Repeat for each of the 3 repos.

CLI alternative: `gh api -X PUT repos/whyse-ab/<repo>/collaborators/<username> -f permission=push`.

- Check: `gh api "orgs/whyse-ab/members?role=admin" --jq '.[].login'` lists two or more people.
- Rollback: change the role back to **Member** (or run the same API call with `-f role=member`).

### 6.2 Create company email aliases (step 2)

- Who: Any founder with admin access to the whyse.se mail host. Whyse mail is on **one.com**.
- Prerequisites: login to the one.com control panel for `whyse.se`. Agree on who receives each alias (at least two founders).

1. Log in to the one.com control panel. (Check in UI)
2. Open the **Email** section for `whyse.se`. (Check in UI)
3. Create the alias / forwarding address `ops@whyse.se`. (Check in UI)
4. Add at least two founder addresses as recipients.
5. Save.
6. Repeat for `billing@whyse.se`.
7. Repeat for `bots@whyse.se`.

If whyse.se moves to Google Workspace later, create these as Google Groups instead (Admin console > Directory > Groups). (Check in UI)

- Check: send a test mail from an outside address to each alias. Two founders confirm they got it.
- Rollback: delete the alias in the control panel.

### 6.3 Set up the company vault (step 3; inventory #7, #15, #17, #20)

- Who: Any founder creates the vault. Each secret owner fills in values. Bobby may create empty entries by name.
- Prerequisites: decision on card 1bdb4642 (1Password or Infisical). Company account created on `ops@whyse.se`.

1Password:

1. Create a business account on `ops@whyse.se`.
2. Invite all founders (Admin console > People > Invite). (Check in UI)
3. Create a vault, for example `whyse-prod`: `op vault create whyse-prod`.
4. Create one item per secret name from section 2: `op item create --vault whyse-prod --category "API Credential" --title FLY_API_TOKEN`. Leave the value empty if you do not own it.
5. Add the owner role (e.g. `ops`, `billing`) as a tag on each item.
6. Ask each owner to paste the value directly in the 1Password app.

Infisical:

1. Create an organization on `ops@whyse.se`.
2. Invite all founders.
3. Create a project, for example `tales-forge`, with an environment `prod` and `playtest`.
4. Add each secret name in the UI. Or run `infisical secrets set <NAME>=<value> --env=prod` on the owner's own machine (never in chat).

Then:

1. Move box token files (`/home/box/.config/tales-forge/*`, Basecamp credentials) into vault entries.
2. Do not rotate `WEB_PUSH_VAPID_*` (rotation breaks subscriptions).

- Check: every secret name in section 2 has an entry with an owner role. Two founders can open the vault.
- Rollback: none needed. The old places still work until you remove them.

### 6.4 Transfer GitHub App `tales-forge-idea-board` to the org (inventory #4, step 4)

- Who: Fredrik only (current App owner, assumed). He must also be org owner of `whyse-ab`.
- Prerequisites: 6.1 done (so the org has a backup owner).

1. Click your profile picture (top right on GitHub).
2. Click **Settings**.
3. Click **Developer settings** in the left sidebar.
4. Click **GitHub Apps**.
5. Click `tales-forge-idea-board`.
6. Click **Advanced** in the left sidebar.
7. Click **Transfer ownership**.
8. Type `whyse-ab` as the new owner.
9. Select the **organization** `whyse-ab` from the dropdown (not an enterprise).
10. Read any uninstall warning.
11. Click **Transfer this GitHub App**.

- Check: `https://github.com/organizations/whyse-ab/settings/apps` lists the App. The idea board still works on prod and playtest. App ID and installation ID stay the same, so Fly secrets do not change.
- Rollback: an org owner transfers it back the same way (org Settings > Developer settings > GitHub Apps > App > Advanced > Transfer ownership).

### 6.5 Transfer the login OAuth App to the org (inventory #5, step 4)

- Who: Fredrik only (assumed owner).
- Prerequisites: 6.1 done. Know which OAuth App has the client ID in `GITHUB_OAUTH_CLIENT_ID` (compare the ID in the UI; do not print the secret).

1. Click your profile picture.
2. Click **Settings**.
3. Click **Developer settings**.
4. Click **OAuth Apps**.
5. Click the login app.
6. Click **Advanced**. (Check in UI)
7. Click **Transfer ownership**.
8. Type the app name to confirm.
9. Type `whyse-ab` as the new owner.
10. Click **Transfer this application**.

- Check: the app is listed under `https://github.com/organizations/whyse-ab/settings/applications`. Admin login works on prod and playtest. Client ID and secret stay the same.
- Rollback: an org owner transfers it back from the org's OAuth Apps page.

### 6.6 Create the `whyse-bots` GitHub App (step 5; inventory #2, #3, #6)

- Who: Any founder who is org owner (needs 6.1). Bobby can prepare the permission list.
- Prerequisites: decision on one App vs. one per bot (open question 3). Vault ready (6.3).

1. Open `https://github.com/organizations/whyse-ab/settings/apps`.
2. Click **New GitHub App**.
3. Set the name to `whyse-bots`.
4. Set the homepage URL to the repo or company site.
5. Clear **Webhook > Active** (bots do not need webhooks).
6. Set only needed repository permissions, e.g. Contents: Read and write, Pull requests: Read and write, Issues: Read and write, Actions: Read, Metadata: Read.
7. Select **Only on this account** under "Where can this GitHub App be installed?".
8. Click **Create GitHub App**.
9. Note the App ID.
10. Click **Generate a private key**. The `.pem` file downloads.
11. Store the App ID and the `.pem` in the vault. Delete the local `.pem` file.
12. Click **Install App** in the left sidebar.
13. Click **Install** next to `whyse-ab`.
14. Select **Only select repositories**.
15. Select the 3 repos.
16. Click **Install**.
17. Note the installation ID from the URL (`.../installations/<id>`) and store it in the vault.

Getting an installation token (expires after 1 hour):

- In Actions: use `actions/create-github-app-token@v1` with `app-id` and `private-key` from secrets.
- On the box: sign a JWT with the private key, then call `POST /app/installations/<id>/access_tokens`. Refresh before 1 hour.

- Check: a bot pushes a test branch. The commit/push actor shows `whyse-bots[bot]`.
- Rollback: uninstall or delete the App. The old `gh` login on the box still works until 6.8.

### 6.7 Org-level Actions secrets (inventory #3, step 6)

- Who: Any founder who is org owner.
- Prerequisites: 6.6 done; new Fly deploy tokens from 6.12/6.13 when you get there.

1. Open `https://github.com/organizations/whyse-ab/settings/secrets/actions`.
2. Click **New organization secret**.
3. Type the name, e.g. `SECURITY_BOT_APP_ID`.
4. Paste the value from the vault.
5. Under **Repository access**, choose **Selected repositories**.
6. Select `ex-tales-forge`.
7. Click **Add secret**.
8. Repeat for `SECURITY_BOT_APP_PRIVATE_KEY`, `SECURITY_LANE_WEBHOOK_URL`, `SECURITY_LANE_WEBHOOK_KEY`.

CLI alternative (value read from stdin or a file, never typed in chat): `gh secret set SECURITY_BOT_APP_ID --org whyse-ab --repos ex-tales-forge < value.txt`.

- Check: `gh secret list --org whyse-ab` shows the names. The next security-lane run passes.
- Rollback: `gh secret delete <NAME> --org whyse-ab`. Repo-level secrets win over org secrets with the same name, so old repo secrets still apply until deleted.

### 6.8 Switch the box and app tokens to the App; revoke Fredrik's token (inventory #2, #6, step 6)

- Who: Bobby does the box changes. Any founder sets Fly secrets. Fredrik only revokes his token.
- Prerequisites: 6.6 and 6.7 done and checked.

1. Change the app code to mint installation tokens instead of reading `GITHUB_DOCS_TOKEN` / `GITHUB_FEED_TOKEN` (it already has `GITHUB_APP_*` for the idea board).
2. Deploy to playtest.
3. Confirm docs and feed work on playtest.
4. Deploy to prod.
5. Run `fly secrets unset GITHUB_DOCS_TOKEN GITHUB_FEED_TOKEN -a tales-forge-playtest`.
6. Run the same for `-a tales-forge`.
7. On the box, switch git/`gh` to the App installation token helper.
8. Push a test branch from the box.
9. Fredrik: open `https://github.com/settings/applications` (Authorized OAuth Apps).
10. Fredrik: revoke **GitHub CLI** for the box session. (Check in UI)
11. Fredrik: open `https://github.com/settings/tokens` and delete PATs used by bots.

Notification settings (stop bot mail to Fredrik, until revoke is done):

1. Open `https://github.com/settings/notifications`.
2. Set **Default notifications email** to the address you want.
3. Under **Custom routing**, route `whyse-ab` to that address (or `bots@whyse.se` for a shared view).
4. Turn off **Actions** email notifications if not needed.

- Check: a new Actions run and a box push show `whyse-bots[bot]` as actor. Fredrik gets no bot mail. `gh auth status` on the box no longer shows `fpahlen`.
- Rollback: run `gh auth login` on the box again. Put the old Fly secrets back from the vault.

### 6.9 Create Fly org `whyse` and invite members (inventory #8, step 7)

- Who: Any founder can create it. Fredrik approves. Billing: whoever holds the company card.
- Prerequisites: company card. 6.2 done (`billing@whyse.se`).

1. Run `fly orgs create whyse`. (If the name is taken, pick e.g. `whyse-ab` and update this doc.)
2. Run `fly orgs invite whyse <founder-email>` for each founder.
3. Each founder accepts the invite email.
4. In the dashboard, open `https://fly.io/dashboard/whyse/billing`. (Check in UI)
5. Add the company card.
6. Set the billing email to `billing@whyse.se`. (Check in UI)
7. Make a second founder admin: dashboard > org `whyse` > **Team** > change role. (Check in UI)

- Check: `fly orgs show whyse` lists all founders. `fly orgs list` shows `whyse` for each founder.
- Rollback: `fly orgs delete whyse` (only while empty).

### 6.10 Move playtest app (inventory #8, #11, step 8)

- Who: Fredrik only (he must be a member of both `personal` and `whyse`). Bobby can prepare commands.
- Prerequisites: 6.9 done. Database moved first (6.11 for playtest), because apps in different orgs cannot reach each other on the private network.

1. Note current state: `fly secrets list -a tales-forge-playtest`, `fly volumes list -a tales-forge-playtest`, `fly certs list -a tales-forge-playtest`.
2. Run `fly apps move tales-forge-playtest --org whyse`.
3. Confirm the prompt.
4. Wait for machines to restart (up to a few minutes of downtime).

- Check: `fly status -a tales-forge-playtest` shows org `whyse`. `fly secrets list`, `fly volumes list` and `fly certs list` match step 1 (Fly moves machines, volumes, secrets and certs). Playtest login works. Oban jobs run.
- Rollback: `fly apps move tales-forge-playtest --org personal`.

### 6.11 Move a Postgres app (`tales-forge-playtest-db`, later `tales-forge-db`) (inventory #11)

- Who: Fredrik only (access to the old org), with Bobby.
- Prerequisites: 6.9 done. Agreed short write freeze. Fresh backup.
- Note: `fly apps move` does **not** support Fly Postgres apps (per Fly docs).

1. Stop writes: `fly scale count 0 -a tales-forge-playtest`.
2. Take a snapshot: `fly volumes list -a tales-forge-playtest-db`, then `fly volumes snapshots create <volume-id>`.
3. Create the new DB in the target org: `fly postgres create --name tales-forge-playtest-db-whyse --org whyse --region arn`.
4. Open a proxy to the old DB: `fly proxy 15432:5432 -a tales-forge-playtest-db`.
5. Dump: `pg_dump -Fc -h localhost -p 15432 -U postgres <dbname> -f playtest.dump` (password from vault).
6. Open a proxy to the new DB: `fly proxy 15433:5432 -a tales-forge-playtest-db-whyse`.
7. Restore: `pg_restore --no-owner -h localhost -p 15433 -U postgres -d <dbname> playtest.dump`. Create the database first if needed.
8. Move the app (6.10).
9. Attach the app: `fly postgres attach tales-forge-playtest-db-whyse -a tales-forge-playtest` (sets `DATABASE_URL`; use `--variable-name` or unset the old value if it clashes).
10. Start the app: `fly scale count 1 -a tales-forge-playtest`.
11. Delete the local dump file.

- Check: row counts on key tables match old and new. App health is OK. Oban jobs run.
- Rollback: set `DATABASE_URL` back to the old DB (still running in `personal`), move the app back, scale up. Do not delete the old DB until a week of good runs.

### 6.12 New playtest deploy token (inventory #3, step 8)

- Who: Any founder who is admin in `whyse`.
- Prerequisites: 6.10 done.

1. Run `fly tokens create deploy -a tales-forge-playtest -x 8760h`.
2. Paste the output straight into the vault entry `FLY_API_TOKEN_PLAYTEST`.
3. Run `gh secret set FLY_API_TOKEN_PLAYTEST --repo whyse-ab/ex-tales-forge` and paste the value at the prompt.

- Check: a playtest deploy from Actions passes.
- Rollback: set the old secret value back from the vault.

### 6.13 Move production, `whyse-workflow` and the box Fly token (inventory #8, #9, #10, #11, step 9)

- Who: Fredrik only for moves. Any `whyse` admin for tokens.
- Prerequisites: playtest checks pass. Quiet window. Backup.

1. Find `whyse-workflow`: Fredrik runs `fly apps list` on his own login and notes the org.
2. Repeat 6.11 for `tales-forge-db` → new DB in `whyse`.
3. Repeat 6.10 for `tales-forge`.
4. Run `fly apps move whyse-workflow --org whyse` (if it is not Postgres).
5. Run `fly tokens create deploy -a tales-forge -x 8760h` and store as `FLY_API_TOKEN` (vault, then `gh secret set FLY_API_TOKEN --repo whyse-ab/ex-tales-forge`).
6. Run `fly tokens create org -o whyse -x 8760h` and store as the box Fly token in the vault.
7. Bobby: switch the box `flyctl` to the new token from the vault.
8. Fredrik: revoke the old box token: `fly tokens list`, then `fly tokens revoke <id>`. (Check in UI for which token is the box token.)
9. Check the builder app `fly-builder-crimson-raindrop-2162`; it is recreated per org and can be deleted from `personal` later.

- Check: prod deploy passes. Health page OK. Row counts before = after. `fly apps list -o personal` shows no company apps.
- Rollback: point `DATABASE_URL` back to the old DB, move apps back with `fly apps move <app> --org personal`, restore old tokens from vault.

### 6.14 Move xAI API to a company team (inventory #12, step 10)

- Who: Fredrik only (current account). Any founder can be added to the new team.
- Prerequisites: `billing@whyse.se`, company card.

1. Log in to `https://console.x.ai`.
2. Create a new team for Whyse AB (team switcher > create team). (Check in UI)
3. Invite founders and `ops@whyse.se` to the team (team settings > Members). (Check in UI)
4. Open **Billing** for the team. (Check in UI)
5. Add the company card and set the billing email to `billing@whyse.se`.
6. Open **API Keys**.
7. Click **Create API key**.
8. Name it `tales-forge-prod`. Limit models/endpoints if offered.
9. Paste the key straight into the vault.
10. Run `fly secrets set XAI_API_KEY=<from vault> -a tales-forge-playtest` from the owner's own shell (not in chat).
11. Check playtest.
12. Repeat with a separate key for `-a tales-forge`.
13. Revoke the old keys in the old team after checks pass.

- Check: the app makes an LLM call. Usage shows on the company team.
- Rollback: set the old key back (do not revoke until checks pass).

### 6.15 Move Typesafe / Intent APIs (inventory #13, step 10)

- Who: Fredrik only (account owner, assumed).
- Prerequisites: same as 6.14.

1. Log in to the vendor dashboard. (Check in UI)
2. Change the account email to `billing@whyse.se`, or create a company account.
3. Add the company card.
4. Create new keys for `TYPESAFE_API_KEY`, `TYPESAFE_INTENT_API_KEY` (and `INTENT_JEV` if it is a key).
5. Store in vault.
6. Set on playtest with `fly secrets set`, check, then on prod.
7. Revoke old keys.

- Check: intent features work. Vendor shows the company account.
- Rollback: put old keys back.

### 6.16 Admin access in the app (inventory #16)

- Who: Any founder (Bobby can make the code change).

1. Create a GitHub team `admins` in `whyse-ab` (if not there): `https://github.com/orgs/whyse-ab/new-team`.
2. Add founders to the team.
3. Set `ADMIN_GITHUB_TEAM` to that team with `fly secrets set` on both apps.
4. Reduce `ADMIN_EMAILS` to company aliases, or unset it.

- Check: each founder can open the admin pages.
- Rollback: set `ADMIN_EMAILS` back from the vault.

### 6.17 Webhooks and shared app tokens (inventory #7, #15, #20)

- Who: Any founder.

1. Copy `GITHUB_WEBHOOK_SECRET`, `COSTS_PEER_TOKEN`, `PRODUCT_APP_API_TOKEN`, `WORKFLOW_API_TOKEN`, `WEB_PUSH_VAPID_*` names into the vault (values from their owners).
2. Do not change the values.

- Check: `https://github.com/whyse-ab/ex-tales-forge/settings/hooks` shows green recent deliveries.
- Rollback: not needed.

### 6.18 Grok Bot and Google connectors (inventory #18, #19)

- Who: Fredrik only.
- What stays personal for now: the Grok Bot account, the box, and the Google Drive/Calendar connectors on `fredrik.pahlen@gmail.com`. They are his logins.

1. Ask Grok Bot support if a company/team account is possible. (Check in UI)
2. If yes: create it on `bots@whyse.se` with the company card.
3. If Google Workspace on `whyse.se` is chosen (open question 4): create a shared drive.
4. Move company files from the personal Drive to the shared drive.
5. Connect the Google connectors with the company account in Grok Bot settings. (Check in UI)
6. Disconnect the personal Google connector only after files are moved.

- Check: bots read the shared drive. No company file is only in the personal Drive.
- Rollback: reconnect the personal connector.

### 6.19 Basecamp (inventory #21)

- Who: Fredrik only (owner, assumed).

1. In Basecamp, open **Adminland**. (Check in UI)
2. Make another founder owner.
3. Change billing to the company card.
4. Store the box credentials in the vault.

- Check: a second founder sees the owner role.
- Rollback: change the owner back.

### 6.20 Billing on every vendor (inventory #22, step 11)

- Who: Fredrik only (his logins); the card holder provides the company card.

1. List all vendors charged to Fredrik's private card.
2. For each vendor, open billing settings.
3. Add the company card.
4. Remove Fredrik's private card.
5. Set the invoice email to `billing@whyse.se`.
6. Stop the utlägg flow after the last private charge.

- Check: the next invoice from each vendor goes to Whyse AB.
- Rollback: change the card back.

### 6.21 DNS / domain (inventory #23)

- Who: whoever holds the registrar login (open question 5).

1. Find the registrar for `whyse.se` (`whois whyse.se`).
2. Log in.
3. Change the account email to `ops@whyse.se`.
4. Add a second founder as user, if the registrar allows it. (Check in UI)
5. Add the company card.

- Check: `whois whyse.se` shows Whyse AB as holder. Renewal is set to the company card.
- Rollback: change email back.

### 6.22 Email sending (inventory #14, later)

- Who: Any founder, when mail is turned on.

1. Create the provider account on `ops@whyse.se`.
2. Verify the `whyse.se` sending domain (DNS records at one.com).
3. Store the key in the vault.
4. Set `MAIL_ADAPTER` and the key with `fly secrets set`.

- Check: a test mail arrives and passes SPF/DKIM.
- Rollback: `fly secrets unset` the mail keys.
