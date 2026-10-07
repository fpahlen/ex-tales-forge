---
title: Decision log
updated: 2026-10-07
---

# Decision log

Decisions made by the founders. Newest at the top. Each entry: date, decision, why, link to details. Changing a decision means adding a new entry that supersedes the old one.

Open questions waiting for a decision live in the [decision queue](../decisions/README.md); once decided, they are recorded here.

## 2026-10-07: Code docs: ExDoc's JavaScript allowed past the admin CSRF check

- **Decision:** ex-tales-forge PR #45 is merged and deployed to production and playtest. Files served from the docs folder at `/admin/code-docs` skip Plug's cross-origin JavaScript check. The admin login check is unchanged. Approved by Fredrik ("Yes, open the fix PR, merge it and deploy once CI is green").
- **Why:** after #44 the pages loaded but every ExDoc script got 403, so the sidebar was empty and search didn't work. The files are static and hold no tokens. The session cookie is SameSite=Lax, so another site's `<script>` request has no admin session and is still redirected to login. The tests now run with CSRF protection on, which the test helpers turn off by default and which hid the bug.
- **Details:** [ex-tales-forge PR #45](https://github.com/whyse-ab/ex-tales-forge/pull/45), [PR #44](https://github.com/whyse-ab/ex-tales-forge/pull/44)

## 2026-10-07: Code docs served admin-only at /admin/code-docs

- **Decision:** ex-tales-forge PR #44 is merged and deployed to production and playtest. Each release builds the ExDoc site in the Docker builder stage (about 4 MB in the image, ex_doc itself stays out of the release) and serves it at `/admin/code-docs` behind the admin login, with a "Code docs" link in the admin nav. Approved by Fredrik ("Yes, merge #44 and deploy").
- **Why:** the documented code (see coding standards) should be readable where we already work, without a local build, and not public.
- **Details:** [ex-tales-forge PR #44](https://github.com/whyse-ab/ex-tales-forge/pull/44), [Coding standards](coding-standards.md)

## 2026-10-07: Coding standards: documented, typed, tested, enforced in CI

- **Decision:** every module has a `@moduledoc` and every public function a `@doc` (with doctests where sensible) and a `@spec` checked by Dialyzer. Credo strict, `mix format`, ExDoc for a browsable docs site, tests for every change with coverage tracked. CI enforces format, Credo, Dialyzer, tests with coverage and the docs build, so failing PRs can't merge. Existing modules are backfilled gradually, starting with the core GM, Character/Person and world-agent modules. Fredrik's standard, relayed by Case.
- **Why:** humans may need to understand the code one day, including code written by coding bots.
- **Details:** [Coding standards](coding-standards.md), [ex-tales-forge PR #43](https://github.com/whyse-ab/ex-tales-forge/pull/43)

## 2026-10-07: Merge the runner fix and world agents round 2, world agents still off

- **Decision:** ex-tales-forge PR #41 (the playtest runner ignores a stale "turn finished" message, which caused a double turn 2) and PR #42 (world agents round 2: prices from code and facts read from the narration) are merged and deployed. `WORLD_AGENTS` stays off in production and playtest; `NPC_REACTIONS` stays on in playtest only. Approved by Fredrik ("Merge #41 and #42 and deploy").
- **Why:** the runner fix makes playtest runs complete and comparable. Round 2 costs nothing while the flag is off, and having it on main lets the next round build on it.
- **Details:** [ex-tales-forge PR #41](https://github.com/whyse-ab/ex-tales-forge/pull/41), [PR #42](https://github.com/whyse-ab/ex-tales-forge/pull/42), [Design sketch: world agents](design-world-agents.md#round-2-results-2026-10-07)

## 2026-10-07: World agents round 2: prices from code, facts read from the narration

- **To try (not a final decision):** Elixir, not the GM, quotes prices. When the player's words mention something with a listed price, the server puts "Price: Bowl of stew, 5 copper" in the GM's per-turn data, or charges the coins itself and says "Purchase: …, paid". After the turn, off the critical path, one small LLM call (`fact_extract`, conv id `<session>:facts`) reads the finished narration for new facts and NPC promises; Elixir validates and stores them for the owning agent. The GM's own `new_facts` field is dropped.
- **Why:** in round 1 the GM still got prices wrong with the price in its facts, and it filled `new_facts` once in 20 turns. Prices are structured data, so code should state them (the call-type rule). Jev can't write text, so extraction is an LLM call.
- **Details:** [Design sketch: world agents](design-world-agents.md#round-2-results-2026-10-07), [ex-tales-forge PR #42](https://github.com/whyse-ab/ex-tales-forge/pull/42)

## 2026-10-07: NPC reactions on in playtest

- **Decision:** `NPC_REACTIONS=on` on tales-forge-playtest only (a Fly secret, like the other playtest switches); `WORLD_AGENTS` stays off there. Approved by Fredrik.
- **Why:** to see the Jev reaction (Brenna's mood and stance before each GM turn) in real playtests. The first Lotta check logged one `npc_reaction` row per turn (~$0.00004, 216–407 ms) and Brenna's replies varied, though she grew steadily warier over 5 turns.
- **Details:** [Fly secrets](fly-secrets.md), [Design sketch: world agents](design-world-agents.md#the-brenna-reaction)

## 2026-10-07: Merge the NPC reaction and world-agent prototype, off by default

- **Decision:** ex-tales-forge PR #40 is merged with both `NPC_REACTIONS` and `WORLD_AGENTS` off by default; production runs with both off. Approved by Fredrik ("Put it all in - I like it").
- **Why:** both flags cost nothing when off, the cached prefix is unchanged (prefix test), and having the code on main lets playtest and the next round build on it.
- **Details:** [ex-tales-forge PR #40](https://github.com/whyse-ab/ex-tales-forge/pull/40), [Design sketch: world agents](design-world-agents.md)

## 2026-10-07: To try: world agents hold facts

- **To try (not a final decision):** world agents (persons, locations, items, maybe animals) hold facts; the GM asks them for facts before narrating, and facts the GM invents are written back to the owning agent.
- **Why:** the prose-GM prototype drifted on lore (harpies instead of the orc nest) and on prices (a room for 2, 3 or 8 silver), and NPCs forgot promises. Facts kept by agents and sent per turn should keep the world consistent while the cached GM prefix stays small and stable.
- **Details:** [Design sketch: world agents](design-world-agents.md)

## 2026-10-07: Measure every call and turn step by call type

- **Decision:** every `ai_calls` row has a `call_type` (`function`, `jev`, `llm`) and adventure and game-system tags; the main Elixir steps of a turn are timed as zero-cost `function` rows. `/admin/costs` and playtest run reports show cost and p50/p90 latency per call type and purpose, the cache hit rate and the idle gap before each GM call, with persona cost kept apart.
- **Why:** so the call-type rule, caching and pricing can be checked with numbers instead of guesses.
- **Details:** [ex-tales-forge PR #39](https://github.com/whyse-ab/ex-tales-forge/pull/39), [Call types: recording call types and metrics](call-types.md#recording-call-types-and-metrics)

## 2026-10-07: Each bot call gets its own conversation id

- **Decision:** persona, scorer and intent calls send `x-grok-conv-id` `<session>:<purpose>`; only the scene and GM calls share the session id.
- **Why:** the persona bot's calls on the session id pushed the GM prompt out of xAI's cache between turns, so GM calls missed the cache.
- **Details:** [ex-tales-forge PR #37](https://github.com/whyse-ab/ex-tales-forge/pull/37)

## 2026-10-07: No length limits in the GM reply schema

- **Decision:** the strict GM/scene reply schema has no `maxLength` or `maxItems`; the caps on notes, summary and NPC memories are applied in code when the reply is parsed.
- **Why:** with `maxLength`/`maxItems` in the schema xAI does not reuse the prompt cache at all (every GM call reported 128 cached tokens); without them the same request reuses ~9k tokens.
- **Details:** [ex-tales-forge PR #36](https://github.com/whyse-ab/ex-tales-forge/pull/36)

## 2026-10-07: Elixir is the platform

- **Decision:** Tales Forge is built on Elixir: Phoenix LiveView, Ash, Oban and Jido. Decided by Fredrik, who funds the project.
- **Why:** the BEAM fits a soft real-time, always-on game with many concurrent sessions and agents.
- **Details:** [Why Elixir](why-elixir.md) (copy of the Google Doc [Why Elixir](https://docs.google.com/document/d/19w4sYfea-OamyPrnMk44hhbuVFDU9kKXirkqR_jjmtE))

## 2026-10-07: Decisions are recorded in this file

- **Decision:** decisions are recorded in this file, in this repo.
- **Why:** one place to see what was decided and why, with git history as the audit trail.

## 2026-10-07: Docs go straight to main

- **Decision:** documentation is committed straight to `main` in this repo, without pull requests; if something is wrong, undo it. Code still goes through pull requests, with Fredrik's OK before merge or deploy.
- **Why:** docs are cheap to fix and slow to review; code reaches players, so it keeps the review gate.
- **Details:** [Environments](environments.md) (how code reaches production)

## 2026-10-07: Call-type rule

- **Decision:** known structured input + structured output = Elixir function; unstructured input + structured output = Jev; prose output = LLM. Asking the LLM for structured output is a smell.
- **Why:** Elixir is exact, free and instant, Jev is fast and cheap, and the LLM is the slowest and most expensive; output length drives GM latency.
- **Details:** [Call types](call-types.md)

## 2026-10-07: GM pipeline direction

- **Decision:** Jev validates player input up front, so the GM prompt needs little hardening. Jev's intent plus Elixir's rules and rolls go to the GM as a typed struct with a short quote of the player's words. The GM uses a non-thinking model.
- **Why:** the GM only narrates prose, which makes turns faster and cheaper while keeping the player's tone.
- **Details:** [Call types: target turn pipeline](call-types.md#target-turn-pipeline)

## 2026-10-07: One Character type

- **Decision:** player characters and NPCs are technically identical (OCEAN personality, personality-filtered memory, Maslow level); only the controller differs (player or GM). NPCs run as their own Elixir agents with Jev gut reactions (System 1).
- **Why:** the GM can play an absent player's character with the same data and calls, and parties become possible later.
- **Details:** [Call types: character model](call-types.md#character-model)

## 2026-10-07: Measure cost and time per call type

- **Decision:** measure cost and time per call type (function, Jev, LLM) and per world/module, including cache hit rate.
- **Why:** so the call-type rule and pricing can be checked with numbers.
- **Details:** [Call types: recording call types and metrics](call-types.md#recording-call-types-and-metrics)

## 2026-10-07: Pricing direction (draft)

- **Decision:** no monthly subscription. Prepaid play time, billed only on GM response time; idle time is free. First character free. Working numbers: $1 per real hour, $3 starter, $5/$10/$20 top-ups.
- **Why:** players pay for what they use, and slow or casual play isn't punished.
- **Details:** [Pricing: a pool of play time](pricing-time-pool.md)

## 2026-10-07: All amounts in USD

- **Decision:** all amounts are in USD.
- **Why:** one currency for costs, prices and reports.

## 2026-10-07: Jev persona-affect scoring

- **Decision:** Jev scores persona affect 1-5 (frustrated to delighted) with confidence, per session and per turn, reading only player and GM spoken text, never hidden GM notes.
- **Why:** a cheap, typed signal of how a session felt, based only on what the player actually saw.
- **Details:** [Jev persona-affect scoring](jev-scoring.md)

## 2026-10-06: Character creation

- **Decision:** copy the working flow from tales-forge.ai, then move to a hybrid where each section (stats, background, social class, origin) offers own input or AI assist.
- **Why:** the old flow works today, and 4 of 5 personas preferred the per-section hybrid.
- **Details:** [Character creation port](character-creation-port.md), [persona preferences](character-creation-persona-prefs.md)

## 2026-10-06: The GM opens the scene

- **Decision:** the GM always opens the scene; players respond.
- **Why:** players start with something to react to instead of a blank prompt.

## 2026-10-06: One admin costs page

- **Decision:** all costs (Fly, Resend, domain, AI, GitHub) are shown on one admin costs page.
- **Why:** total running cost in one place.
- **Details:** [Infrastructure assets](infrastructure.md)

## 2026-10-06: Playtesting

- **Decision:** one end-to-end smoke test until all personas are ready, then intense bursts. Persona-bot time and tokens are measured separately from the game's own numbers.
- **Why:** don't spend on bot play before it's useful, and keep game cost figures clean.
- **Details:** [Design: playtest loop](design-playtest-loop.md), [Personas](personas.md)

## 2026-10-06: Branching and environments

- **Decision:** one always-deployable `main` with short-lived feature branches, per-PR preview apps, and a separate long-lived playtest Fly app. Bots need Fredrik's explicit OK before any deploy or merge of code.
- **Why:** production stays stable while bots and founders try changes safely.
- **Details:** [Environments](environments.md)

## 2026-10-06: Separate API keys per environment

- **Decision:** separate API keys per environment (xAI production vs playtest; TypeSafe per environment).
- **Why:** so costs split by environment, and one key can be revoked without breaking the other.
- **Details:** [Adding API keys and secrets to Fly](fly-secrets.md)

## 2026-10-06: Sign-in

- **Decision:** admin uses email magic links (no passwords), and logins last 30 days. Founders playtest via GitHub login, checked against the whyse-ab tales-forge team.
- **Why:** no passwords to store or leak, and founder access follows GitHub team membership.
- **Details:** [Setting up Resend](resend-setup.md), [Infrastructure assets](infrastructure.md)

## 2026-10-06: tales-forge.ai stays on Netlify for now

- **Decision:** tales-forge.ai stays on the existing Netlify site until the new Fly app is a working prototype.
- **Why:** players keep a working game until the replacement is ready.
- **Details:** [Infrastructure assets](infrastructure.md), [Environments](environments.md)

## 2026-10-05: North star

- **Decision:** the north star is the first paying customer the founders don't personally know.
- **Why:** everything is ordered by how much it brings that customer closer.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: No assigning tasks

- **Decision:** nobody assigns tasks to people; founders self-assign. Plans are ordered lists, most important first.
- **Why:** founders choose their own work; the order says what matters most.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: Fantasy first, own content first

- **Decision:** launch with fantasy only. The team builds the world and modules itself first; an author marketplace comes later.
- **Why:** prove the game in one genre with content we control before opening it up.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: Acquisition

- **Decision:** RPG forums first, then word of mouth.
- **Why:** forums bring the first players; sharing brings the next ones.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## Open questions

- **Prose-only GM vs structured reply format.** The prototype ([ex-tales-forge PR #38](https://github.com/whyse-ab/ex-tales-forge/pull/38)) is cheaper and faster but loses per-turn NPC memories and lore anchoring. The structured schema stays the default for now.
