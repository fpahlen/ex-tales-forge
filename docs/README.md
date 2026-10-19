# Shared docs

Longer design notes and plans. Prefer Markdown here; Google Drive is a temporary home until content is migrated or linked.

- [Decision log](decisions.md): what the founders have decided and why, newest first
- [Future ideas](future-ideas.md): ideas we may pick up later, not decided

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
- [Refactoring lessons](refactoring.md): the patterns from the 2026-10-17 refactoring (cycles, forwarders, structs instead of long parameter lists, the health gate, CI), each with its PR
- [Module audit of ex-tales-forge (2026-10-07)](module-audit-2026-10-07.md): every module grouped as in use, framework, dead or unsure, with a ranked removal proposal
- [Plan: remove Ash (plain Ecto)](plan-remove-ash.md): what goes, the admin forms on Ecto, the safe table drop, deps, rollout and rollback (done: #47 merged and deployed 2026-10-07)
- [Plan: one Character entity for PCs and NPCs](plan-unify-character.md): today's two shapes side by side, the target `characters` table and agent, the controller (player or GM, AFK, companions), data migration, levers, what breaks, phased rollout (plan; waiting for OK)
- [Plan: Tales Forge refactoring round 2026-10-17](plan-tf-refactor-2026-10-17.md): health targets and steps, including GameCharacter 10a–10f, the 10b split (10b-1, 10b-1.5 sheet promotion, 10b-2) and the `runtime["sheet"]` bridge condition
- [Design sketch: world agents](design-world-agents.md): persons, locations and items as Elixir agents that hold facts for the GM, and the [living world](design-world-agents.md#living-world-design-to-try): factions with plans and clocks on world time (to try)
- [Design: the Tin Valley world around the inn](design-tin-valley-world.md): new places and people for every player type (`INN_WORLD`), the Tinjacks antagonist on world time (`WORLD_ANTAGONIST`), flags and cost
- [Design: playtest loop](design-playtest-loop.md): how persona bots play, get scored, and feed fixes and decisions (draft)
- [Jev persona-affect scoring](jev-scoring.md): TypeSafe Jev for numeric persona-feeling scores (first cut 2026-10-07; not built yet)
- [Design: Jev as player-intent gate](design-jev-intent-gate.md): Jev checks player input up front; the GM gets a typed turn brief instead of prose (draft, 2026-10-07). The later approved direction is [Design: player intent as one Jev call](design-jev-intent.md) (2026-10-08).
- [Analysis: Jev scores from the playtests (2026-10-07)](analysis-jev-scores-2026-10-07.md): per persona, by turn, correlations (dice failures and NPC brush-offs drive low scores), Hawk's low confidence, recommendations
- [Analysis: Jev after the inn-world, scene-change and Brenna rework (2026-10-08)](analysis-jev-post-rework-2026-10-08.md): 23-run post-rework series vs the 2026-10-07 baseline (new rubric for Paul and Lotta): leaving the inn, echo and tics, the Tinjacks, growth, cost, a turn hang
- [Analysis: INTENT_CALL_EVERY_TURN off vs on (2026-10-08)](analysis-intent-every-turn-2026-10-08.md): 20-run playtest batch on ex-tales-forge #76 with the flag off and on: quote rate, clarification loops, Jev, safety labels, cost (game vs persona), latency, hangs
- [Design: persistent world state at the core of the turn loop](design-stateful-world.md): an apply-consequences step between rules and prose, one process per world with entities as plain data, an event log plus snapshots, the GM gets a state snapshot; migration in small flagged PRs (design, no code)
- [Design: player intent as one Jev call](design-jev-intent.md): one TypeSafe Jev call per turn for the typed intent and the safety label; labelled evaluation set and `mix intent.eval` first, thresholds and clarification bands, what goes away, secrets, playtest comparison, PR sequence (design, no code yet)
- [Design: social layer](design-social-layer.md): hearing as pure game code (voice dB vs room noise and distance, clarity per listener), listener readings in the per-NPC reaction call, signed per-pair liking, an obligations ledger that reads trades but never changes them, and two-speed understanding (System 2 and theory-of-mind level 2 only on code-decided triggers); waits for survey 5; open decisions and an 11-PR plan (design, no code)
- [Design: one rule for skills and the economy](design-skills-economy.md): a day rate by skill level through practice hours drives wages, hirelings, trainer fees, services and item prices as anchors, with bounded situational modifiers (0.5×-3×) for the price paid; practice hours as narrative bands; growth stays PR #100's LP model; the drift to fix and open questions (design, no code)
- [Goal: a living town](goal-living-town.md): long-term technical goal, a 100-hour session in a town of 1,000 GameCharacters; a yardstick with gap questions for designs and PRs (not scheduled, no build cards)
- [Discussion: when Workflow needs a bot, and how a client sets it up](https://github.com/whyse-ab/workflow/blob/main/docs/discussion-workflow-bots-and-client-setup.md): code, then LLM, then bot; hosting, Microsoft-only clients, and bots other than Grok Bot (open discussion)
- [Personal account migration plan](personal-account-migration.md): move Tales Forge and Workflow off Fredrik's personal accounts (GitHub, Fly, billing, secrets)
- [Call types: Elixir function, Jev, or LLM](call-types.md): which call type to use for each piece of work, and the target turn pipeline (draft)
- [Player UI directions (2026-10-16)](ui-suggestions/2026-10-16-player-ui-directions/README.md): three UI concepts (run of the mill, pen and paper, living manuscript), creation and gameplay screens in light and dark, with the persona and research reasoning behind each (concept mockups, no decision)
- [Plan: porting character creation from the old app](character-creation-port.md): how the old app's creation works and a proposed port to the Elixir app (draft)
- [Setting up Resend (email)](resend-setup.md)
- [Adding API keys and secrets to Fly](fly-secrets.md)
- [Pricing decision draft: a pool of play time](pricing-time-pool.md): bill GM processing time only, first character free, rough cost per turn and per commute (draft)
- [Character creation: persona preferences (hybrid ideas)](character-creation-persona-prefs.md): Hawk/Paul/Lotta/Lars/Ronny on Idea 1 vs Idea 2 (research; complements port plan PR #15)
- [Founder survey: how we'd play, and do the playtest scores feel right?](founder-survey-3.md): one combined form, about 17 minutes. Play style, what the persona key words mean, 10 real baseline turns to rate against Jev, and an archetype grid per persona. Open; answered on production at [`/admin/survey`](https://tales-forge.fly.dev/admin/survey) (surveys live only on production, playtest redirects there), generated from [`founder-survey-3.json`](founder-survey-3.json)
- [Founder survey 4: what did the player mean?](founder-survey-4-intent.md): 12 vague player lines from the intent eval set (tune split only); founders pick the reading, or say the game should ask. About 10 minutes. Open; a tab on production's `/admin/survey` once ex-tales-forge #82 merges (reachable now at [`/admin/surveys/founder-survey-4-intent`](https://tales-forge.fly.dev/admin/surveys/founder-survey-4-intent)), generated from [`founder-survey-4-intent.json`](founder-survey-4-intent.json); how answers become labels: [apply_answers](scripts/survey-intent/apply_answers.md)
- [Founder survey 5: what does the player's line do?](founder-survey-5-social.md): 40 player lines (24 real from the 2026-10-18 playtest sessions, 16 scripted); founders label the social act (the 14 G1 labels or unclear), the target and the voice, blind. About 20 minutes. Open; a tab on production's `/admin/founders/survey` once merged, generated from [`founder-survey-5-social.json`](founder-survey-5-social.json); the plan, the proposed pass bar and the later Jev comparison: [experiments/2026-10-social-act-survey](experiments/2026-10-social-act-survey.md)
- [Founder survey 2: how we'd play](founder-survey-2.md): merged into the combined survey above, never sent

Worlds and adventure packs (Merovingia, Penny Dreadful, Tin Valley, …) copied from the game repos: [worlds/README.md](worlds/README.md)
