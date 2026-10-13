# GitHub webhooks

GitHub sends repository events to the app. The live PR feed on `/team`, the
deploy status in the feed, the board's PR cards and the bot wakes update from
each event (`TalesForge.GitEvents`, PubSub topic `"github"`). A full read of
GitHub every 30 minutes (`TalesForge.PrFeed.Reconcile`) is the backup for
missed deliveries.

## Endpoints

Each app has its own webhook. Add one webhook for each URL:

| App        | Payload URL                                              |
|------------|----------------------------------------------------------|
| Production | `https://tales-forge.fly.dev/webhooks/github`            |
| Playtest   | `https://tales-forge-playtest.fly.dev/webhooks/github`   |

The endpoint answers:

- `202` for an event that the app reads. The app broadcasts it on `"github"`.
- `204` for any other event (also `ping`).
- `401` when the signature (`X-Hub-Signature-256`) is not correct.
- `404` while the secret is not set. The endpoint is off.

## Secret

The Fly secret `GITHUB_WEBHOOK_SECRET` holds the webhook secret. Use the same
value on both apps and in both GitHub webhooks. The app checks the
HMAC-SHA256 of the raw request body with this secret, in constant time.

1. Make a random value and set it on both apps:

   ```sh
   SECRET="$(openssl rand -hex 32)"
   fly secrets set GITHUB_WEBHOOK_SECRET="$SECRET" -a tales-forge
   fly secrets set GITHUB_WEBHOOK_SECRET="$SECRET" -a tales-forge-playtest
   ```

2. Keep the value for the GitHub settings below. Do not put it in git.

## GitHub settings

In `whyse-ab/ex-tales-forge`, go to **Settings → Webhooks → Add webhook**. Do
these steps for each payload URL:

1. **Payload URL**: the URL from the table.
2. **Content type**: `application/json`.
3. **Secret**: the value of `GITHUB_WEBHOOK_SECRET`.
4. **SSL verification**: enabled.
5. **Which events**: select **Let me select individual events**, then select:
   - **Pull requests**
   - **Pushes**
   - **Workflow runs**
   - **Check suites**
6. Select **Active**, then **Add webhook**.

GitHub then sends a `ping`. The app answers `204`. On the webhook page,
**Recent Deliveries** shows each delivery and its answer.

## What each event does

| Event          | Feed (`TalesForge.PrFeed.Live`)                       | Board (`TalesForge.Board.GitHubEvents`, production)       |
|----------------|-------------------------------------------------------|-----------------------------------------------------------|
| `pull_request` | Updates that pull request, the counters and the pace. | Opened: queues the PR backfill. Merged: wakes Bobby (`pr.merged`). |
| `push` (main)  | Adds the new commits to the sha lookup and the pace.  | No change.                                                |
| `workflow_run` | `CI`: the CI badge. A deploy: reads the running commits again. | `CI` failed: wakes Bobby (`ci.failed`). `Deploy to production` passed: queues AutoDone. |
| `check_suite`  | No change (the `CI` runs give the badges).            | No change.                                                |
