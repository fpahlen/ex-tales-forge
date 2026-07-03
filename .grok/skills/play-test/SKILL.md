---
name: play-test
description: >
  Run a live playthrough against Tales Forge (ex-tales-forge) after code changes.
  Use when the user runs /play_test, /play-test, or asks to smoke-test
  a session playthrough, check response times, or verify intent extraction.
---

# Play Test (`/play_test`)

Run a **live** playthrough against the Phoenix server with real LLM calls.

> **Status: stub.** text-forge has a full Python playtest agent at `text-forge/backend/app/playtest/`. Elixir automation is not built yet — use the preflight + manual steps below until a Mix task exists.

## Parse arguments

- Slash command: `/play_test` or `/play_test tavern_smoke`
- Default scenario: `tavern_smoke` (not yet implemented — manual steps use equivalent actions)
- Future: YAML scenarios in `priv/playtest/scenarios/*.yaml` (port from text-forge)

## Preflight

1. **Repo root** — run commands from the ex-tales-forge directory.

2. **Environment** — `mix dev.check`
   - `[ok] .env found`
   - `[ok] PostgreSQL connected`
   - `[ok] XAI_API_KEY set (...)` and `LLM provider: xai`
   - If any check fails, stop and fix before playtesting.

3. **Server health** — Phoenix on port 4000:
   ```bash
   curl -sf http://localhost:4000 > /dev/null && echo "server up"
   ```
   - If down, start:
     ```bash
     mix phx.server
     ```
   - If port busy: `lsof -ti :4000 | xargs kill -9` then restart.

4. **API key** — confirm `.env` has `XAI_API_KEY`. Warn if `LLM_PROVIDER=mock` — playtest should use `GM source: api`.

## Run playtest (manual until automated)

Until `mix playtest` exists, perform these steps in the browser at http://localhost:4000:

1. Click **Start new session** (always use a fresh session after code changes).
2. Play through the tavern smoke scenario:
   - `look around the tavern`
   - `talk to the barkeep`
   - `order an ale`
3. After each turn, verify:
   - GM narration appears (not mock footer text)
   - Play header shows **`GM source: api`**
   - Terminal logs include `llm call start provider=xai` (or chosen provider)

For ambiguous-input testing, try a compound action and confirm a clarification panel appears before resolution.

## Report results

State **PASS** or **FAIL** clearly.

For each step, note:
- Whether the response was mock or API-sourced
- Approximate latency (subjective until automated timing exists)
- Whether intent/mechanics seemed correct (skill checks, inventory, etc.)

Suggest which layer broke:
- **intent** → `lib/ex_tales_forge/game/intent.ex`
- **GM / narrative** → `lib/ex_tales_forge/llm.ex`, `priv/prompts/gm_system.txt`
- **mechanics** → `lib/ex_tales_forge/game/mechanics.ex`, `action_handler.ex`
- **latency** → model config, Oban queue, or network

## Do not

- Substitute `mix test` for this skill — the point is a live end-to-end run with real LLM calls.
- Reuse an old session after pulling code changes — start a new one.
- Fail silently when `mix dev.check` reports missing API key.

## TODO: automated playtest (future)

Port from [text-forge/backend/app/playtest/](text-forge/backend/app/playtest/):

- [ ] `priv/playtest/scenarios/*.yaml` — scenario definitions with `expect` blocks
- [ ] `Mix.Tasks.Playtest` or `lib/ex_tales_forge/playtest/` — HTTP/LiveView driver
- [ ] `--judge` mode using LLM to score narrative quality
- [ ] JSON report output (`playtest-report.json`)
- [ ] Intent debug exposure on turn responses (like text-forge `PLAYTEST_EXPOSE_INTENT`)

Reference implementation: `text-forge/.grok/skills/play-test/SKILL.md` and `backend/.venv/bin/python -m app.playtest --judge`.