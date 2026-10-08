# Shared docs

Longer design notes and plans. Prefer Markdown here; Google Drive is a temporary home until content is migrated or linked.

- [Decision log](decisions.md): what the founders have decided and why, newest first

Docs copied from the [Google Drive folder](https://drive.google.com/drive/folders/1tlNoL8WZJPgbFQVT4SipKi9odGnQM_PB) (each file's front matter has a `source:` link to its Drive original):

- [Roadmap 2027 (rev. 3)](roadmap-2027.md)
- [Why Elixir](why-elixir.md)
- [Personas](personas.md)
- [Design: Game data vs sessions](design-game-data-vs-sessions.md)
- [Design: Decision queue and shared docs](design-decision-queue-and-docs.md)

Persona input is collected with a Google Form: [Tales Forge: Your input on our player personas](https://docs.google.com/forms/d/e/1FAIpQLSdd8W5SJrnh5zZMDPXABKTErgYAKcl4Iag35CwZ_OYHifOqNQ/viewform). First-pass synthesis: [Persona form notes](persona-form-notes.md).

Also in this folder:

- [Examples of play](examples-of-play.md): five short sample sessions in Merovingia, one per persona (draft)
- [Infrastructure assets](infrastructure.md)
- [Environments and how changes reach production](environments.md)
- [Coding standards](coding-standards.md): moduledocs, docs, specs + Dialyzer, Credo strict, ExDoc, tests with coverage, all enforced in CI
- [Module audit of ex-tales-forge (2026-10-07)](module-audit-2026-10-07.md): every module grouped as in use, framework, dead or unsure, with a ranked removal proposal
- [Plan: remove Ash (plain Ecto)](plan-remove-ash.md): what goes, the admin forms on Ecto, the safe table drop, deps, rollout and rollback (done: #47 merged and deployed 2026-10-07)
- [Plan: one Character entity for PCs and NPCs](plan-unify-character.md): today's two shapes side by side, the target `characters` table and agent, the controller (player or GM, AFK, companions), data migration, levers, what breaks, phased rollout (plan; waiting for OK)
- [Design sketch: world agents](design-world-agents.md): persons, locations and items as Elixir agents that hold facts for the GM, and the [living world](design-world-agents.md#living-world-design-to-try): factions with plans and clocks on world time (to try)
- [Design: the Tin Valley world around the inn](design-tin-valley-world.md): new places and people for every player type (`INN_WORLD`), the Tinjacks antagonist on world time (`WORLD_ANTAGONIST`), flags and cost
- [Design: playtest loop](design-playtest-loop.md): how persona bots play, get scored, and feed fixes and decisions (draft)
- [Jev persona-affect scoring](jev-scoring.md): TypeSafe Jev for numeric persona-feeling scores (first cut 2026-10-07; not built yet)
- [Analysis: Jev scores from the playtests (2026-10-07)](analysis-jev-scores-2026-10-07.md): per persona, by turn, correlations (dice failures and NPC brush-offs drive low scores), Hawk's low confidence, recommendations
- [Analysis: Jev after the inn-world, scene-change and Brenna rework (2026-10-08)](analysis-jev-post-rework-2026-10-08.md): 23-run post-rework series vs the 2026-10-07 baseline (new rubric for Paul and Lotta): leaving the inn, echo and tics, the Tinjacks, growth, cost, a turn hang
- [Analysis: INTENT_CALL_EVERY_TURN off vs on (2026-10-08)](analysis-intent-every-turn-2026-10-08.md): 20-run playtest batch on ex-tales-forge #76 with the flag off and on: quote rate, clarification loops, Jev, safety labels, cost (game vs persona), latency, hangs
- [Design: player intent as one Jev call](design-jev-intent.md): one TypeSafe Jev call per turn for the typed intent and the safety label; labelled evaluation set and `mix intent.eval` first, thresholds and clarification bands, what goes away, secrets, playtest comparison, PR sequence (design, no code yet)
- [Call types: Elixir function, Jev, or LLM](call-types.md): which call type to use for each piece of work, and the target turn pipeline (draft)
- [Plan: porting character creation from the old app](character-creation-port.md): how the old app's creation works and a proposed port to the Elixir app (draft)
- [Setting up Resend (email)](resend-setup.md)
- [Adding API keys and secrets to Fly](fly-secrets.md)
- [Pricing decision draft: a pool of play time](pricing-time-pool.md): bill GM processing time only, first character free, rough cost per turn and per commute (draft)
- [Character creation: persona preferences (hybrid ideas)](character-creation-persona-prefs.md): Hawk/Paul/Lotta/Lars/Ronny on Idea 1 vs Idea 2 (research; complements port plan PR #15)
- [Founder survey: how we'd play, and do the playtest scores feel right?](founder-survey-3.md): one combined form, about 17 minutes. Play style, what the persona key words mean, 10 real baseline turns to rate against Jev, and an archetype grid per persona. Open; answered in the app at `/admin/survey`, generated from [`founder-survey-3.json`](founder-survey-3.json)
- [Founder survey 2: how we'd play](founder-survey-2.md): merged into the combined survey above, never sent

Worlds and adventure packs (Merovingia, Penny Dreadful, Tin Valley, …) copied from the game repos: [worlds/README.md](../worlds/README.md)
