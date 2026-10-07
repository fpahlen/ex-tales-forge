---
title: "Call types: Elixir function, Jev, or LLM"
updated: 2026-10-07
status: draft
---

# Call types: Elixir function, Jev, or LLM

**Status:** draft, 2026-10-07. Agreed rule for the Tales Forge app ([whyse-ab/ex-tales-forge](https://github.com/whyse-ab/ex-tales-forge), Elixir/Phoenix/Ash/Jido).

Every piece of work in a turn is one of three call types. Pick by the shape of the input and the output.

## The rule

| Input | Output | Call type | Cost |
| --- | --- | --- | --- |
| Structured (known) | Structured | **Elixir function** | Exact, free, instant |
| Unstructured (unknown) | Structured | **Jev call** (TypeSafe System One API) | Fast, cheap |
| Any | Unstructured (prose) | **LLM call** (xAI Grok, non-thinking model) | Slowest, most expensive |

- **Elixir function:** when we already know the shape of the data, plain code does it.
- **Jev:** when the input is free text or a messy situation but we want a typed answer. Jev returns typed JSON that Elixir pattern-matches across multiple function heads, so the result drives code directly.
- **LLM:** only when the output itself is prose a person reads. Use it last, with the smallest input possible.

## Corollary: structured output from the LLM is a smell

Whenever we are about to ask the LLM for structured output, move that work to Jev or Elixir. Today the GM also returns bookkeeping fields (gm_notes, context summary, NPC memories, state updates, mood adjustments). Only about 46% of GM output is player-facing story, and output length dominates GM latency (p50 about 5.9 s against a 3 s target). Taking the bookkeeping out of the LLM call makes the game faster and cheaper.

## Tales Forge examples

| Elixir function | Jev | LLM |
| --- | --- | --- |
| Dice rolls and skill checks | Player intent extraction into a typed struct: system exploit, a skill they don't have, which skills apply, out-of-character talk | GM scene narration |
| Damage and wounds | Persona affect scoring, 1-5 frustrated to delighted, with confidence (exists today, jev-1.13.0; see [Jev scoring](jev-scoring.md)) | NPC dialogue |
| Inventory | NPC gut reaction (System 1) from situation + OCEAN scores + mood | Opening scene |
| Coin and prices | Memory formation filtered through personality | Deliberate (System 2) NPC thinking, when it matters |
| Time advance | Playtest finding classification | Persona bot player text in playtests |
| Maslow need levels | | |
| Caps and billing of GM seconds | | |
| Prompt assembly | | |

## Target turn pipeline

```mermaid
flowchart LR
  A[Player text] --> B[Jev: intent, typed]
  B --> C[Elixir: rules and rolls]
  C --> D[Jev: NPC reactions]
  D --> E[Struct + short quote of player's words for tone]
  E --> F[LLM: GM narrates prose]
  F --> G[Elixir: record and bill]
```

1. Player text comes in.
2. Jev extracts intent as a typed struct.
3. Elixir applies rules and rolls dice.
4. Jev produces NPC reactions.
5. Elixir builds one struct of outcomes, plus a short quote of the player's own words so the GM keeps their tone.
6. The LLM GM narrates prose only.
7. Elixir records the turn and bills GM seconds.

## Character model

Player characters and NPCs are the same `Character` type: OCEAN personality scores, personality-filtered memory, and a Maslow need level. Only the controller differs: a player or the GM. That also lets the GM play an absent player's character using the same data and the same calls.
