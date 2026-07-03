# ex-tales-forge

Tales Forge on the BEAM — a text-first AI RPG with Jido agents, Phoenix LiveView, PostgreSQL, and Oban.

This is a greenfield Elixir rewrite. Game rules and prompts are borrowed from [text-forge](../text-forge); v1 Supabase code is reference-only.

## Stack

| Layer | Technology |
|-------|------------|
| UI | Phoenix LiveView |
| Game runtime | Jido 2.x agents + actions |
| Database | PostgreSQL + Ecto |
| Background jobs | Oban |
| LLM | xAI Grok (Tier 1 intent + Tier 2 GM) |
| Images (planned) | Tigris on Fly.io |
| Deploy (planned) | Fly.io |

## Prerequisites

- Elixir 1.15+
- PostgreSQL 16+ (local default: `postgres` / `postgres`)
- Node.js (for asset bundling)

## Local setup

### 1. Environment file

Secrets live in `.env` at the project root. This file is gitignored — only `.env.example` is committed.

```bash
cd ex-tales-forge
cp .env.example .env
```

Edit `.env` and add your xAI API key:

```
XAI_API_KEY=xai-your-key-here
```

The app loads `.env` automatically in development via `config/runtime.exs`. You do not need to `export` variables manually.

### 2. Database

Start PostgreSQL if it is not already running:

```bash
brew services start postgresql@16
```

Create the database and run migrations:

```bash
mix setup
```

To use a non-default connection string, uncomment `DATABASE_URL` in `.env`:

```
DATABASE_URL=ecto://postgres:postgres@localhost/ex_tales_forge_dev
```

### 3. Verify

```bash
mix dev.check
```

You should see PostgreSQL connected and your API key masked (e.g. `xai-...abcd`). If the key is missing, the game falls back to mock GM narration.

## Run

```bash
mix phx.server
```

Open http://localhost:4000

1. Click **Start new session**
2. Type an action on the play screen

With `XAI_API_KEY` set, the play header shows `GM source: api` after your first turn. Without it, you will see `GM source: mock`.

Default model is fast non-reasoning Grok (`grok-4.20-0309-non-reasoning`). Verify turn latency with `mix e2e.smoke` (3s budget per turn).

## Project layout

```
lib/
  ex_tales_forge/
    agents/          # Jido agents (PlayerSessionAgent, NPC agents later)
    actions/         # Jido actions (PlayerMessage, LLM pipeline later)
    game/            # Pure game logic (mechanics, inventory)
    schemas/         # Ecto schemas (runtime persistence)
    game_sessions.ex # Session + agent coordination
  ex_tales_forge_web/
    live/            # HomeLive, PlayLive
priv/
  rules/             # Markdown rulebook (from text-forge)
```

## Phase status

- [x] Phase 0: Phoenix + Jido + LiveView play loop with mock GM
- [x] Phase 1: Two-tier LLM pipeline + server mechanics (mock GM when no API key)
- [ ] Phase 2: Ash authoring layer + Tigris images
- [ ] Phase 3: NPC agents + world clock

## Development

See [AGENTS.md](AGENTS.md) for git workflow, Elixir idioms, LLM conventions, and troubleshooting.

- Work on feature branches — never commit directly to `main`
- Run `mix format` while coding; run `mix precommit` before opening a PR
- `mix quality` runs format check + Credo on `lib/`
- After gameplay changes, smoke-test with `/play_test` (see `.grok/skills/play-test/SKILL.md`)

## Tests

```bash
mix test
```