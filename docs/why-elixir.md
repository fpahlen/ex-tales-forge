---
title: "Why Elixir"
updated: 2026-10-06
source: https://docs.google.com/document/d/19w4sYfea-OamyPrnMk44hhbuVFDU9kKXirkqR_jjmtE/edit
---

# Why Elixir for Tales Forge

*Fredrik Pahlén, 2026-10-05. A proposal for the team, especially tsjokvist.*

## First: credit where it's due

The current app (`tales-forge-new`: React/TS/Vite, Supabase, 40+ edge functions, LangGraph, multi-provider LLM, a proper dev→staging→main pipeline) is why we know Tales Forge is worth building. Most of it was written by tsjokvist. It got real players in (17 users, 22 characters and 17 sessions at the May 2026 premortem), and the premortem it made possible gave us an honest list of what's hard. This proposal builds on that work. The question is not whether the old app was built right. It is which foundation best fits the game we now know we want to build.

## Elixir and the BEAM in five minutes

*For anyone on the team who hasn't used Elixir. Skip this if you have.*

**Where it comes from.** In the late 1980s Ericsson created the Erlang language and its virtual machine, the **BEAM**, to run telephone switches. Those systems had to be *soft real-time* (answer quickly and predictably), *always on* (no downtime for upgrades), and able to swap in new code while running (*hot code upgrades*). Erlang has been open source since 1998.

**Elixir** was created by José Valim, starting around 2011 (1.0 in 2014). It runs on the same BEAM and can call any Erlang library, so it inherits 30+ years of runtime engineering. What it adds is a friendlier, Ruby-like syntax, macros, and modern tooling: **Mix** (build, tests, tasks) and **Hex** (package manager). **Phoenix** is its main web framework, and LiveView is part of the Phoenix ecosystem.

