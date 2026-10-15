---
title: Architecture
updated: 2026-10-12
---

# Architecture

Short rules for the shape of the game server code (decision 2026-10-12, Fredrik).

## A turn is one pipe

```elixir
input
|> Jev.classify()
|> Premise.check()
|> Mechanics.apply()
|> Npcs.react()
|> Prompt.build()
|> Gm.narrate()
|> Outcome.persist()
```

- Every stage takes a `%Turn{}` and returns a `%Turn{}`.
- Each stage writes only its own typed field: `turn.intent`, `turn.premise`, `turn.outcome`, `turn.npcs`, `turn.prompt`, `turn.narration`. No ad hoc `Map.put`.
- A rejected action is data on the struct (for example an `outcome` entry with `status: rejected` and a reason code), not an exception.

## Pure stages, IO at the edges

- Stages are pure. The LLM, the database and PubSub sit at the edges, or behind a small adapter that the struct or the options pass in. A test passes a fake adapter and needs no mocks.
- The NPC adapter holds the 600 ms reaction timeout.
- `Gm.narrate` takes a stream adapter that emits partial text (GM streaming, #191). It starts only after `Npcs.react` returns.

## Config once

- Flags and the app role are read from config into the struct once, at the start of the turn. No stage reads the environment.

## Style

- Pattern matching and function heads, not if/case chains.
- `{:ok, _}` and `{:error, _}` with `with`.

## Prompts

- A prompt is a pipeline of sections: `ctx |> Prompt.new() |> Prompt.add_all(Profile.turn_sections(ctx)) |> Prompt.to_messages()`.
- A section (`Prompt.Section`) has an id, a slot (`:static`, `:session` or `:turn`), `applies?/1` and `render/1`.
- `Prompt.to_messages/1` keeps the cache order static < session < turn.
- `Prompt.Profile` is the single registry of sections per call type (gm, scene, intent). It holds all the role, flag and baseline checks.
