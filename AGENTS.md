# ex-tales-forge — Agent Rules

## Project

Text-first AI RPG on the BEAM. Jido agents own play-session runtime; LiveView is the UI; PostgreSQL holds sessions and turn history.

Greenfield Elixir rewrite of [text-forge](../text-forge). Borrow rules, prompts, and lore from text-forge; do not port v1 Supabase code.

## Stack

- **UI:** Phoenix LiveView + Tailwind
- **Runtime:** Jido 2.x agents + actions
- **Persistence:** Ecto + PostgreSQL (`GameSession`, `Turn`, `NpcInstance`)
- **Jobs:** Oban (LLM + images later)
- **Authoring (later):** Ash domains for roster/adventures — not the game loop

## Non-negotiables

1. Ash owns content that exists **before** play; Jido + Oban own **during** play
2. Tier 1 intent must run before Tier 2 GM; raw player text never reaches Tier 2
3. Server rolls dice and applies LP/inventory — the LLM narrates, not invents mechanics
4. Important authored state stays human-readable: `priv/rules/*.md`, `priv/prompts/*.txt`
5. LLM responses use structured JSON (Tier 1 `PlayerAction` via `TalesForge.Game.Intent`)
6. Turn history is auditable — persisted in the `Turn` schema (text-forge uses git commits per campaign turn; same goal, different storage)
7. Borrow rules/prompts/lore from `../text-forge`; do not port v1 Supabase code

## Git workflow

1. **Never commit development work directly to `main`.**
2. Before starting a new feature or fix, create a branch:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/<short-name>
   ```
3. Use kebab-case short names that describe the work (e.g. `feature/two-tier-llm`, `setup/local-env`, `fix/oban-migration`).
4. Commit and push on the feature branch; merge to `main` via PR when ready.
5. If already on `main` with uncommitted work, stash or commit to a new feature branch before continuing.

## Dev commands

```bash
cp .env.example .env          # add XAI_API_KEY
mix setup                     # deps, DB, assets
mix dev.check                 # Postgres + API key + provider
mix phx.server                # http://localhost:4000
mix test
mix precommit                 # format + test (run before opening a PR)
```

### Troubleshooting

**Port 4000 in use** — stale server still running:

```bash
lsof -ti :4000 | xargs kill -9
```

**`GM source: mock` in the UI** — API key not loaded. Check `.env`, run `mix dev.check`, restart `mix phx.server`.

**No LLM logs during play** — restart the server after editing `.env`. Create a new session (cached state may skip the LLM).

**Ollama hijacking Tier 1** — if Ollama is running on `:11434`, Tier 1 may prefer it. Force xAI in `.env`:

```
TIER1_MODEL=xai/grok-4.3
```

**PostgreSQL not running**:

```bash
brew services start postgresql@16
mix setup
```

## LLM providers

Set API keys in `.env` (loaded automatically in dev via `config/runtime.exs`). Provider resolution in `TalesForge.Config`:

1. If `LLM_PROVIDER` is set, use that provider explicitly (`mock`, `xai`, `openai`, `anthropic`).
2. Otherwise auto-select: `xai` if `XAI_API_KEY` is set, else `openai`, else `anthropic`, else `mock`.

| Provider | Key | Notes |
|----------|-----|-------|
| `mock` | none | Deterministic fallback for offline dev |
| `xai` | `XAI_API_KEY` | Default when key is present; model via `XAI_MODEL` (default `grok-4.3`) |
| `openai` | `OPENAI_API_KEY` | |
| `anthropic` | `ANTHROPIC_API_KEY` | |

### Two-tier LLM

Each turn runs Tier 1 intent extraction (small model, temp 0) then Tier 2 storytelling (Grok). Raw player text never reaches Tier 2 — only validated `PlayerAction` JSON.

| Setting | Default | Purpose |
|---------|---------|---------|
| `TIER1_MODEL` | auto | Intent extraction model |
| `TIER2_MODEL` | auto | GM narration model |
| `TIER1_TEMPERATURE` | `0` | Intent extraction |
| `TIER2_TEMPERATURE` | `0.7` | Storytelling |
| `TIER1_CONFIDENCE_THRESHOLD` | `0.75` | Heuristic fallback cutoff |

Tier 1 auto-selects Ollama when running locally. Compound or ambiguous actions may return a clarification prompt before the turn resolves.

Set `LOG_LEVEL=debug` in `.env` for full LLM request/response logging.

## Relationship to text-forge

| text-forge | ex-tales-forge |
|------------|----------------|
| `backend/app/rules/*.md` | `priv/rules/*.md` |
| `backend/app/prompts/*.txt` | `priv/prompts/*.txt` |
| File-based campaigns + git per turn | PostgreSQL runtime + Ecto schemas |
| FastAPI + Next.js | Phoenix LiveView + Jido |

When rules or prompts change in text-forge, sync the corresponding files here. Product principles are shared; storage and runtime differ by design.

## Turn pipeline

1. `GameSessions.submit_message/3` — Tier 1 intent (heuristic or LLM)
2. `TalesForge.Workers.ProcessTurn` (Oban `:llm` queue) — Tier 2 GM + mechanics
3. PubSub `{:turn_completed, payload}` → LiveView

## Layout

```
lib/ex_tales_forge/
  agents/       # PlayerSessionAgent, NPCAgent (later)
  game/         # intent, mechanics, action_handler, turn_processor
  workers/      # Oban ProcessTurn
  schemas/      # Ecto runtime schemas
priv/rules/     # Markdown rulebook (from text-forge)
priv/prompts/   # LLM system prompts (from text-forge)
```

## Playtest agent (`/play_test`)

After code changes, run a live playthrough to verify intent extraction and GM responses. See [`.grok/skills/play-test/SKILL.md`](.grok/skills/play-test/SKILL.md). Automated Elixir playtest runner is not yet implemented — use manual browser checks until then.