**Core ideas**
- **Lightweight processes.** A BEAM "process" is not an OS thread. It's a tiny unit managed by the VM, costing a few kilobytes and created in microseconds. Running hundreds of thousands, or even millions, on one machine is normal.
- **Message passing, no shared memory.** Processes don't share state. They send each other messages, so there are no locks and no data races between them.
- **Per-process garbage collection.** Each process collects its own garbage, so there's no global "stop the world" pause that freezes everyone.
- **Preemptive scheduling on all cores.** The VM runs one scheduler per CPU core and gives each process a small time slice before switching. One slow or busy process can't stall the others. That matters for latency: one heavy world-sim job won't delay a player's turn.
- **"Let it crash" and supervisors.** Instead of defensive error handling everywhere, you let a broken process die. A **supervisor** watches it and restarts it in a known good state. **OTP** (Erlang's standard framework) provides ready-made building blocks such as **GenServer** (a process with state that handles requests), Supervisor and Registry.
- **Functional and immutable.** Data never changes in place. Functions take data and return new data. **Pattern matching** lets you destructure data and pick code paths by its shape, which makes behaviour explicit and easy to test.

**A tiny example: an NPC as a process**

```elixir
defmodule NPC do
  use GenServer
  def init(name), do: {:ok, %{name: name, mood: :calm}}
  def handle_cast({:insulted, _by}, state), do: {:noreply, %{state | mood: :angry}}
  def handle_call(:mood, _from, state), do: {:reply, state.mood, state}
end

{:ok, npc} = GenServer.start_link(NPC, "Old Mara")
GenServer.cast(npc, {:insulted, "Hawk"})
GenServer.call(npc, :mood)  #=> :angry
```

*Each NPC is its own small process that keeps its state and reacts to messages. Pattern matching on the message (`{:insulted, _by}`, `:mood`) picks which function runs.*

**Who uses it in production** (well-documented cases): **Ericsson** (telecom switches, where Erlang began), **WhatsApp** (Erlang backend), **Klarna** (its core system, Kred, is Erlang and dates back to 2004), **Discord** (Elixir for its real-time chat infrastructure, at millions of concurrent users), and **RabbitMQ** (the message broker is written in Erlang).

**How it maps to Tales Forge**
- **One process per game session and one per NPC**, plus a world clock process. State lives in memory where the game needs it and is persisted to Postgres.
- **Supervisors** restart a crashed NPC (for example after a bad LLM response) without taking down the player's session.
- **Phoenix PubSub** broadcasts world events and GM text to everyone who needs them. LiveView pushes the updates to the browser.

**Where to learn**
- Official getting started guide: https://elixir-lang.org/getting-started/introduction.html
- Elixir School (free lessons, beginner to OTP): https://elixirschool.com/en
- Phoenix docs: https://hexdocs.pm/phoenix/overview.html
- Exercism Elixir track (exercises with mentoring): https://exercism.org/tracks/elixir

## What the premortem told us

- **Monolithic prompts/engine.** It's hard to change one part without breaking another.
- **The living-world tick isn't connected to live play.** The world doesn't really live, even though the site markets living NPCs.
- **First-session magic** is fragile.
- **Observability** is thin. When something goes wrong (e.g. issue #29, gibberish output on an action), it's hard to see why.

On top of that, we have a hard requirement: **≤ 3 s from player input to response.**

## Why the BEAM fits this game

**1. A process per session, per NPC, per world.** On the BEAM, processes are cheap and isolated. Each game session, each NPC agent (Jido) and the world clock can be its own long-lived process with its own state, talking over messages and PubSub. That is exactly the "living world" design: NPCs that keep existing between turns, and a world that ticks while players are away. In the current stack each edge function is stateless and short-lived, so a living world has to be rebuilt from the database on every call. That is a big part of why the tick never got wired into live play.

**2. Fault tolerance by design.** Supervisors restart a crashed NPC or session process without taking anything else down. An LLM timeout or a malformed response becomes a contained, restartable failure, not a broken session. tsjokvist knows from casino systems how much reliability is worth when real-time state matters. OTP gives us that model as part of the runtime, not as something we bolt on.

**3. LiveView: real-time without an API + SPA.** The server holds the session state and pushes diffs to the browser over a WebSocket. Streaming GM text token by token is natural. We drop a whole layer: no separate REST/edge API, no client-side state syncing, no duplicated types between frontend and backend.

**4. Oban keeps slow work off the latency path.** NPC ticks, world simulation, image generation and summaries run in Oban queues (`default`, `llm`, `images`), backed by Postgres, retryable and visible. The player's 3 s only covers what the player needs right now.

**5. One language, one deploy.** One Elixir app on Fly replaces Netlify + Supabase + 40+ edge functions (Deno) + a LangGraph orchestration layer. That means one codebase to grep, one test suite, one deploy and one place to add telemetry. This directly addresses the observability risk.

**6. Modular engine instead of monolith prompts.** The rewrite splits the turn into a **two-tier LLM**: Tier 1 classifies intent, Tier 2 narrates as GM. Mechanics (dice 1d20 ≤ skill, LP from failures, inventory) are computed **server-side** in plain code. Each piece can be tested and swapped on its own. The LLM narrates the outcome, it doesn't decide it, which also cuts down on gibberish cases like #29.

**7. It suits a bot-built codebase and self-play at scale.** The 2027 plan is a swarm of AI coding bots that code and test, plus persona player agents that play every build. Elixir helps on both sides:
- *Self-play at scale:* each simulated session (a persona agent plus its game session) is just another cheap BEAM process. Hundreds of concurrent self-play sessions can run on one node, and that doubles as a load test of the real supervision tree.
- *Bot output that can be checked:* Phoenix/Ecto/Ash conventions give bots one obvious way to do things. Pattern matching and small pure functions make behaviour explicit, and ExUnit (with doctests and property tests) makes it cheap for bots to write tests and for humans to read them.
- *Gates for free:* the compiler (warnings as errors), Dialyzer, Credo and `mix format` reject a whole class of bad bot output before a human looks at it.

Honestly, there is less Elixir than TypeScript in the models' training data, so bot output may need more correction at first. The gates and reviews are how we find out, and we'll track it.

## It isn't a blank page

`whyse-ab/ex-tales-forge` already has:
- **Phase 0:** mock GM loop end-to-end.
- **Phase 1:** two-tier LLM (xAI Grok) and server-side mechanics.
- **Phase 2:** Ash-based authoring/admin and a pack importer.
- **Phase 3 (partly):** NPC agents and the world clock in code.
- Next: the fronts/WorldSim design, using Tin Valley as a tracer.

What's missing is the boring but essential stuff: CI (there's none), a real Fly deploy (only a `fly.toml` stub), the eval/latency harness, and parity with the old app. That's exactly where experience with real-time systems in production, like tsjokvist's, would make the biggest difference. Anyone who wants to pick it up is welcome.

## Latency: the honest picture

Non-LLM work (dice, state, rendering) takes milliseconds in either stack. **The 3 s budget is spent on LLM calls.** The levers are the same whichever language we pick:
stream GM text (first token < 1 s), use a fast/small model or rule-based shortcut for Tier 1, use prompt caching and shorter prompts, and run NPC/world/image work async. Elixir helps with the last two structurally (processes hold context, Oban handles async). We'll measure p50/p95 time-to-first-token and full response from the start, not argue about them.

**Why not Rust for the core?** Rust would make the milliseconds faster, and the milliseconds aren't our problem. It would cost development speed on the parts that matter (game logic, prompts, iteration). If profiling ever shows a CPU hotspot (e.g. a heavy WorldSim calculation), we can drop in a Rust NIF via Rustler for just that piece.

## Honest costs and risks

| Cost / risk | Mitigation |
|---|---|
| **Smaller hiring pool** than TS/React | We're a small team for 2027; Elixir devs are fewer but tend to be experienced and keen. Visibility via ElixirConf 2027 helps recruiting. |
| **Learning curve** for everyone new to Elixir | Primer + pairing; first PRs in contained areas (Ash admin, content tooling). Architecture, scaling and ops experience carries over regardless of language: reviewing designs and running load tests doesn't require writing much Elixir. |
| **Rewrite risk:** the classic trap of never reaching parity | Phases 0–2 already done; an explicit parity checklist; the old app stays live until the new one is better; monthly target outcomes and a "stop" condition. |
| **Losing Supabase conveniences** (auth, dashboard, row-level security, hosted functions) | phx.gen.auth / Ash auth for accounts; Ash admin for data; plain Postgres (could even stay on Supabase as a DB); we take on more ops ourselves, on Fly, drawing on the team's real-time ops experience. |
| **Single provider (xAI)** in the new app | Keep the LLM client behind an interface; test a fallback model in the latency harness. |
| **Bus factor:** Fredrik has written all the new code so far | Reviews, ADRs, docs, and getting more of the team into the codebase early. |

## The ask

I propose that at the October 2026 kickoff we decide together:

1. **Commit to `ex-tales-forge` as the platform for 2027**, with the old app kept live (bug fixes only) until parity.
2. **Start with the foundations:** CI gates, a real Fly deploy, the eval harness design and a critical review of the process/supervision design. Nobody is assigned. Whoever wants to take a piece picks it up. tsjokvist, you know better than any of us what fails first in real-time systems under load. If any of this interests you, your eyes on it would be hugely valuable, in whatever form suits you.
3. **Go/no-go checkpoint at the end of December 2026** (see [`roadmap-2027.md`](roadmap-2027.md)). If the core loop isn't at parity and meeting ≤ 3 s p95 in self-play, we stop and reassess, including going back to the old stack.

I'd rather hear the strongest objections now than in December. tsjokvist especially, since you built the app that got us this far: what would make you say no?
