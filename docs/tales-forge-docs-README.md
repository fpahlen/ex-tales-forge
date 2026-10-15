# Tales Forge docs

Private source of truth for the founders' **decision queue** and **shared docs**.

- `decisions/` — one Markdown file per decision (YAML front matter). Ranked by `rank` (lowest = most important).
- `docs/decisions.md` — the [decision log](decisions.md): what has been decided and why, newest first.
- `docs/` — longer design notes and plans (see [docs/README.md](README.md); latest: [Jev scoring](jev-scoring.md)).

Git history is the audit log. The game admin (`ex-tales-forge`) indexes this repo for the LiveView queue; agents propose via MCP/PRs; only founders record outcomes.

See `SCHEMA.md` for the decision file format.

## Writing rules

Write with positive framing ("confidence", never "unsure" or "uncertainty") and in ASD-STE100 Simplified Technical English. See [CONTRIBUTING.md](writing-rules.md) and the [decision](decisions.md) of 2026-10-10.
