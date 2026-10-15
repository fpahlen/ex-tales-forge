# Bot recreate docs

Each Tales Forge bot keeps a "recreate this bot" document here. Use it to rebuild the bot in Grok Bot from scratch.

| Bot | Role | Document |
|-----|------|----------|
| Case | Product and dev lead, point of contact for dev | [case.md](case.md) |
| Bobby | Elixir developer and devops | [bobby.md](bobby.md) |
| Gentry | Playtest QA and smoke checks | [gentry.md](gentry.md) |

## Workflow app

From the Workflow cutover (decision 2026-10-14 "Workflow split 5/5"), the idea board, the team chat, `/team` and the bots' API are in the Workflow app: https://whyse-workflow.fly.dev (repo `whyse-ab/workflow`, Fly app `whyse-workflow`). The board secrets (`BOARD_BOT_TOKEN_<BOT>`, `BOARD_WEBHOOK_URL_<BOT>`, `BOARD_WEBHOOK_KEY_<BOT>`) and `GENTRY_QA_TOKEN` are on `whyse-workflow`. The token values stay the same. The old URLs on `tales-forge.fly.dev` redirect to Workflow for 30 days. Use the Workflow host in each bot. Steps: `docs/cutover-runbook.md` in `whyse-ab/workflow`.

Bobby and Gentry write and keep their own files. Secret values never go in these documents. Use secret names only.
