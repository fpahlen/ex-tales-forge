---
title: Future ideas
updated: 2026-10-10
---

# Future ideas

Ideas we may pick up later. They are not decisions and nobody is building them yet. Each entry says where it came from, what it is, the constraints, and when to pick it up. When an idea is picked up, it gets a design note and an entry in the [decision log](decisions.md), and the entry here links to them.

## Speculative intent while typing

- **From:** Fredrik, 2026-10-08 (via Case).
- **Idea:** after a typing pause of about 300–400 ms, run the Jev intent and safety call on the draft in the input box. On send, reuse that result if the text is unchanged; otherwise run the call again on the sent text.
- **Bigger win:** also start the work that follows intent early: the roll, the NPC reactions, the prices and a warm-up of the GM prompt cache. That might take 1–2 s off a turn of about 7 s.
- **Constraints:**
  - The turn always uses the exact text the player sent, never a stale draft. Anything computed from a draft is thrown away unless the sent text matches it exactly.
  - Speculative calls are capped per turn, so a slow typist can't run up cost.
- **When:** after the Jev intent path is live (PR 2 of the intent plan).
- **Related:** [Design: player intent as one Jev call](design-jev-intent.md), [Design: persistent world state](design-stateful-world.md#8-cost-and-latency) (the turn's cost and latency).

## Memory consolidation and attitude drift

*Fredrik, 2026-10-08. A later layer on top of the [stateful world](design-stateful-world.md).*

- **Consolidation on the world clock.** On a world-clock tick (about hourly in game time), memories nobody has touched since the last tick merge into a gist and lose detail. The merge is plain Elixir or a Jev call, never an LLM.
- **Strong moments stay sharp.** Memories with strong emotion keep their detail longer.
- **Personality sets the pace.** OCEAN traits decide how fast things fade: high neuroticism holds on to slights, and high agreeableness forgives sooner.
- **Meeting again refreshes.** Seeing someone again refreshes the gist and starts a new detailed layer on top of it.
- **Attitudes drift toward neutral.** Feelings slowly drift back toward neutral over world time, and grudges fade more slowly than warmth.
- **NPCs and PCs alike.** The same rules apply to both, since they share the unified character type.

Fits the per-world process: consolidation and drift are pure functions run on world ticks, stored as data, so restarts and replays give the same result.

## Founder kanban on /team

- **From:** Fredrik, 2026-10-09 (via Case).
- **Idea:** turn `/team` into the shared workspace for founders and bots: a kanban board with the columns Ideas → Refining (Case) → Founder check → Building (Bobby) → Done.
  - Founders add a feature card or move one into the queue.
  - Case refines it: details, open questions and a rough cost.
  - Founders check it's what they meant, comment, and drag it to Building.
  - Bobby builds it, with the PR and playtest links on the card. Then it moves to Done.
- **No polling:** moving a card pings the right bot (Refining → Case, Building → Bobby).
- **One place for each thing:** an approved card writes its own entry in [decisions.md](decisions.md).
- **Approval:** dragging a card to Building is the founder OK, a step toward every founder holding the approval key.
- **Builds on:** the existing Collab decision queue in ex-tales-forge (`TalesForge.Collab`, `/admin/decisions`: decisions imported from this repo, with comments, interest and rank in Postgres; exporting decided outcomes back to Markdown is still a TODO). The board would extend that into an idea-to-done flow, not start from scratch.
- **When:** after the `/team` page is live; needs a design note and Fredrik's OK before any code.
- **Related:** [team page brief](team-page/content.md#6-how-well-work-together-one-shared-board), [design: decision queue and docs](design-decision-queue-and-docs.md).

## Presence on /team

- **From:** Fredrik, 2026-10-10.
- **Idea:** show who's online on `/team` with Phoenix Presence — founders and bots — and what each is doing right now (e.g. Bobby on a PR, Gentry probing, Case reviewing).
- **When:** after the `/team` page is live; needs a design note and Fredrik's OK before any code.
- **Related:** [Founder kanban on /team](#founder-kanban-on-team), [team page brief](team-page/content.md).

## Team chat with mentions

- **From:** Fredrik, 2026-10-10.
- **Idea:** a team chat on `/team` with mentions (`@Case`, `@fpahlen`, `@founders`). Mentioning a bot wakes it so it can join the thread.
- **When:** after Presence on `/team`; needs a design note and Fredrik's OK before any code.
- **Related:** [Presence on /team](#presence-on-team), [Founder kanban on /team](#founder-kanban-on-team).

## Built-in screen capture in chat

- **From:** Fredrik, 2026-10-10.
- **Idea:** built-in screen capture in team chat for bug reports, using the Screen Capture API. Capture the app, not the chat window, so a screenshot or clip lands in the thread with the report.
- **When:** after team chat; needs a design note and Fredrik's OK before any code.
- **Related:** [Team chat with mentions](#team-chat-with-mentions).

## Code heat map

- **From:** Fredrik, 2026-10-10.
- **Idea:** a module tree coloured by call count, total time and average time, filterable to show hot spots. Built from telemetry so founders and bots can see where the app spends its time.
- **When:** after enough telemetry is in place; needs a design note and Fredrik's OK before any code.

## Attribution

- **From:** Fredrik, 2026-10-10.
- **Idea:** tag PRs, branches and cards with who came up with the idea, and show that attribution wherever the work appears.
- **When:** alongside the Founder kanban; needs a design note and Fredrik's OK before any code.
- **Related:** [Founder kanban on /team](#founder-kanban-on-team).
