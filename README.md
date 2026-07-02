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
| LLM (planned) | jido_ai / req_llm (Tier 1 intent + Tier 2 GM) |
| Images (planned) | Tigris on Fly.io |
| Deploy (planned) | Fly.io |

## Prerequisites

- Elixir 1.15+
- PostgreSQL (local default: `postgres` / `postgres`)
- Node.js (for asset bundling)

## Setup

```bash
cd ex-tales-forge
mix setup
```

Copy environment template if you need LLM keys later:

```bash
cp .env.example .env
```

## Run

```bash
mix phx.server
```

Open http://localhost:4000

1. Click **Start new session**
2. Type an action on the play screen (Phase 0 uses mock GM narration)

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
- [ ] Phase 1: Two-tier LLM pipeline + server mechanics
- [ ] Phase 2: Ash authoring layer + Tigris images
- [ ] Phase 3: NPC agents + world clock

## Tests

```bash
mix test
```