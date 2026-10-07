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
- [Plan: remove Ash (plain Ecto)](plan-remove-ash.md): what goes, the admin forms on Ecto, the safe table drop, deps, rollout and rollback (plan; code not started)
- [Design sketch: world agents](design-world-agents.md): persons, locations and items as Elixir agents that hold facts for the GM (to try)
- [Design: playtest loop](design-playtest-loop.md): how persona bots play, get scored, and feed fixes and decisions (draft)
- [Jev persona-affect scoring](jev-scoring.md): TypeSafe Jev for numeric persona-feeling scores (first cut 2026-10-07; not built yet)
- [Call types: Elixir function, Jev, or LLM](call-types.md): which call type to use for each piece of work, and the target turn pipeline (draft)
- [Plan: porting character creation from the old app](character-creation-port.md): how the old app's creation works and a proposed port to the Elixir app (draft)
- [Setting up Resend (email)](resend-setup.md)
- [Adding API keys and secrets to Fly](fly-secrets.md)
- [Pricing decision draft: a pool of play time](pricing-time-pool.md): bill GM processing time only, first character free, rough cost per turn and per commute (draft)
- [Character creation: persona preferences (hybrid ideas)](character-creation-persona-prefs.md): Hawk/Paul/Lotta/Lars/Ronny on Idea 1 vs Idea 2 (research; complements port plan PR #15)
- [Founder survey 2: how we'd play](founder-survey-2.md): play-style questions for the next founder form (draft; first usage indication before beta telemetry)

Worlds and adventure packs (Merovingia, Penny Dreadful, Tin Valley, …) copied from the game repos: [worlds/README.md](../worlds/README.md)
