# GitHub webhooks

The GitHub webhook moved to the Workflow app (`whyse-ab/workflow`,
`docs/github-webhooks.md` there). Its payload URL is
`https://whyse-workflow.fly.dev/webhooks/github`.

For 30 days after the cutover, this app answers `/webhooks/github` with a
307 redirect to Workflow. GitHub does not follow redirects, so change the
payload URL in the repository webhook settings at the cutover (Workflow
`docs/cutover-runbook.md`). After the cutover, remove the playtest webhook
(`https://tales-forge-playtest.fly.dev/webhooks/github`) and the secret
`GITHUB_WEBHOOK_SECRET` from both product apps.
