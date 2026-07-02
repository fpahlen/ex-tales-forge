# ex-tales-forge — Agent Rules

## Project

Text-first AI RPG on the BEAM. Jido agents own play-session runtime; LiveView is the UI; PostgreSQL holds sessions and turn history.

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
4. Borrow rules/prompts/lore from `../text-forge`; do not port v1 Supabase code

## Dev commands

```bash
mix setup
mix phx.server          # http://localhost:4000
mix test
```

## Layout

```
lib/ex_tales_forge/
  agents/       # PlayerSessionAgent, NPCAgent (later)
  actions/      # Jido actions (PlayerMessage, ParseIntent, TellStory)
  game/         # Pure mechanics/inventory
  schemas/      # Ecto runtime schemas
priv/rules/     # Markdown rulebook
```