---
title: "Design sketch: world agents"
updated: 2026-10-07
---

# Design sketch: world agents

**Status:** to try, not decided ([decision log](decisions.md#2026-10-07-to-try-world-agents-hold-facts)). Prototype on Tin Valley behind `WORLD_AGENTS=on` in ex-tales-forge (PR linked below once open).

## Problem

The GM is the only memory of the world. Over a few turns it drifts: the prose prototype ([ex-tales-forge #38](https://github.com/whyse-ab/ex-tales-forge/pull/38)) turned the orc nest into harpies and priced the same inn room at 2, 3 and 8 silver, and NPCs forget what they promised. Putting more lore into the prompt makes it bigger, and anything that changes per session or turn can't sit in the cached prefix.

## Idea

Things in the world are Elixir processes that own their state and facts:

- **Person:** the one Character type ([character model](call-types.md#character-model)): player characters and NPCs alike, controlled by a player or by the GM. Holds OCEAN, mood, memories and promises.
- **Location:** nested, e.g. Valley Inn < Tin Valley village < Tin Valley region. Holds facts such as prices, who keeps the place, what threatens it.
- **Item**, and maybe **animal:** facts that travel with the thing (who owns it, what it does).

Before each turn Elixir asks the relevant agents for facts; the GM gets them in the per-turn part of the prompt and turns them into prose. Facts the GM invents come back in a typed field and are written to the agent that owns them, so the world remembers.

## Process model

- One `GenServer` per entity per session (`TalesForge.World.Agent`), started lazily the first time a turn needs it, stopped after an idle timeout. A session that is never played starts nothing.
- `TalesForge.World.Supervisor` (`DynamicSupervisor`) plus `TalesForge.World.Registry` (`Registry`, key `{session_id, entity_id}`). A crash restarts the agent from persisted state; it never takes the turn down (the turn goes on without that agent's facts).
- The existing Jido NPC agents (`NPCAgent`, `NPCRegistry`) already run one process per present NPC. Long term, the Person agent and the NPC agent should be the same process; the prototype keeps them apart to stay small.
- A turn talks to agents with `GenServer.call` on the same node: microseconds to a few ms. Agents never call the LLM themselves; a Person's gut reaction is a Jev call made for it by the turn (below).

## Persistence (Ash)

- Target: two Ash resources. `World.Fact` (session, entity id and kind, fact kind `fact | price | promise | memory`, text, source `pack | gm`, turn, timestamps; identity on session + entity + normalized text) and `World.EntityState` (session, entity id, mood and other small mutable state as a map).
- Pack facts are not copied per session: an agent starts from the adventure pack's definition and adds the session's rows on top.
- Writes happen in the turn's transaction (write-through), so a crashed agent or a restarted machine rehydrates exactly what the player saw. No periodic snapshots needed at this size.
- Prototype shortcut: the session's own facts and moods are a snapshot in `world_state["world_agents"]`, written in the turn transaction. No migration.

## Facts per turn

- Relevant agents: the location chain of where the player character is (room < village < region), the persons present, and the items the character holds.
- Order and budget: current location first, then persons present, then the parent locations; per entity pack facts first, then the newest GM facts. A hard budget (prototype: 12 facts, about 1,200 characters, ~300 tokens) keeps the per-turn section small. Older GM facts stay with the agent and come back when relevant.
- The facts go into the per-turn user message only, never into the narrator/rules/task/session-stable prefix, so the cached prefix ([ex-tales-forge #34](https://github.com/whyse-ab/ex-tales-forge/pull/34)) is unchanged and the prefix-stability test still guards it.

## Writing facts back

- The GM reply schema gets a `new_facts` array of `{about, kind, text}` (only when the flag is on). As with the other bookkeeping fields there are no `maxLength`/`maxItems` in the schema, because they turn off xAI prompt caching ([#36](https://github.com/whyse-ab/ex-tales-forge/pull/36)); caps are applied when the reply is parsed (prototype: 3 facts, 160 characters each).
- Elixir validates each one: `about` must be an agent that was in this turn's set (`here` means the current location), `promise` only for persons, duplicates dropped, a new price for something that already has a price is rejected (the pack wins). Valid facts go to the owning agent and are persisted with the turn.
- `gm_system.txt` tells the GM to treat the world facts as true and to record only new, lasting facts (a price it names, a promise an NPC makes, a named person or place).

## The Brenna reaction

The Jev NPC reaction prototype is a Person agent's System 1: before the GM call each present person gets one Jev call with its OCEAN, its mood (held by the agent) and what the player character visibly said or did, and returns a typed reaction (emotion, intensity, stance hostile..friendly, confidence). The agent keeps the new mood; the GM gets one line per person in the per-turn section.

## Call types per step

| Step | Call type | Expected cost and time |
| --- | --- | --- |
| Start or find agents, collect facts (`turn.world_facts`) | function | free, < 5 ms |
| Person reaction (`npc_reaction`) | jev | ~$0.00004 per person per turn, ~70–450 ms, concurrent, short timeout |
| GM narration (`gm`) | llm | +~150–300 uncached input tokens per turn, + a few dozen output tokens when it writes facts |
| Validate and write back new facts (`turn.world_writeback`) | function | free, < 5 ms |

The Jev reaction is the only added step on the critical path; everything else is Elixir.

## Related

- [Call types](call-types.md): the call-type rule and the Character model this builds on.
- [Jev as player-intent gate (tales-forge-docs #24, draft)](https://github.com/whyse-ab/tales-forge-docs/pull/24): the gate validates the player's intent before the turn; with world agents it can ask them, as plain function calls, whether a target exists here or what something costs, instead of trusting the GM.
