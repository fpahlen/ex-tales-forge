---
title: "Plan: one Character entity for player characters and NPCs"
updated: 2026-10-07
status: plan (no code; waiting for Fredrik's OK)
---

# Plan: one Character entity for player characters and NPCs

**Ask** (Fredrik via Case, 2026-10-07): player characters (PCs) and NPCs become one `Character` entity, with one schema and one process. They share the same attributes: stats, skills, OCEAN, Maslow level, current concerns, memory and inventory. Only the **controller** differs: a player or the GM. This plan turns the existing decision [One Character type](decisions.md#2026-10-07-one-character-type) into steps. It adds no new decision entry; that comes with the OK.

**Builds on:** ex-tales-forge `main` after [#47 Remove Ash](https://github.com/whyse-ab/ex-tales-forge/pull/47), which is open and not merged. The plan assumes #47 lands. Two places depend on it:
- **Admin.** The new Character admin form follows #47's plain Ecto forms (`to_form` + changesets, `NpcInstance.admin_changeset/2`).
- **Persistence.** The "Persistence (Ash)" section of [design-world-agents](design-world-agents.md) is replaced here by plain Ecto.

If #47 doesn't land, step 2 needs an Ash resource and an AshPhoenix form instead. That would cost about +150 LOC, and nothing else changes.

## 1. Today: two different shapes

| | Player character | NPC |
|---|---|---|
| **Stored** | The `"character"` map in `game_sessions.world_state`, with no table of its own | An `npc_instances` row (`game_session_id`, `npc_id` slug, `personality` = the whole authored definition, `runtime_state` map, `disposition` float that the game never uses) |
| **Authored from** | `World.default_world_state/0` (Elara Voss, hardcoded). `Pack.materialize/1` copies her into tin_valley | Pack files: `priv/adventures/tin_valley/npcs/*.json` + `*.md` (front matter: name, race, role, default location) and `priv/npcs/*.json` (Crossroads: Marta, Henrik) |
| **Stats** | `stats` STR..CHA | none |
| **Skills** | `skills` raw 0–3, plus a stat bonus at roll time (`Mechanics.effective_skill_level/2`) | `skills` raw 7–8, used only by `Train` (a trainer needs raw ≥ the PC's raw + 5) |
| **OCEAN** | none | `motivations.personality_traits` (0–10 ×5) |
| **Maslow** | none | `motivations.primary_need` as text (Marta: "safety"), never read by code |
| **Concerns** | none | `runtime_state.current_concern` (one map: focus, priority, since_tick), plus `motivations.current_concerns` (a list of text) in some files |
| **Memory** | none | `runtime_state.memories` (who, tick, what, felt, summary, secret), capped at 20; the GM sees the last 5 |
| **Inventory** | `inventory` list + `coins` map | `stock` list with `price_copper` |
| **Health and learning** | `wounds`, `wound_max`, `vitality`, `learning_points`, `learning_failures` | none |
| **Mood** | none | Kept in three places: `runtime_state.mood`, the Jido `NPCAgent` state, and `world_state["npc_moods"]` (Jev reactions). There is also a snapshot copy in `world_state["npc_state"]` |
| **Relationship** | none | `runtime_state.relationship_score`, one float toward "the player" |
| **Process** | `PlayerSessionAgent` (Jido): only turn count and entries, no character state | `NPCAgent` (Jido), one per **present** NPC, kept in sync by `NPCRegistry.sync/1` and restored at boot by `NPCRecovery`. Signals from `NPCSignals`: `world.time.passed`, `player.talked_to`, `conversation.message` (actions in `Actions.NPC.*`) |
| **World agents** (`WORLD_AGENTS`, off on both apps) | The PC's location chain and held items become agents; the PC itself is not a Person agent | `World.Agent` with kind `:person`, a separate GenServer from `NPCAgent`, holding facts from `world_agents.json` and `world_fact` events, with mood read from `npc_moods` |
| **Jev reactions** (`NPC_REACTIONS`: on on playtest, off on prod) | Input only: what the PC said or did, and how the attempt came across | One Jev call per present NPC (at most 4), reading OCEAN + mood and writing `npc_moods` |
| **Per-turn writes** | `TurnProcessor` rewrites `world_state["character"]` in the turn Multi | `NPC.persist_tick_multi/3`, `record_memory/4`, `persist_stock_updates/2`, `adjust_concern/3` |

**Rows today** (read-only count on 2026-10-07, after #46 was deployed):

| | game_sessions (= PCs) | npc_instances | NPC slugs | turns |
|---|---|---|---|---|
| prod (tales-forge v43) | 5, all tin_valley, all "Elara Voss" | 15 | prospector, guild_steward, innkeep ×5 | 3 |
| playtest (tales-forge-playtest v31) | 19 (18 tin_valley, 1 crossroads), all "Elara Voss" | 54 | the same three ×18 | 82 |

Every PC map has the same set of keys, and every `npc_instances.runtime_state` has the same keys. That makes the backfill mechanical: 24 PC rows and 69 NPC rows. The one playtest Crossroads session has no NPC rows. Two playtest sessions have `npc_moods`.

## 2. Target

### Schema: one `characters` table (plain Ecto)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `game_session_id` | fk, `on_delete: :delete_all` | Characters live in one session for now (see open question 1) |
| `slug` | string | `innkeep`, `elara_voss`, … Unique per session |
| `controller` | `player` \| `gm` | The only difference between a PC and an NPC |
| `controller_ref` | string, nullable | Who plays it: a player id later; null for `gm` |
| `origin` | map | `{pack, adventure_id, definition_id}` or `{created, …}`, so a pack edit can be traced |
| `definition` | map | Immutable copy of the authored source, the `front_instances.definition` pattern (today's misnamed `npc_instances.personality`) |
| `name`, `race`, `role`, `location_id` | string | |
| `stats` | embedded (STR..CHA) | NPCs get stats too; default 10 when the pack has none, so one roll formula serves both |
| `skills` | map skill → raw | One scale and one roll formula. `Train` keeps its gap rule |
| `ocean` | embedded, 5 × 0–10 | Fixed for the whole session |
| `maslow_level` | enum: physiological, safety, belonging, esteem, self_actualisation | Plus `maslow_since_tick` |
| `concerns` | embeds_many, 0–3 | text, focus, priority, since_tick, status. Replaces both `current_concern` and `current_concerns` |
| `memories` | embeds_many | who, tick, kind (`memory` \| `promise` \| `reaction` \| `fact`), text, felt, secret. Capped in code (20), as today |
| `inventory` | embeds_many | id, name, quantity, `price_copper` (nil = not for sale). NPC `stock` becomes inventory with prices |
| `coins` | map | |
| `wounds`, `wound_max`, `vitality`, `learning_points`, `learning_failures` | | NPCs get the same fields (unused at first) |
| `mood` | string | **One place.** Jev reactions, the agent and the GM all read it here |
| `relationships` | map other_slug → score | Replaces `relationship_score`, which only tracked "the player"; a GM companion can like an NPC too |
| `runtime` | map | Small engine state that isn't a lever: initiative flags, concern_wait_ticks, resources, public_facts, since_tick |
| `lock_version`, timestamps | | Optimistic locking for chronicler vs turn writes (architecture.md's concern) |

`world_state` keeps `player_character_id` and `present_npcs` (later renamed `present_character_ids`). It loses `character`, `npc_state` and `npc_moods`.

One `Characters` context replaces the character parts of `NPC`, plus the `world_state["character"]` reads and writes in `TurnProcessor`, `Context`, `World` and `Prices`.

To keep the first PRs small, `Mechanics`, `Inventory`, `Train` and `Vitality` keep working on a plain map: `Character.to_sheet/1` / `apply_sheet/2`. They move to the struct later, or never.

### Process: one `Characters.Agent` per present character

- **One agent type.** A Jido agent per character that is *present* in a running session: the PC, which is always present, plus the NPCs at its location. It replaces `NPCAgent` and folds in `World.Agent`'s `:person` kind. Locations and items stay `World.Agent`.
- **Registry and recovery.** `NPCRegistry` becomes `Characters.Registry` (same sync on `present_*`), and `NPCRecovery` restores the agents of active sessions.
- **The agent holds** the hot copy of the levers: mood, concerns, Maslow level and recent memory. The DB row is the source of truth; writes go through in the turn Multi, as today.
- **What the controller decides:** who produces the character's next action.
  - `player`: the LiveView, or the persona runner, which is just another player client. It submits text, and the turn runs as today: intent (Jev) → rules (Elixir) → reactions (Jev) → GM narrates.
  - `gm`: nobody types. The character acts through what NPCs have today: the Jev gut reaction (System 1), initiative from concerns, and the GM's narration. A GM-controlled character never gets a turn of its own; it acts inside another character's turn, or in the world tick.
- **AFK player** (matters for parties; single player just pauses):
  - After N minutes or N party turns without input, the controller flips to `gm` with `runtime.afk_from = "player:<id>"`. The GM plays the character conservatively: it follows the party, defends itself, and makes no big decisions.
  - When the player sends anything, control goes back. With the same data and calls, that is the "GM plays an absent player's character" goal from the decision.
- **GM-controlled companion:** `controller: gm` plus membership in the player's party group (Tuckman phase on the group). The player gives orders by talking to the companion, which is a normal intent with the companion as target. The companion's Jev reaction, concerns and party phase decide whether it obeys. No new call types.

### Seeding from packs

- **Pack NPCs:** `Characters.seed_from_pack/2` builds Characters from JSON + md, like `NPC.seed_from_pack/2` today.
  - OCEAN comes from `motivations.personality_traits`.
  - Maslow comes from a new `maslow` key. The default is `safety`, mapped from `primary_need` where present.
  - Concerns come from a new `concerns` list, or from `current_concern` / `current_concerns`.
  - Inventory comes from `stock`.
  - Stats default to 10.
  - `Pack.load/1` validates the new keys and fails fast, as it does for exits.
- **The PC:** Elara moves from `World.default_world_state/0` into a pack file, `priv/adventures/<id>/characters/elara_voss.json`, with the same keys as an NPC file plus her sheet. She also needs authored OCEAN, Maslow and concerns: the PC has none today (open question 2).
- **Character creation:** the [port plan](character-creation-port.md) "where is the character stored" question is answered by this table. A created character is a `characters` row with `origin: created`.

## 3. Levers mapped onto Character

| Design lever ([world agents: character levers](design-world-agents.md#character-levers-design-not-built)) | On Character | Notes |
|---|---|---|
| OCEAN | `ocean` | Exists for NPCs; new for PCs. The Jev reaction reads it, as today |
| Maslow level | `maslow_level`, `maslow_since_tick` | New. Typed events drop it at once (raid, armed stranger, no coin); calm turns raise it by one. Jev state line: "Right now she needs: safety" |
| Current concerns | `concerns` (0–3) | Replaces `current_concern`. Events advance or resolve them; the extraction call may propose one, validated like a fact |
| Memory | `memories` + `world_fact` events about the character | One list per character, filtered by personality (open question 6) |
| Mood | `mood` | Fixes the three-copies problem |
| Group phase (Tuckman) | **Not on Character.** A later `groups` + `group_members` table (party, gang, council); a member's agent reads the phase | The AFK and companion rules use it once it exists |
| World-agent Person | The Character agent itself | Facts (`world_fact` events) stay events. The Person agent is no longer a second process |

## 4. What breaks, and how each piece is kept safe

- **GM prompts and the cache prefix:**
  - `Context.session_stable_section/1` reads only the PC's name and race. It must render **byte-identical** text from the Character.
  - The per-turn sections (`NPC.format_gm_sections/2`, the intent context with `player_inventory` and NPC stock, `NpcReactions.prompt_section/1`, world facts) must also render identically in phase 2.
  - Guard: golden tests on whole prompts for a fixed session, next to `prompt_prefix_test.exs`. The #34 message order and the prefix-stability test stay unchanged, and no lever goes into the prefix.
- **Admin forms:**
  - `NpcLive.Show` (#47's Ecto form) becomes `CharacterLive.Show` for any character, with the same changeset rule: only levers and runtime are editable, never slug, session or controller.
  - The session page's world-state JSON no longer contains the character, so it links to the PC's Character page instead. The NPC definition pages stay as they are (read-only pack files).
- **Persona runner:**
  - `Playtest.PlayerView` reads `world["character"]`; it switches to the PC Character.
  - The runner submits as the player, which proves the `player` controller works with a non-human client. `PLAYTEST_RUNNER_ENABLED` is unchanged.
- **Jev reactions (`NpcReactions`):**
  - The reaction reads `ocean` and `mood` and writes `mood` on the Character instead of `npc_moods`.
  - It runs for present `gm`-controlled characters only (still at most 4), so a PC under the GM (AFK) reacts too.
  - Cost is unchanged per character.
  - Prompt input stays player-visible only.
- **World agents:**
  - `World.collect/2` gets persons from Characters.
  - `World.Agent` drops the `:person` kind once the Character agent serves facts.
  - `WORLD_AGENTS` stays off.
- **WorldSim people tick:** `NPC.sim_people/1` and `persist_tick_multi/3` move to Characters, for `gm` characters only.
- **Play UI:** the character panel and NPC panel (`PlayComponents`, `PlayLive`) read Characters.
- **Tests:**
  - About 20 test files touch `world_state["character"]` or NPC instances. The biggest are vitality (33 references), inventory, competence and train (10–15 each), admin, prompt_prefix and pack.
  - Most go through `to_sheet/1` unchanged. Fixtures that build `world_state["character"]` by hand need a helper.
  - `mix e2e.smoke` (Marta, the chalk, the square) must stay green.
- **Flag constraints:** mood fade and `WORLD_AGENTS` stay off on playtest; the plan does not touch them.

## 5. Phased rollout

A flag is sensible for the read switch, because it changes what the GM sees. The write side uses dual-write instead of a flag.

| Phase | What | Flag | LOC (rough) | Risk |
|---|---|---|---|---|
| 0 | `Character` struct, embedded schemas, `to_sheet/1`, pack keys (`maslow`, `concerns`) + validation; Elara as a pack file. No behaviour change | none | +350 | low |
| 1 | `characters` table and backfill migration (24 + 69 rows; it aborts if a session's PC map is malformed). **Dual-write:** every PC/NPC write also writes the Character in the same Multi, and a consistency check (mix task + admin badge) diffs the two | none | +550 | low–medium (Multi size, write drift) |
| 2 | **Reads from Characters:** Context, NPC prompt sections, NpcReactions (mood on the Character), PlayerView, PlayLive, admin `CharacterLive`. Golden prompt tests must stay byte-identical. Turn it on on playtest first and compare persona runs (Jev scores, cache hit rate) before prod | `CHARACTERS=on` (default off) | +500 / −250 | medium (prompt drift, cache misses) |
| 3 | **One process:** `Characters.Agent` replaces `NPCAgent`; the PC gets an agent; registry and recovery are renamed; the controller field drives initiative. Stop dual-write; drop `character`, `npc_state` and `npc_moods` from `world_state`; `npc_instances` becomes read-only | `CHARACTERS=on` required | +400 / −700 | medium–high (agent lifecycle, recovery at boot) |
| 4 | Drop `npc_instances` with the row-check pattern from #47 (abort unless reviewed); remove the flag and the old `NPC` paths | none | −400 | low |
| Later | Lever behaviour (Maslow events, concern resolution, personality-filtered memory), groups + Tuckman, AFK handoff and companions (need parties), a character library across sessions (needs accounts) | own plans | — | — |

**Total for phases 0–4:** about +1,800 / −1,350 LOC over 5–7 PRs. The net is small; the value is one shape for PCs and NPCs.

**Rollback:**
- Phases 0–2: turn the flag off; the old fields are still written.
- Phase 3 and later: roll back the release and run the migration `down`. `npc_instances` and `world_state` are kept until phase 4 for exactly this reason.

## 6. Open questions for Fredrik

1. **Scope:** do characters live in one session (recommended now), or in a player's library across sessions? A library needs accounts and ties into the character-creation port.
2. **PC levers:** does the PC get authored OCEAN, Maslow and concerns? Are they visible to the player on the sheet, or hidden and used only when the GM controls the PC?
3. **AFK:** in single player, pause (recommended), or let the GM take over after a timeout? For parties, what timeout, and how much may the GM decide for an absent PC?
4. **Companions:** should a GM-controlled companion obey orders by default, or decide by reaction, concerns and party phase (proposed)?
5. **Skill scale:** keep NPC raw skills (7–8) with default stats (10), or rescale them to the PC scale? Trainers depend on the gap.
6. **Memory:** an embedded list on each character (simple), or a shared memories/facts table that matches the world-fact events (better for queries and admin)?
7. **Controller values:** only `player | gm`, with the persona runner counting as a player (proposed), or a third `bot` value?
