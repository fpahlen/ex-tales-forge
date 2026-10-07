---
title: "Design sketch: world agents"
updated: 2026-10-07
---

# Design sketch: world agents

**Status:** to try, not decided ([decision log](decisions.md#2026-10-07-to-try-world-agents-hold-facts)). Prototype on Tin Valley behind `WORLD_AGENTS=on` (default off): round 1 in [ex-tales-forge PR #40](https://github.com/whyse-ab/ex-tales-forge/pull/40) (merged 2026-10-07, off in production and playtest), round 2 in [PR #42](https://github.com/whyse-ab/ex-tales-forge/pull/42) (merged 2026-10-07, still off in production and playtest).

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

## First prototype results (2026-10-07, 10 local 5-turn runs)

- **Lore:** no drift in the 4 world-agent runs (orcs only, Osric is Guild), against 3 contradictions in the 4 Lotta runs without facts (bandits, "Osric Vane's old nest"). The sample is small.
- **Prices:** not fixed. The GM still said 2c for stew or bread with 5c / 1c in its facts. Prices are structured data, so next try: Elixir quotes the price (from the handler, into the GM struct) instead of asking the GM to copy it.
- **Write-back:** the GM almost never fills `new_facts` (1 attempt in 20 turns), and no NPC made a promise, so promise memory is only unit-tested. Next try: Jev or Elixir extracts new facts from the narrative rather than relying on the GM.
- **Cost and latency:** facts add ~320 uncached GM input tokens per turn (~$0.0004). The Jev reaction adds ~110–190 ms on the critical path; the function steps take ~1 ms. Turns 2+ cache: 13/16 hits, no regression (the prefix is byte-identical by test).
- **Jev scores** rose, mostly because of the reactions: Lotta off 3.47/3.57 → 4.15/3.81, Paul off 3.79/4.11 → 4.13/4.41.

## Round 2 (2026-10-07)

Two changes, following round 1:

- **Prices from code** (`World.Prices`, function step `turn.prices`). Price facts carry `item`, `copper` and `aliases`. When the player's words mention a priced thing here, the GM's per-turn data gets `Price: Bowl of stew, 5 copper`. When the player pays (a statement, not a question: pay or buy, handing over coins, or naming an amount), the server charges the coins and writes `Purchase: Bowl of stew, 5 copper, paid (server)`. The amount picks the items ("three silver and five copper" = room + stew). The GM is told to use those amounts.
- **Facts read from the narration** (`World.Extract`). After the turn, off the critical path, one small LLM call (purpose `fact_extract`, call_type `llm`, conv id `<session>:facts`) returns `{about, kind, text}` facts and promises. Elixir validates them as before (and also rejects a second price for something any agent of the turn already prices), stores them as hidden `world_fact` session events, pushes them to the running agents and rehydrates them on restart. The GM's `new_facts` field is dropped. Persistence is still a prototype shortcut; the Ash `World.Fact` resource above remains the target.

| Step | Call type | Measured |
| --- | --- | --- |
| Prices (`turn.prices`) | function | < 1 ms |
| Extraction (`fact_extract`) | llm | ~$0.0010 per turn, ~1.1k input / ~34 output tokens, 550–750 ms, after the turn |
| Validate and store (`turn.world_writeback`) | function | ~3 ms, after the turn |

## Round 2 results (2026-10-07)

6 local 5-turn runs (Lotta ×3, Paul ×3) with `WORLD_AGENTS=on`, compared with round 1's 4 world-agent runs; ~$0.34 xAI.

| | Round 1 (4 runs) | Round 2 (6 runs) |
| --- | --- | --- |
| Wrong price in the narration | 2 | 0 |
| Lore errors | 0 | 0 |
| Facts and promises kept per run | GM: 1 attempt in 20 turns | 2–6 (avg 3.2), 8 promises in total |
| GM input tokens (avg) | 9,835 | 9,784 |
| GM latency p50 | 4.2–5.5 s | 3.3–5.5 s |
| GM $/turn | $0.0070 | $0.0070 |
| Extraction $/turn | — | $0.0010 |
| Game $/turn (incl. scene) | $0.0089 | $0.0091 |
| GM cache hits, turns 2+ | 13/16 | 20/24 |
| Jev session, Lotta | 4.15, 3.81 | 3.39, 3.58, 3.62 |
| Jev session, Paul | 4.13, 4.41 | 4.33, 4.49, 3.83 |

- **Prices:** every price in the narration matched the list ("Five copper for the bowl", "Three silver for the room, paid now").
- **Charging:** the first runs used a looser payment rule and missed payments the narration showed. Replaying all recorded player lines through the final rule charges 5 of 6 payments exactly (one 1c bread missed). The final-code run charged both its payments, and the GM wrote "the copper already taken".
- **Extracted, for example:** Brenna promised "Stew's on the house tonight if it keeps you from pressing me further" and "Room's yours; up the narrow stair, second door on the left"; Tin Valley got "The orc nest is a half-day's hard walk east of the market square…". Restated prices were rejected as conflicts (the pack wins).
- **Weak spots:** near-duplicate promises across turns, one rule filed as a promise, and the extraction runs on the tier-1 model; a cheaper fast model should cut its ~$0.001 per turn. The Lotta Jev scores are lower than in round 1, but run-to-run spread is large at this sample size; nothing in the per-turn data points to the prices or facts.

## Character levers (design, not built)

**Principle: few levers, emergent behaviour.** A person has four levers and a group has one. Elixir holds them on the agent and changes them from typed events. Each turn the Jev reaction reads them, and the GM gets the result as per-turn facts. Nothing new goes into the cached prefix, and there are no new LLM calls.

| Lever | Held by | Changes | Feeds the Jev reaction | Feeds the GM per-turn facts |
| --- | --- | --- | --- | --- |
| **OCEAN** (0–10 ×5) | person, from the pack | never within a session | in the state text, as today: how strongly she reacts and to what | not sent; the GM sees its effect through the reaction |
| **Maslow level** (physiological, safety, belonging, esteem, self-actualisation) | person: the lowest unmet need | drops at once on a threat to a lower need (raid, armed stranger, no coin); rises one level after a few calm turns with that need met | "Right now she needs: safety" in the state; threats to that need weigh most | one line: "Brenna: needs safety (the raids)" |
| **Current concerns** (1–3 short goals) | person; pack defaults, e.g. Brenna wants returning, happy, safe customers and an inn kept out of the Guild feud | events advance, threaten or resolve them; the extraction call may propose a new one, validated like a fact; resolved concerns drop | listed in the state, plus one Score question: does this help or threaten her concerns? It drives the stance | "wants: …" facts on the person, kept within the facts budget |
| **Memory** | person: facts, promises and recent reactions involving the player character (round 2) | added after each turn by extraction and the reaction; old items fade from the prompt but stay on the agent | the 2–3 most relevant memories about this player character | promises and facts, as today ("promised: …") |
| **Group phase** (Tuckman: forming, storming, norming, performing) | group agent: party, bandit gang, village council; members are persons | shared events, below | a member's state includes the group's phase: storming makes them prickly with each other, performing makes them steady and confident with outsiders | one line per group present: "Bandit gang (storming): quarrel over the split" |

**Group phase transitions** come from shared events in the session log, counted by Elixir, not judged by an LLM. The event kinds are tagged by rules or by the extraction call (`conflict`, `shared_success`, `shared_failure`, `betrayal`, `member_joined`, `member_lost`):

- forming → storming: the first conflict inside the group (blame, a loot dispute, a failed shared check).
- storming → norming: that conflict is resolved (an agreement, a shared success, one member backing another).
- norming → performing: a few shared successes in a row with no new conflict.
- any phase → storming: betrayal, a new member or the loss of the leader. A party that disbands ends.

Emergence comes from the combination. A safety-starved Brenna, a storming bandit gang in town and a player character who keeps a promise produce different scenes, and nobody scripts them.

## Related

- [Call types](call-types.md): the call-type rule and the Character model this builds on.
- [Jev as player-intent gate (tales-forge-docs #24, draft)](https://github.com/whyse-ab/tales-forge-docs/pull/24): the gate validates the player's intent before the turn; with world agents it can ask them, as plain function calls, whether a target exists here or what something costs, instead of trusting the GM.
