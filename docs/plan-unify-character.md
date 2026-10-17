---
title: "Plan: one Character entity for player characters and NPCs"
updated: 2026-10-07
status: plan; seven answers confirmed by Fredrik 2026-10-07; phase 1 deployed and backfilled 2026-10-07
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
| `controller` | `player` \| `gm` \| `bot` | The only difference between a PC and an NPC (`bot` = persona runner) |
| `controller_ref` | string, nullable | Who controls it right now: a player id or persona id; null for `gm` |
| `owner_player_id` | nullable | Who the character belongs to, ready for carry-over between sessions (decision 1) |
| `origin` | map | `{pack, adventure_id, definition_id}` or `{created, …}`, so a pack edit can be traced |
| `definition` | map | Immutable copy of the authored source, the `front_instances.definition` pattern (today's misnamed `npc_instances.personality`) |
| `name`, `race`, `role`, `location_id` | string | |
| `stats` | embedded (STR..CHA) | NPCs get stats too; default 10 when the pack has none, so one roll formula serves both |
| `skills` | map skill → raw | One scale and one roll formula. `Train` keeps its gap rule |
| `ocean` | embedded, 5 × 0–10 | Fixed for the whole session |
| `maslow_level` | enum: physiological, safety, belonging, esteem, self_actualisation | Plus `maslow_since_tick` |
| `concerns` | embeds_many, 0–3 | text, focus, priority, since_tick, status. Replaces both `current_concern` and `current_concerns` |
| memories | separate `character_memories` rows (decision 6) | Each row is one character's personality-filtered view of a shared event. The shared events table is the existing `session_events` (kind, actor, tick, location, payload, player_aware): kind (`memory` \| `promise` \| `reaction` \| `fact`), text, felt, salience, secret. The prompt shows the top few, as today |
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

> **Superseded (2026-10-08):** there will be no per-character agent. Characters are plain data inside one process per world (`World.Instance`), and an NPC that needs to think something through gets a short-lived Task. Phase 3 below changes to match. See the [decision](decisions.md#2026-10-08-stateful-world-four-design-answers) and [Design: persistent world state, §4](design-stateful-world.md#4-processes-and-plain-data).

- **One agent type.** A Jido agent per character that is *present* in a running session: the PC, which is always present, plus the NPCs at its location. It replaces `NPCAgent` and folds in `World.Agent`'s `:person` kind. Locations and items stay `World.Agent`.
- **Registry and recovery.** `NPCRegistry` becomes `Characters.Registry` (same sync on `present_*`), and `NPCRecovery` restores the agents of active sessions.
- **The agent holds** the hot copy of the levers: mood, concerns, Maslow level and recent memory. The DB row is the source of truth; writes go through in the turn Multi, as today.
- **What the controller decides:** who produces the character's next action.
  - `player`: the LiveView, or the persona runner, which is just another player client. It submits text, and the turn runs as today: intent (Jev) → rules (Elixir) → reactions (Jev) → GM narrates.
  - `gm`: nobody types. The character acts through what NPCs have today: the Jev gut reaction (System 1), initiative from concerns, and the GM's narration. A GM-controlled character never gets a turn of its own; it acts inside another character's turn, or in the world tick.
- **AFK player** (matters for parties; single player just pauses):
  - After N minutes or N party turns without input, the controller flips to `gm` with `runtime.afk_from = "player:<id>"`. The GM plays the character conservatively: it follows the party, defends itself, and makes no big decisions.
  - When the player sends anything, control goes back. With the same data and calls, that is the "GM plays an absent player's character" goal from the decision.
- **GM-controlled companion:** `controller: gm` plus membership in the player's party group (Tuckman phase on the group). The player gives orders by talking to the companion, which is a normal intent with the companion as target. The companion's Jev reaction, its concerns and the party's phase (read from the party group, not stored on the companion) decide whether it obeys. No new call types.

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
| Group phase (Tuckman: forming, storming, norming, performing, adjourning) | **Not on Character.** The phase is a property of the Group (party, gang, council) in a later `groups` table. A Character only references its membership(s) through `group_members`, and a member's agent reads the phase from the group | The AFK and companion rules use it once it exists |
| World-agent Person | The Character agent itself | Facts (`world_fact` events) stay events. The Person agent is no longer a second process |

## 4. What breaks, and how each piece is kept safe

- **GM prompts and the cache prefix:**
  - `Assemble.session_stable_section/1` reads only the PC's name and race. It must render **byte-identical** text from the Character.
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
| 3 | **One process** (*superseded 2026-10-08: one process per world, not per character; see the note in section 2*): `Characters.Agent` replaces `NPCAgent`; the PC gets an agent; registry and recovery are renamed; the controller field drives initiative. Stop dual-write; drop `character`, `npc_state` and `npc_moods` from `world_state`; `npc_instances` becomes read-only | `CHARACTERS=on` required | +400 / −700 | medium–high (agent lifecycle, recovery at boot) |
| 4 | Drop `npc_instances` with the row-check pattern from #47 (abort unless reviewed); remove the flag and the old `NPC` paths | none | −400 | low |
| Later | Lever behaviour (Maslow events, concern resolution, personality-filtered memory), groups + Tuckman, AFK handoff and companions (need parties), a character library across sessions (needs accounts) | own plans | — | — |

**Status, 2026-10-07:** phases 0 and 1 (setup) are **merged and deployed** as [ex-tales-forge #48](https://github.com/whyse-ab/ex-tales-forge/pull/48) (main `326c8ae`, production v45, playtest v33; see the [decision](decisions.md#2026-10-07-characters-phase-1-merged-and-deployed-48)):
- the `characters` and `character_memories` tables;
- pack levers with validation, and Elara in the packs;
- new sessions write characters (the persona runner as `bot`), but nothing reads them;
- a golden test keeps the GM prompts byte-identical.

**Status update, 2026-10-07 (afternoon):** phase 1 is complete. It was **merged, deployed and backfilled** as two PRs ([decision](decisions.md#2026-10-07-characters-defaults-rescale-backfill-and-double-write-50-51)):
- [#50](https://github.com/whyse-ab/ex-tales-forge/pull/50) (main `8d8efc3`): `Characters.Defaults` ([section 7](#7-defaults-from-class-race-standing-and-occupation-jev-for-descriptions)) and NPC skills on the PC scale through `derive` blocks. The golden prompts did not change, because NPC skills never reach the GM prompt; only `Train` uses them.
- [#51](https://github.com/whyse-ab/ex-tales-forge/pull/51) (main `e867f16`, production v48, playtest v36):
  - the backfill (`Characters.backfill/0`);
  - the double-write after every turn (`Characters.mirror/1`), done after the turn rather than inside the turn's Multi; failures are logged and the next turn re-syncs.
  - The consistency-check mix task and admin badge from the table above are not built yet.
- **Backfill:** production 20 rows (5 PCs + 15 NPCs) and playtest 85 rows (22 PCs + 63 NPCs). A second run inserted 0 on both.
- Existing sessions keep the NPC skills they were seeded with; only new sessions get the rescaled values.
- Nothing reads `characters` yet.

Next: phase 2, the read switch behind `CHARACTERS=on`.

**Total for phases 0–4:** about +1,800 / −1,350 LOC over 5–7 PRs. The net is small; the value is one shape for PCs and NPCs.

**Rollback:**
- Phases 0–2: turn the flag off; the old fields are still written.
- Phase 3 and later: roll back the release and run the migration `down`. `npc_instances` and `world_state` are kept until phase 4 for exactly this reason.

## 6. Decisions (confirmed by Fredrik, 2026-10-07)

Case suggested answers to the seven open questions. Fredrik confirmed all seven on 2026-10-07 ([decision](decisions.md#2026-10-07-one-character-entity-the-seven-design-answers)).

1. **Scope:** characters live **per session for now**, but the schema is ready for a character to belong to a player and carry over. Concretely: `owner_player_id` (nullable) and `origin`, and nothing assumes one session forever. The persistent-world option stays open in the design. Options compared:

   | Option | Characters and world state belong to | Good | Costs |
   |---|---|---|---|
   | A. Per session (**chosen for now**) | One `game_session` | Small, matches today's data, easy cleanup (cascade delete), no accounts needed | Nothing outlives a session; a faction can't remember the player next time |
   | A+. Per session, owned by a player | A session, plus a nullable owner, so a character can be copied or moved into a new session | Carry-over without a world model; fits character creation and a library | Needs player accounts for the owner; the copy rules (what carries: skills, inventory, memories?) need deciding |
   | B. Persistent world instance | A long-lived `world` (e.g. "Tin Valley #3") that sessions join; characters, factions, facts and clocks live on the world | Needed for the [living world](design-world-agents.md#living-world-design-to-try): the world moves between sessions, factions remember, parties share one world | A new top-level entity; sessions become visits to a world; per-world ticks cost CPU (small); harder resets, moderation and data growth; migration of `world_state` from the session to the world |

   Phase 1 builds A with A+'s owner column. Moving to B later means adding `world_id` next to `game_session_id` and backfilling one world per existing session.
2. **PC levers:** PCs get OCEAN, a Maslow level and concerns, **visible on the character sheet**.
3. **AFK:** solo play pauses. In parties the GM takes over an absent PC after a timeout, and control goes back when the player returns.
4. **Companions:** a GM-controlled companion decides by its reaction, its concerns and its party's phase (read from the party group; the phase is not a character attribute). It does not obey orders by default.
5. **Skill scale:** NPC skills are **rescaled to the PC scale**. NPCs use the same raw values plus stat bonus and the same roll formula as PCs. The pack values move to that scale (now by deriving them from occupation tiers, see [section 7](#7-defaults-from-class-race-standing-and-occupation-jev-for-descriptions)): a master trainer still sits well above a starting PC. The trainer gap rule (`Train`, today raw + 5) is re-checked against the new values.
6. **Memory:** one **shared events table** (what happened, where, who was involved, who could perceive it) plus **per-character memory rows**: each character's personality-filtered view of an event (felt, salience, secret), pointing at the event. The shared table is the existing `session_events`, which already holds world facts and hidden events. It becomes world-scoped if option B lands.
7. **Controller:** `player | gm | bot`. The persona runner uses `bot`, so playtest characters are easy to tell apart in data and costs.

Effect on the phases: phase 0+1 (setup) adds `owner_player_id`, `controller` with three values, the shared events table and per-character memory rows. Rescaling NPC skills is a separate step after phase 1: it changes who can train whom (`Train`) and the skill values the GM sees, so it gets its own PR with the gap rule re-checked, and phase 1 keeps the GM prompts byte-identical. Nothing switches reads until phase 2.

## 7. Defaults from class, race, standing and occupation; Jev for descriptions

**Direction from Fredrik via Case, 2026-10-07**, recorded as a design direction in [decisions](decisions.md#2026-10-07-design-direction-derived-character-defaults-and-jev-for-descriptions). The sketch below is Case's proposal for how to build it; the details are not yet confirmed.

1. **Defaults are derived in pure Elixir** from class, race, social standing and occupation: stats, skills, OCEAN, Maslow level and concerns. The assumption is that people are reasonably skilled at their job and have a typical personality for their role.
2. **Notable characters are authored by hand as overrides** on top of the defaults, for example the reluctant king or the sour barkeep.
3. **A free-text description becomes a Character through one Jev call** (unstructured in, structured out). The same call serves **player character creation**: the player describes their character, Jev returns labels, and the defaults fill the gaps.

### 7.1 The derivation module: `TalesForge.Characters.Defaults`

The module is pure: no database and no AI. `derive(inputs, rules) :: character_attrs` returns the same attrs shape that `Characters.from_npc_instance/3` builds today. Because it is deterministic, it is cheap to test, and every result goes through `Character.changeset/2` and `Levers.validate!/2`.

**Inputs** (all labels from fixed lists):

| Input | Values (examples) | Notes |
|---|---|---|
| `race` | the world's races: human, elf, dwarf, gnome, halfling, half_elf | |
| `class` | the world's archetypes (warrior, thief, ranger, cleric, wizard, druid) or `none` | Most NPCs have no class: a barkeep is an occupation, not a class |
| `standing` | nobility, gentry, merchant, commoner, underclass | The five social classes from the old app and the `starting_wealth` table |
| `occupation` | innkeep, guild_steward, miner, prospector, guard, soldier, smith, farmer, merchant, priest, scholar, thief, ruler, … | One fixed list per world, with an `other` entry |
| `seniority` | apprentice, journeyman, master | Defaults to journeyman: "reasonably skilled at their job" |
| `seed` | hash of session id + slug (7.4) | Drives a small deterministic jitter, so two innkeepers differ but a character is stable on reload |

**Tables** (pack data, for example `rules/character_defaults.json` per world, loaded and checked fail-fast like `Pack`):

- **Race:** stat modifiers and skill bonuses (from `races.md`), and **OCEAN modifiers**. The race OCEAN table already exists in `worlds/*/rules/races.md`, for example Dwarf O −1, C +2, E −1, A −2, N −1.
- **Class:** stat emphasis (for example warrior STR +2, CON +1) and class skills.
- **Occupation:**
  - core skills (2–3) and secondary skills;
  - OCEAN offsets for the typical personality (innkeep E +2, A +1; guard C +2; scholar O +2);
  - a typical Maslow level;
  - 1–3 concern templates, each a fixed focus label with a text template and a priority;
  - a kit of inventory or stock.
- **Standing:**
  - coins, from `starting_wealth`;
  - a Maslow shift: underclass leans physiological or safety, nobility esteem;
  - kit quality, and social-skill adjustments such as etiquette for gentry and above.

**Rules, in order:**

1. **Stats:** start at 10, add the class emphasis, then the race modifiers, and clamp to 3–18.
2. **Skills:** occupation core skills at the seniority tier, using the world's tiers (Novice 1–5, Adept 6–10, Expert 11–15): apprentice 4, journeyman 8, master 12. Secondary skills get half of that; class skills get 3; then the race bonus.
   - **PCs** are then held to the starting rules: skills capped at 5, inside the point budget.
   - **NPCs** keep the professional values. This is how decision 5 (one skill scale) lands without hand re-authoring: a master trainer at 12+ sits more than 5 above any starting PC, which satisfies the `Train` gap rule.
3. **OCEAN:** start at 5, add the race modifier and the occupation offset, apply a jitter of ±1 from the seed (confirmed, 7.4), and clamp to 1–10, as `races.md` specifies.
4. **Maslow:** the occupation level, shifted by standing. The lower need wins, because a hungry noble is still hungry.
5. **Concerns:** the occupation templates plus at most one from standing, sorted by priority, at most 3. Each has `since_tick` set at seeding.

**Overrides merge on top.** `derive(inputs) |> Overrides.merge(authored)`, then validate:
- **Maps merge per key:** `stats.STR`, `skills.persuasion`, `ocean.agreeableness`.
- **Scalars replace:** name, Maslow level, mood.
- **Lists replace whole:** concerns and inventory.
- A skill set to `0` is removed. A missing key keeps the default.

A pack NPC file becomes `{"derive": {...inputs}, ...overrides}`. Today's authored fields simply become overrides, so nothing is lost. The `definition` keeps both parts, and `origin` records `derived_from` and which fields were overridden. Examples:

- **The sour barkeep:** `derive: {race: human, standing: commoner, occupation: innkeep}`, plus `ocean: {agreeableness: 2, neuroticism: 7}`, `mood: "sour"` and her own concerns.
- **The reluctant king:** `derive: {standing: nobility, occupation: ruler, seniority: master}`, plus `maslow: "belonging"` (against the esteem default), `ocean: {extraversion: 2}` and a concern "Escape the weight of the crown".

### 7.2 Description → Character: one Jev call

Jev's **state** is the free text: the player's description, or an author's NPC blurb. Its **questions** are fixed labels, all in one request, evaluated in parallel:

| Field | Question type | Labels |
|---|---|---|
| race, class, standing, occupation | Choice | The world's lists, each with `other` or `none` (a Choice allows up to 255 options) |
| seniority | Score | apprentice < journeyman < master |
| OCEAN (5 questions) | Score | 5 levels, very low to very high, mapped to 1, 3, 5, 7, 9 |
| Maslow level | Choice | the 5 levels |
| concerns | Choice | About 30 fixed focus labels (money, debt, family, revenge, faith, duty, love, fame, safety, freedom, knowledge, escaping the past, …). Take up to 3 labels whose probability is above a floor |
| skill emphasis | Choice | The world's skill list ("what is this character best at?"); the top 1–2 get one tier up |
| unrealistic request | Noul | "Does the description ask for impossible power (maximum stats, godlike)?" Logged only; the limits apply anyway |

**How answers map onto fields:**

1. **Inputs first.** Gate race, class, standing, occupation and seniority on confidence. At or above the threshold (0.6 to start, confirmed in 7.4; confidence is logged and the threshold tuned after playtests), use Jev's label. Below it, use the world default: human, `none`, commoner, `other`, journeyman.
2. Run `derive/2` on those inputs.
3. **Levers next.** Confident OCEAN, Maslow, concern and skill-emphasis answers are applied as **overrides**, through the same merge as authored overrides. A field below the threshold keeps its derived default.
4. **Provenance.** Each field records its source (`jev`, `default` or `player`) and its confidence in `origin`. The sheet can then mark guessed fields, and tests can assert on them.
5. **If the call fails or confidence is low overall** (an error, a 429, a timeout, or most inputs below the threshold), use the defaults for the inputs that came back confident, or for everything. Creation never blocks on Jev.

**Jev limits that matter:**

- **Fixed labels only, no free text.** Jev answers only Choice (up to 255 options), Score (ordered levels) and Noul (yes or no). It cannot write a name, appearance, backstory or concern sentence, and returns no numbers outside the levels. As a result:
  - **Name:** the player types it, or Elixir picks one from the world's naming lists. Jev can only pick a name from candidates we supply, such as a roster or a pre-parser; names have no regex.
  - **Concern text:** the template for the chosen focus. The player's own sentence is kept in `definition` as the description.
  - **Backstory or appearance prose:** keep the player's text. An LLM call for prose is optional and is the founders' call (port question 1). It must not return structured fields, per [call types](call-types.md).
- **Questions are independent.** There is no cross-question consistency, so "wizard" plus "miner" can both come back. Elixir reconciles: class and occupation both apply, and derivation handles the mix.
- **Keep labels closed and described.** Each option's description is sent to Jev, so the descriptions should separate the options. Every list needs `other` or `none`.
- **Cost and speed are small.** Jev costs about $0.042 per 1M input tokens. A description of about 1k tokens with about 15 questions costs well under $0.001. Today's Jev calls (NPC reactions) take 210–340 ms. The model is pinned at jev-1.13.0.

### 7.3 Which phase

- **Derivation module, tables and the `derive` blocks in pack NPCs:** with the **skill-rescale PR** (the next one, alongside the backfill and dual-write). Deriving NPC skills from occupation tiers *is* the rescale, so the pack values aren't re-authored by hand. GM prompts change there (NPC skills), so that PR updates the golden fixtures on purpose and runs a playtest comparison.
- **Jev description → Character:**
  - **For authors:** first as a mix task (`mix characters.from_text`) that drafts an NPC file for an author to review. This can come right after the derivation module.
  - **For players:** with the [character creation port](character-creation-port.md#plan-2026-10-07-the-port-on-the-unified-character), PR 6. Update 2026-10-07: creation does **not** wait for phase 2. It writes `world_state["character"]`, which the game reads today, and the `characters` row through `seed_session`.

### 7.4 Decisions (confirmed by Fredrik, 2026-10-07)

Fredrik confirmed the four open points via Case on 2026-10-07 ([decision](decisions.md#2026-10-07-character-defaults-the-four-answers)):

1. **Label lists:** one **global base list** (races, classes, standings, occupations, concern focuses, skills) that **each world pack extends**. A pack can add labels; it doesn't remove the base ones.
2. **Jev confidence threshold:** **0.6** to start. Log the confidence of every answer and tune the threshold after playtests.
3. **Random variation:** yes, small, and **seeded per character**, so it's stable on reload. The seed is a hash of the session id plus the character key (slug). It replaces "the slug" as the seed in 7.1.
4. **Player edits:** the player can **edit everything Jev fills in, within the rules**: stats within the point budget, OCEAN, concerns, background and name. This follows the per-section "own input or AI assist" flow ([decision](decisions.md#2026-10-06-character-creation)). Changing an input such as race, class, standing or occupation re-runs the derivation. Fields the player has edited keep the player's value, recorded with source `player`.
