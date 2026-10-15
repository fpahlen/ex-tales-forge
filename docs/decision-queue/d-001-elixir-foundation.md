---
id: d-001-elixir-foundation
title: "Confirm the Elixir rewrite as the foundation"
rank: 1
status: decided
options:
  - Commit to `ex-tales-forge` with a go/no-go at end of Dec 2026
  - Keep extending the old app
  - Hybrid: new engine behind the old frontend
decision: "Commit to the Elixir rewrite (`ex-tales-forge`): Elixir/Phoenix LiveView, Ash, Oban and Jido. Decided by Fredrik, who funds the project."
rationale: "The BEAM fits a soft real-time, always-on game with many concurrent sessions and agents. See docs/why-elixir.md."
decided_at: 2026-10-07
links:
  - roadmap-2027.md §3
  - docs/decisions.md#2026-10-07-elixir-is-the-platform
  - docs/why-elixir.md
interested: []
---

# Confirm the Elixir rewrite as the foundation

**Why:** Every later investment lands on one stack; splitting effort delays the first sale.

**Unblocks:** CI, deploy, harness, bots.

## Context

Seeded from Roadmap 2027 rev. 3 (2026-10-05). North star: the first paying customer the founders don't personally know.

## Decision

Decided 2026-10-07 by Fredrik: Elixir is the platform. Recorded in the decision log: [2026-10-07: Elixir is the platform](../decisions.md#2026-10-07-elixir-is-the-platform). Background: [Why Elixir](../why-elixir.md).

## Discussion

_(empty)_
