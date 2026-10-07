---
title: "ex-tales-forge module audit (2026-10-07)"
updated: 2026-10-07
---

# ex-tales-forge module audit

Read-only audit of `main` at `57e43cd` (merge of #45), in a fresh worktree. Nothing was deleted, branched or committed during the audit.

**Follow-ups:** items 1–5 of the removal proposal are in [ex-tales-forge PR #46](https://github.com/whyse-ab/ex-tales-forge/pull/46) (open, not merged). Ash removal (item 9, extended to the admin resources) is planned in [Plan: remove Ash](plan-remove-ash.md).

## Summary

| Group | Modules | LOC |
|---|---:|---:|
| 1. In active use | 116 | 16316 |
| 2. Framework / generated, must stay | 15 | 1296 |
| 3. Unused / dead | 5 | 96 (+199 in `page_html/home.html.heex`) |
| 4. Unsure (flag-gated off everywhere, empty data, dev-only tools) | 12 | 2884 |
| **Total** | **148** | **20592** |

LOC is total lines (`wc -l`) in `lib/**/*.ex`. Modules nested in one file (e.g. `Game.Schemas.*`) get their own block length, so the totals add up to the 20,592 lines in `lib/`. 148 modules, plus 7 `Inspect.*` impls that Ash generates for its resources (not counted).

**What this means for `/admin/code-docs`:** almost everything listed there is real. Only 5 modules (96 lines, plus a 199-line template) are clearly dead. The bigger savings are in group 4: the Ash authoring layer (about 1,450 lines, tables empty on prod and playtest) and the unused `jido_ai` dependency (12 hex packages, about 14 MB of the release).

## Method

- `mix compile --force`: **0 warnings** (so no unused private functions, aliases or variables).
- `mix xref callers <Module>` for all 155 compiled modules. `mix xref graph --format plain`, with a reachability walk from the real entry points: `application.ex` children, router/endpoint, `rel/overlays/bin/migrate` (Release), mix tasks, and modules named in config: `ash_domains`, `render_errors` (ErrorHTML/JSON), `TalesForge.Costs`, `Playtest.Runner`, `Config`, `AICalls.check_spend_caps`.
- `mix xref unreachable` doesn't exist in Elixir 1.18 (removed). The compiler and xref cover what it used to do.
- Cross-checks:
  - routes in `router.ex`;
  - Oban workers and their enqueue sites, plus job counts by worker on prod and playtest;
  - Ash domains and resources, including row counts on prod and playtest;
  - Jido actions listed in `NPCAgent`;
  - dynamic dispatch (`apply`, `Module.concat`, `String.to_atom`): only the `TalesForgeWeb.__using__` macro and atom keys in the importer;
  - env flags read in `lib/` and `config/`;
  - mix aliases, and docs that mention the tasks.
- Prod/playtest data checks were read-only: `Repo.aggregate(:count)` through `flyctl machine exec ... rpc`.
- A name-based scan for public functions with no callers in `lib/` (see appendix). It's a lower bound: a common name can hide a dead function.

## 1. In active use (116 modules, 16316 LOC)

| Module | File | LOC | Evidence / caller |
|---|---|---:|---|
| `Mix.Tasks.Playtest.Run` | `lib/mix/tasks/playtest.run.ex` | 47 | **flag-gated** CLI entry to the persona runner. |
| `Mix.Tasks.Tales.SyncDocs` | `lib/mix/tasks/tales.sync_docs.ex` | 54 | Docs sync CLI (DEPLOY-FLY.md); same code path as the admin sync |
| `TalesForge.AICalls` | `lib/ex_tales_forge/ai_calls.ex` | 289 | called by W/live/admin/costs_live, ai_calls/metrics, ai_calls/steps, costs +5 more |
| `TalesForge.AICalls.Metrics` | `lib/ex_tales_forge/ai_calls/metrics.ex` | 469 | called by W/live/admin/costs_live, playtest/reports |
| `TalesForge.AICalls.Steps` | `lib/ex_tales_forge/ai_calls/steps.ex` | 96 | called by game/turn_processor, game_sessions, world/extract |
| `TalesForge.AICalls.Tags` | `lib/ex_tales_forge/ai_calls/tags.ex` | 56 | called by ai_calls, game/turn_processor, game_sessions |
| `TalesForge.Actions.NPC.AdjustConcern` | `lib/ex_tales_forge/actions/npc/adjust_concern.ex` | 23 | called by actions/npc/react_to_time |
| `TalesForge.Actions.NPC.EmitInitiative` | `lib/ex_tales_forge/actions/npc/emit_initiative.ex` | 34 | called by actions/npc/react_to_time |
| `TalesForge.Actions.NPC.OnOverheard` | `lib/ex_tales_forge/actions/npc/on_overheard.ex` | 33 | called by agents/npc_agent |
| `TalesForge.Actions.NPC.OnPlayerTalked` | `lib/ex_tales_forge/actions/npc/on_player_talked.ex` | 37 | called by agents/npc_agent |
| `TalesForge.Actions.NPC.ReactToTime` | `lib/ex_tales_forge/actions/npc/react_to_time.ex` | 34 | called by agents/npc_agent |
| `TalesForge.Actions.NPC.UpdateMemory` | `lib/ex_tales_forge/actions/npc/update_memory.ex` | 19 | called by actions/npc/on_overheard, actions/npc/on_player_talked |
| `TalesForge.Admin` | `lib/ex_tales_forge/admin.ex` | 379 | called by W/live/admin/dashboard_live, W/live/admin/npc_definition_live/index, W/live/admin/npc_definition_live/show, W/live/admin/npc_live/index +4 more |
| `TalesForge.AdminAuth` | `lib/ex_tales_forge/admin_auth.ex` | 165 | called by W/controllers/admin_github_auth_controller, W/controllers/admin_session_controller, W/live/admin/hooks, W/plugs/admin_auth +2 more |
| `TalesForge.AdminAuth.GitHub` | `lib/ex_tales_forge/admin_auth/github.ex` | 206 | called by W/controllers/admin_github_auth_controller, W/live/admin/login_live, admin_auth |
| `TalesForge.AdminAuth.MembershipCache` | `lib/ex_tales_forge/admin_auth/membership_cache.ex` | 47 | Application child: GitHub team membership cache |
| `TalesForge.AdminResources` | `lib/ex_tales_forge/admin_domain.ex` | 29 | Ash domain (config `ash_domains`) for AshPhoenix edit forms on runtime tables |
| `TalesForge.AdminResources.GameSession` | `lib/ex_tales_forge/admin_resources/game_session.ex` | 87 | AshPhoenix form on `/admin/sessions/:id` |
| `TalesForge.AdminResources.NpcInstance` | `lib/ex_tales_forge/admin_resources/npc_instance.ex` | 64 | AshPhoenix form on `/admin/sessions/:id/npcs/:npc_id` |
| `TalesForge.AdminResources.Scene` | `lib/ex_tales_forge/admin_resources/scene.ex` | 56 | Admin scene edits via `TalesForge.Admin` |
| `TalesForge.AdminResources.Turn` | `lib/ex_tales_forge/admin_resources/turn.ex` | 57 | Admin turn edits via `TalesForge.Admin` |
| `TalesForge.Agents.NPCAgent` | `lib/ex_tales_forge/agents/npc_agent.ex` | 28 | Jido NPC agent (NPCRegistry) |
| `TalesForge.Agents.PlayerSessionAgent` | `lib/ex_tales_forge/agents/player_session_agent.ex` | 16 | Jido agent per player session (GameSessions) |
| `TalesForge.Collab` | `lib/ex_tales_forge/collab.ex` | 178 | Admin decisions/docs pages + `mix tales.sync_docs` (12 decisions, 13 docs on prod) |
| `TalesForge.Collab.Importer` | `lib/ex_tales_forge/collab/importer.ex` | 343 | Syncs tales-forge-docs into the DB (`Collab.sync`, admin "sync" + `mix tales.sync_docs`) |
| `TalesForge.Collab.Markdown` | `lib/ex_tales_forge/collab/markdown.ex` | 70 | called by W/live/admin/decision_live/show, W/live/admin/doc_live/index |
| `TalesForge.Collab.Schemas.Comment` | `lib/ex_tales_forge/collab/schemas/comment.ex` | 25 | Decision comments (1 row on prod) |
| `TalesForge.Collab.Schemas.Decision` | `lib/ex_tales_forge/collab/schemas/decision.ex` | 62 | called by collab, collab/importer, collab/schemas/comment, collab/schemas/interest |
| `TalesForge.Collab.Schemas.Doc` | `lib/ex_tales_forge/collab/schemas/doc.ex` | 24 | called by collab, collab/importer |
| `TalesForge.Collab.Schemas.Interest` | `lib/ex_tales_forge/collab/schemas/interest.ex` | 27 | Decision interest marks (1 row on prod) |
| `TalesForge.Collab.Schemas.MagicToken` | `lib/ex_tales_forge/collab/schemas/magic_token.ex` | 25 | Admin magic-link tokens (AdminAuth) |
| `TalesForge.Config` | `lib/ex_tales_forge/config.ex` | 74 | Env config incl. flags (`NPC_REACTIONS`, `WORLD_AGENTS`); also config/runtime.exs |
| `TalesForge.Costs` | `lib/ex_tales_forge/costs.ex` | 271 | Costs page + peer endpoint; config key `TalesForge.Costs` |
| `TalesForge.Costs.Peer` | `lib/ex_tales_forge/costs/peer.ex` | 79 | called by W/controllers/costs_peer_controller, W/live/admin/costs_live |
| `TalesForge.Fronts` | `lib/ex_tales_forge/fronts.ex` | 110 | Front persistence (15 rows prod, 54 playtest) |
| `TalesForge.GMReasoning` | `lib/ex_tales_forge/gm_reasoning.ex` | 68 | called by game/turn_processor, playtest/reports |
| `TalesForge.Game.ActionHandler` | `lib/ex_tales_forge/game/action_handler.ex` | 105 | called by game/turn_processor, npc_signals |
| `TalesForge.Game.Context` | `lib/ex_tales_forge/game/context.ex` | 316 | called by game/intent, game/prompts, game/scene_processor, game/turn_processor +1 more |
| `TalesForge.Game.Events` | `lib/ex_tales_forge/game/events.ex` | 166 | called by game/turn_processor |
| `TalesForge.Game.Fronts` | `lib/ex_tales_forge/game/fronts.ex` | 66 | called by game/pack |
| `TalesForge.Game.Fronts.Moves` | `lib/ex_tales_forge/game/fronts/moves.ex` | 111 | called by game/world_sim |
| `TalesForge.Game.Fronts.Rules` | `lib/ex_tales_forge/game/fronts/rules.ex` | 86 | called by game/world_sim |
| `TalesForge.Game.Intent` | `lib/ex_tales_forge/game/intent.ex` | 476 | called by game_sessions |
| `TalesForge.Game.Intent.ClarificationNeeded` | `lib/ex_tales_forge/game/intent.ex` | 11 | Exception raised/rescued in `GameSessions` intent flow |
| `TalesForge.Game.Inventory` | `lib/ex_tales_forge/game/inventory.ex` | 743 | called by game/intent, game/train, game/turn_processor, npc +1 more |
| `TalesForge.Game.Mechanics` | `lib/ex_tales_forge/game/mechanics.ex` | 398 | called by game/action_handler, game/context, game/events, game/intent +4 more |
| `TalesForge.Game.NpcReactions` | `lib/ex_tales_forge/game/npc_reactions.ex` | 379 | **flag-gated** Flag `NPC_REACTIONS` (or `WORLD_AGENTS`): on in playtest, off in prod. Called by TurnProcessor/Context. |
| `TalesForge.Game.Pack` | `lib/ex_tales_forge/game/pack.ex` | 363 | called by fronts, game_sessions, npc |
| `TalesForge.Game.Perception` | `lib/ex_tales_forge/game/perception.ex` | 126 | called by game/context, game/turn_processor |
| `TalesForge.Game.Prompts` | `lib/ex_tales_forge/game/prompts.ex` | 152 | called by game/context, game/intent, game/scene_processor, game/turn_processor |
| `TalesForge.Game.SceneProcessor` | `lib/ex_tales_forge/game/scene_processor.ex` | 173 | GM pipeline: scene narration (ProcessScene worker, runner) |
| `TalesForge.Game.Schemas` | `lib/ex_tales_forge/game/schemas.ex` | 30 | Shared types for the schema structs below |
| `TalesForge.Game.Schemas.ClarificationOption` | `lib/ex_tales_forge/game/schemas.ex` | 17 | Built by `IntentExtraction.decode/1` in the same file (xref only lists other files) |
| `TalesForge.Game.Schemas.GMStructuredResponse` | `lib/ex_tales_forge/game/schemas.ex` | 64 | called by game/turn_processor, gm_reasoning, llm |
| `TalesForge.Game.Schemas.HandlerResult` | `lib/ex_tales_forge/game/schemas.ex` | 8 | called by game/action_handler, game/mechanics, game/prompts, llm |
| `TalesForge.Game.Schemas.IntentExtraction` | `lib/ex_tales_forge/game/schemas.ex` | 49 | called by game/intent, game_sessions, llm |
| `TalesForge.Game.Schemas.MechanicalResolution` | `lib/ex_tales_forge/game/schemas.ex` | 43 | called by game/context, game/mechanics, game/turn_processor |
| `TalesForge.Game.Schemas.PlayerAction` | `lib/ex_tales_forge/game/schemas.ex` | 27 | called by game/action_handler, game/intent, game/mechanics, game/prompts +3 more |
| `TalesForge.Game.Schemas.SingleAction` | `lib/ex_tales_forge/game/schemas.ex` | 52 | called by game/intent, game/inventory, game_sessions |
| `TalesForge.Game.Train` | `lib/ex_tales_forge/game/train.ex` | 84 | GM pipeline: the "train" action (TurnProcessor) |
| `TalesForge.Game.TurnProcessor` | `lib/ex_tales_forge/game/turn_processor.ex` | 522 | GM pipeline: runs one turn (ProcessTurn worker) |
| `TalesForge.Game.World` | `lib/ex_tales_forge/game/world.ex` | 111 | called by game/context, game/inventory, game/pack, game/scene_processor +3 more |
| `TalesForge.Game.WorldClock` | `lib/ex_tales_forge/game/world_clock.ex` | 122 | called by fronts, game/action_handler, game/intent, game/pack +4 more |
| `TalesForge.Game.WorldSim` | `lib/ex_tales_forge/game/world_sim.ex` | 173 | called by game/turn_processor |
| `TalesForge.GameSessions` | `lib/ex_tales_forge/game_sessions.ex` | 448 | called by W/live/home_live, W/live/play_live, game/context, playtest/jev_scorer +5 more |
| `TalesForge.LLM` | `lib/ex_tales_forge/llm.ex` | 718 | called by game/intent, game/scene_processor, game/turn_processor, playtest/runner +4 more |
| `TalesForge.NPC` | `lib/ex_tales_forge/npc.ex` | 585 | called by actions/npc/adjust_concern, actions/npc/on_player_talked, actions/npc/update_memory, admin +11 more |
| `TalesForge.NPCInitiative` | `lib/ex_tales_forge/npc_initiative.ex` | 39 | called by actions/npc/emit_initiative |
| `TalesForge.NPCRecovery` | `lib/ex_tales_forge/npc_recovery.ex` | 61 | Application child: restarts NPC agents on boot |
| `TalesForge.NPCRegistry` | `lib/ex_tales_forge/npc_registry.ex` | 120 | called by game/turn_processor, game_sessions, npc_recovery, npc_signals |
| `TalesForge.NPCSignals` | `lib/ex_tales_forge/npc_signals.ex` | 124 | called by game/turn_processor |
| `TalesForge.Playtest.AffectLevels` | `lib/ex_tales_forge/playtest/affect_levels.ex` | 63 | **flag-gated** Persona runner: Jev affect levels per persona. |
| `TalesForge.Playtest.JevScorer` | `lib/ex_tales_forge/playtest/jev_scorer.ex` | 233 | **flag-gated** Persona runner: Jev affect scoring for runs. |
| `TalesForge.Playtest.Personas` | `lib/ex_tales_forge/playtest/personas.ex` | 79 | **flag-gated** Persona runner (playtest only); admin playtest page. |
| `TalesForge.Playtest.PlayerView` | `lib/ex_tales_forge/playtest/player_view.ex` | 90 | **flag-gated** Persona runner: what the bot player sees. |
| `TalesForge.Playtest.Reports` | `lib/ex_tales_forge/playtest/reports.ex` | 193 | **flag-gated** Persona runner reports; admin playtest pages. |
| `TalesForge.Playtest.Runner` | `lib/ex_tales_forge/playtest/runner.ex` | 483 | **flag-gated** Persona runner. Flag `PLAYTEST_RUNNER_ENABLED` (config/runtime.exs): 16 runs on playtest, 0 on prod. Admin `/admin/playtest`, `mix playtest.run`. |
| `TalesForge.Playtest.Scorer` | `lib/ex_tales_forge/playtest/scorer.ex` | 158 | **flag-gated** Persona runner: scorer bot (admin playtest show). |
| `TalesForge.PubSub.GameSession` | `lib/ex_tales_forge/pubsub/game_session.ex` | 21 | called by W/live/play_live, game/scene_processor, game/turn_processor, game_sessions +2 more |
| `TalesForge.Schemas.AICall` | `lib/ex_tales_forge/schemas/ai_call.ex` | 78 | called by ai_calls, ai_calls/metrics, playtest/reports |
| `TalesForge.Schemas.FrontInstance` | `lib/ex_tales_forge/schemas/front_instance.ex` | 33 | Fronts table (15 rows prod) |
| `TalesForge.Schemas.GameSession` | `lib/ex_tales_forge/schemas/game_session.ex` | 35 | called by admin, ai_calls/tags, fronts, game/context +15 more |
| `TalesForge.Schemas.NpcInstance` | `lib/ex_tales_forge/schemas/npc_instance.ex` | 29 | called by admin, npc, npc_initiative, schemas/game_session |
| `TalesForge.Schemas.PlaytestRun` | `lib/ex_tales_forge/schemas/playtest_run.ex` | 68 | called by playtest/reports, playtest/runner, schemas/playtest_score |
| `TalesForge.Schemas.PlaytestScore` | `lib/ex_tales_forge/schemas/playtest_score.ex` | 58 | called by playtest/jev_scorer, playtest/reports, playtest/scorer |
| `TalesForge.Schemas.Scene` | `lib/ex_tales_forge/schemas/scene.ex` | 29 | called by admin, game/context, game/npc_reactions, game/scene_processor +3 more |
| `TalesForge.Schemas.SessionEvent` | `lib/ex_tales_forge/schemas/session_event.ex` | 30 | called by game/perception, game/turn_processor, gm_reasoning, schemas/game_session +1 more |
| `TalesForge.Schemas.Turn` | `lib/ex_tales_forge/schemas/turn.ex` | 35 | called by admin, game/context, game/npc_reactions, game/turn_processor +4 more |
| `TalesForge.Workers.ProcessScene` | `lib/ex_tales_forge/workers/process_scene.ex` | 22 | Oban worker, enqueued by `GameSessions` (5 jobs prod, 19 playtest) |
| `TalesForge.Workers.ProcessTurn` | `lib/ex_tales_forge/workers/process_turn.ex` | 25 | Oban worker, enqueued by `GameSessions` (3 jobs prod, 82 playtest) |
| `TalesForgeWeb.AdminComponents` | `lib/ex_tales_forge_web/components/admin_components.ex` | 240 | called by W/components/layouts, W/live/admin/costs_live, W/live/admin/dashboard_live, W/live/admin/decision_live/index +8 more |
| `TalesForgeWeb.AdminGithubAuthController` | `lib/ex_tales_forge_web/controllers/admin_github_auth_controller.ex` | 71 | routes `/admin/auth/github` + callback |
| `TalesForgeWeb.AdminLive.CostsLive` | `lib/ex_tales_forge_web/live/admin/costs_live.ex` | 531 | route `live /admin/costs` |
| `TalesForgeWeb.AdminLive.DashboardLive` | `lib/ex_tales_forge_web/live/admin/dashboard_live.ex` | 63 | route `live /admin` |
| `TalesForgeWeb.AdminLive.DecisionLive.Index` | `lib/ex_tales_forge_web/live/admin/decision_live/index.ex` | 171 | route `live /admin/decisions` (12 decisions on prod) |
| `TalesForgeWeb.AdminLive.DecisionLive.Show` | `lib/ex_tales_forge_web/live/admin/decision_live/show.ex` | 246 | route `live /admin/decisions/:slug` |
| `TalesForgeWeb.AdminLive.DocLive.Index` | `lib/ex_tales_forge_web/live/admin/doc_live/index.ex` | 149 | route `live /admin/docs` (13 docs on prod) |
| `TalesForgeWeb.AdminLive.Hooks` | `lib/ex_tales_forge_web/live/admin/hooks.ex` | 39 | router `on_mount` for both admin live_sessions |
| `TalesForgeWeb.AdminLive.LoginLive` | `lib/ex_tales_forge_web/live/admin/login_live.ex` | 96 | route `live /admin/login` |
| `TalesForgeWeb.AdminLive.NpcDefinitionLive.Index` | `lib/ex_tales_forge_web/live/admin/npc_definition_live/index.ex` | 61 | route `live /admin/npc-definitions` (lists pack JSON; Ash rows if any) |
| `TalesForgeWeb.AdminLive.NpcDefinitionLive.Show` | `lib/ex_tales_forge_web/live/admin/npc_definition_live/show.ex` | 67 | route `live /admin/npc-definitions/:id` (save writes Ash NpcDefinition) |
| `TalesForgeWeb.AdminLive.NpcLive.Index` | `lib/ex_tales_forge_web/live/admin/npc_live/index.ex` | 76 | route `live /admin/sessions/:id/npcs` |
| `TalesForgeWeb.AdminLive.NpcLive.Show` | `lib/ex_tales_forge_web/live/admin/npc_live/show.ex` | 143 | route `live /admin/sessions/:id/npcs/:npc_id` (AshPhoenix form) |
| `TalesForgeWeb.AdminLive.PlaytestLive.Index` | `lib/ex_tales_forge_web/live/admin/playtest_live/index.ex` | 133 | route `live /admin/playtest` |
| `TalesForgeWeb.AdminLive.PlaytestLive.Show` | `lib/ex_tales_forge_web/live/admin/playtest_live/show.ex` | 349 | route `live /admin/playtest/:id` |
| `TalesForgeWeb.AdminLive.SessionLive.Index` | `lib/ex_tales_forge_web/live/admin/session_live/index.ex` | 84 | route `live /admin/sessions` |
| `TalesForgeWeb.AdminLive.SessionLive.Show` | `lib/ex_tales_forge_web/live/admin/session_live/show.ex` | 211 | route `live /admin/sessions/:id` (AshPhoenix form) |
| `TalesForgeWeb.AdminLive.TurnLive.Index` | `lib/ex_tales_forge_web/live/admin/turn_live/index.ex` | 102 | route `live /admin/sessions/:id/turns` |
| `TalesForgeWeb.AdminSessionController` | `lib/ex_tales_forge_web/controllers/admin_session_controller.ex` | 49 | routes `POST /admin/login`, `/admin/magic/:token`, `DELETE /admin/logout` |
| `TalesForgeWeb.CodeDocsController` | `lib/ex_tales_forge_web/controllers/code_docs_controller.ex` | 83 | route `GET /admin/code-docs/*path` |
| `TalesForgeWeb.CostsPeerController` | `lib/ex_tales_forge_web/controllers/costs_peer_controller.ex` | 48 | route `GET /internal/costs` (peer costs page) |
| `TalesForgeWeb.HomeLive` | `lib/ex_tales_forge_web/live/home_live.ex` | 96 | route `live /` (player home) |
| `TalesForgeWeb.PlayComponents` | `lib/ex_tales_forge_web/components/play_components.ex` | 368 | called by W/live/play_live, playtest/player_view |
| `TalesForgeWeb.PlayLive` | `lib/ex_tales_forge_web/live/play_live.ex` | 283 | route `live /play/:id` (the game) |
| `TalesForgeWeb.Plugs.AdminAuth` | `lib/ex_tales_forge_web/plugs/admin_auth.ex` | 28 | router `:admin` pipeline |
| `TalesForgeWeb.Plugs.AdminEmail` | `lib/ex_tales_forge_web/plugs/admin_email.ex` | 18 | router `:admin_public` pipeline |

## 2. Framework or generated boilerplate, must stay (15 modules, 1296 LOC)

| Module | File | LOC | Evidence / caller |
|---|---|---:|---|
| `TalesForge` | `lib/ex_tales_forge.ex` | 9 | Root namespace module (generated); home page of the ExDoc site |
| `TalesForge.Application` | `lib/ex_tales_forge/application.ex` | 38 | OTP application callback (mix.exs `mod:`) |
| `TalesForge.Jido` | `lib/ex_tales_forge/jido.ex` | 6 | Jido instance (application child; NPC agents) |
| `TalesForge.Mailer` | `lib/ex_tales_forge/mailer.ex` | 7 | Swoosh mailer (magic-link emails via AdminAuth) |
| `TalesForge.Release` | `lib/ex_tales_forge/release.ex` | 28 | `rel/overlays/bin/migrate` (Fly `release_command`) |
| `TalesForge.Repo` | `lib/ex_tales_forge/repo.ex` | 28 | Ecto repo (config, application child, 35 callers) |
| `TalesForgeWeb` | `lib/ex_tales_forge_web.ex` | 114 | `use TalesForgeWeb, :live_view/:controller/...` macros |
| `TalesForgeWeb.CoreComponents` | `lib/ex_tales_forge_web/components/core_components.ex` | 505 | Phoenix generated components (22 callers) |
| `TalesForgeWeb.Endpoint` | `lib/ex_tales_forge_web/endpoint.ex` | 68 | Phoenix endpoint (application child) |
| `TalesForgeWeb.ErrorHTML` | `lib/ex_tales_forge_web/controllers/error_html.ex` | 24 | `render_errors` in config/config.exs |
| `TalesForgeWeb.ErrorJSON` | `lib/ex_tales_forge_web/controllers/error_json.ex` | 21 | `render_errors` in config/config.exs |
| `TalesForgeWeb.Gettext` | `lib/ex_tales_forge_web/gettext.ex` | 25 | Gettext backend (used by CoreComponents and the web macros) |
| `TalesForgeWeb.Layouts` | `lib/ex_tales_forge_web/components/layouts.ex` | 208 | Root/app/admin/play layouts |
| `TalesForgeWeb.Router` | `lib/ex_tales_forge_web/router.ex` | 118 | Phoenix router |
| `TalesForgeWeb.Telemetry` | `lib/ex_tales_forge_web/telemetry.ex` | 97 | Telemetry supervisor + LiveDashboard metrics (`/admin/oban`) |

## 3. Unused or dead (5 modules, 96 LOC)

| Module | File | LOC | Evidence / caller |
|---|---|---:|---|
| `TalesForge.Actions.NPC.EvaluateInitiative` | `lib/ex_tales_forge/actions/npc/evaluate_initiative.ex` | 19 | Jido action not listed in `NPCAgent` actions and never referenced; initiative is evaluated by `NPC.evaluate_initiative/2` instead. Since 2026-07-03. |
| `TalesForge.Images` | `lib/ex_tales_forge/images.ex` | 29 | No callers anywhere (lib, test, config). "Phase 2 stub" for Tigris images; last real change 2026-07-10. |
| `TalesForge.Workers.GenerateImage` | `lib/ex_tales_forge/workers/generate_image.ex` | 27 | Only enqueued by `TalesForge.Images` (itself unused). No-op worker; 0 jobs ever on prod or playtest. `images` Oban queue in config exists only for it. |
| `TalesForgeWeb.PageController` | `lib/ex_tales_forge_web/controllers/page_controller.ex` | 11 | Not in router.ex (`/` is HomeLive). Phoenix scaffold from 2026-07-02. Its test (`page_controller_test.exs`) actually tests HomeLive. |
| `TalesForgeWeb.PageHTML` | `lib/ex_tales_forge_web/controllers/page_html.ex` | 10 | Only for PageController; embeds `page_html/home.html.heex` (199 lines, the Phoenix welcome page). |

Also dead without being a module: `lib/ex_tales_forge_web/controllers/page_html/home.html.heex` (199 lines), the `images: 3` Oban queue in `config/config.exs`, and the commented `AWS_*`/Tigris block in `.env.example`.

## 4. Unsure (12 modules, 2884 LOC)

| Module | File | LOC | Evidence / caller |
|---|---|---:|---|
| `Mix.Tasks.Dev.Check` | `lib/mix/tasks/dev.check.ex` | 79 | Local env/model pre-flight check; README and AGENTS.md tell humans/agents to run it. Dev tool, not prod. |
| `Mix.Tasks.E2e.Smoke` | `lib/mix/tasks/e2e.smoke.ex` | 453 | Live-API smoke test from 2026-07-03 (`feature/grok-fast-llm`); README/AGENTS mention it. Overlaps with the playtest runner and `dev.check`. |
| `Mix.Tasks.Tales.ImportPack` | `lib/mix/tasks/tales.import_pack.ex` | 174 | Dev/ops task for the Ash pack importer; tables empty everywhere, so evidently unused. |
| `TalesForge.Authoring` | `lib/ex_tales_forge/authoring.ex` | 16 | Ash domain in `ash_domains` config. Live read paths (GameSessions, NPC, Admin) but **0 rows** in all three tables on prod and playtest; every read falls back to pack files. |
| `TalesForge.Authoring.Adventure` | `lib/ex_tales_forge/authoring/adventure.ex` | 98 | Read by `GameSessions.resolve_adventure_world_state/1` (rescue -> fallback). 0 rows prod/playtest. |
| `TalesForge.Authoring.Importer` | `lib/ex_tales_forge/authoring/importer.ex` | 914 | Only caller is `mix tales.import_pack`. Never run on prod/playtest (Authoring tables empty). No tests. Largest single file in lib (914 lines). |
| `TalesForge.Authoring.Location` | `lib/ex_tales_forge/authoring/location.ex` | 106 | Read by `GameSessions.load_authored_locations/1`. 0 rows prod/playtest. |
| `TalesForge.Authoring.NpcDefinition` | `lib/ex_tales_forge/authoring/npc_definition.ex` | 138 | Read by `NPC` and admin NPC-definition pages; written only by the admin "save" button. 0 rows prod/playtest. |
| `TalesForge.World` | `lib/ex_tales_forge/world.ex` | 433 | Flag `WORLD_AGENTS` (off on prod and playtest). Called from TurnProcessor/SceneProcessor/Context only when enabled. |
| `TalesForge.World.Agent` | `lib/ex_tales_forge/world/agent.ex` | 76 | Flag `WORLD_AGENTS`: GenServers started by `World` only when enabled (0 running). |
| `TalesForge.World.Extract` | `lib/ex_tales_forge/world/extract.ex` | 153 | Flag `WORLD_AGENTS`: `fact_extract` runs only when world agents exist (0 calls in the 13:00 Paul run). |
| `TalesForge.World.Prices` | `lib/ex_tales_forge/world/prices.ex` | 244 | Flag `WORLD_AGENTS`: `world_prices([] ...)` short-circuits when no agents; prompt section empty. |

## Flag-gated paths and legacy items (explicit)

| Item | State on main | Where | Prod / playtest | Verdict |
|---|---|---|---|---|
| `GM_REPLY_MODE` prose (unmerged #38) | **No remnants on main.** No `reply_mode`, `GM_REPLY` or prose mode in `lib/`, `config/` or `test/`. The only "prose" hits are a CSS class and a test string. | none | n/a | Nothing to remove |
| `WORLD_AGENTS` | `Config.world_agents?/0`; `World`, `World.Agent`, `World.Extract`, `World.Prices` (906 LOC) | TurnProcessor `world_agents/2`, SceneProcessor, Context prompt sections | off / off | Group 4. Keep: the design is current and the decision log says it's being tried |
| `NPC_REACTIONS` | `Config.npc_reactions?/0`; `Game.NpcReactions` | TurnProcessor `npc_reactions/5`, Context | off / **on** | Group 1 (flag-gated, in use on playtest) |
| Persona runner | `PLAYTEST_RUNNER_ENABLED` (config/runtime.exs); `Playtest.*` (7 modules), `mix playtest.run`, `/admin/playtest` | Runner, admin pages | 0 runs / **16 runs** | Group 1 (flag-gated, in use on playtest) |
| Collab importer | `Collab.Importer` (docs/decisions sync), `mix tales.sync_docs` | admin decisions/docs pages | **12 decisions, 13 docs** / 0 | Group 1: in use on prod. Not legacy |
| Ash authoring + pack importer | `Authoring` domain, 3 resources, `Authoring.Importer` (914 lines), `mix tales.import_pack` | GameSessions/NPC/Admin reads (fall back to pack files); admin NPC-definition save | **0 rows** in adventures/locations/npc_definitions on both | Group 4: the code paths are live, but the feature has never been used |
| Old character creation | **Not on main.** No chargen/create_character module. The pack importer parses a `player_characters` roster section but stores nothing ("RosterCharacter ... not this domain yet") | `Authoring.Importer` | n/a | Goes with the importer |
| Images (Tigris) | `Images` + `Workers.GenerateImage` stub | no callers | 0 jobs ever / 0 | Group 3 |
| LLM providers other than xAI | `LLM.request/4` branches for `gpt-*`/`openai` and `ollama/`; `resolve_tier_model/1` falls back to OpenAI, then Ollama, then Anthropic, then mock | `llm.ex` | xAI only | Unsure. **Latent bug:** with only `ANTHROPIC_API_KEY` set, the model becomes `anthropic/claude-3-5-haiku…`, but `request/4` has no Anthropic branch and returns `{:error, {:unsupported_model, _}}` |

## Dependencies in mix.exs

| Dep | Used by | Verdict |
|---|---|---|
| **`jido_ai ~> 2.2`** | **Nothing.** No `Jido.AI`/`ReqLLM` reference in `lib/`, `config/` or `test/` | **Unused.** Removing it drops 12 packages from the release: jido_ai, req_llm, llm_db, goth, ex_aws_auth, jsv, websockex, server_sent_events, fsmx, abnf_parsec, texture, toml. That's about **14.3 MB** of the 136 MB release |
| `igniter ~> 0.6` (dev/test) | No code references; optional for Ash/Jido generators (`mix ash.gen.*`) | Unused by our code. Keep only if someone runs the generators |
| `ash`, `ash_postgres`, `ash_phoenix` | Authoring (empty) + AdminResources (admin AshPhoenix forms) | Used. They could only go if Authoring is dropped **and** the two admin forms move to plain Ecto changesets |
| `yaml_elixir` | `Collab.Importer` (front matter) | Used |
| `dotenvy` | `config/runtime.exs` | Used |
| `mdex` | `Collab.Markdown` | Used |
| `assent` | `AdminAuth.GitHub` | Used |
| `time_zone_info` | `AICalls`, `CostsLive` (Europe/Stockholm) | Used |
| `jev` | `Game.NpcReactions`, `Playtest.JevScorer` | Used |
| `jido` | NPC agents, Actions, `TalesForge.Jido` | Used |
| `oban`, `swoosh`, `req`, `bandit`, `dns_cluster`, `telemetry_*`, `gettext`, `jason`, `heroicons`, `esbuild`, `tailwind`, `phoenix_*`, `ecto_sql`, `postgrex`, `lazy_html` (test), `credo`/`dialyxir`/`ex_doc` | framework / tooling | Used |

## Appendix: public functions with no callers in lib/

Name-based scan (excluding callbacks and Ash/Jido generated functions):

| Function | LOC | Used in tests? | Note |
|---|---:|---|---|
| `Playtest.Reports.cost_by_purpose/1` | 17 | no | Dead |
| `Collab.get_decision!/1` | 1 | no | Dead |
| `Config.log_level/0` | 1 | no | Dead |
| `Fronts.list_live/1` | 1 | no | Dead |
| `Game.TurnProcessor.simulate!/5,6` | 23 | 5 test files | Test harness in lib. Move to `test/support`, don't delete |
| `Game.Prompts.build_scene_user/1` | 3 | yes | Test-only |
| `NPCRecovery.recover_now/0` | 3 | yes | Test-only |
| `AICalls.Steps.purposes/0`, `Playtest.AffectLevels.persona_ids/0`, `Game.WorldSim.accept_chronicler_move/2`, `AdminAuth.MembershipCache.clear/0` | 1 each | yes | Test-only helpers |

No module is used **only** by tests. `TalesForgeWeb.PageController`'s test (`page_controller_test.exs`) doesn't touch PageController at all: it tests HomeLive at `/`.

## Removal proposal, ranked by safety

| # | Change | LOC removed (lib) | Risk | Notes |
|---:|---|---:|---|---|
| 1 | Delete `PageController`, `PageHTML`, `page_html/home.html.heex`; rename `page_controller_test.exs` to `home_live_test.exs` | 21 + 199 template | **None**: not routed | Pure Phoenix scaffold |
| 2 | Delete `Images`, `Workers.GenerateImage`, the `images` Oban queue, and the Tigris block in `.env.example` | 56 (+ config lines) | **Very low**: no callers, 0 jobs ever on either env | Bring back if image generation gets built |
| 3 | Delete `Actions.NPC.EvaluateInitiative` | 19 | **None**: not registered on `NPCAgent` | |
| 4 | Delete dead functions `Reports.cost_by_purpose/1`, `Collab.get_decision!/1`, `Config.log_level/0`, `Fronts.list_live/1` | ~20 | **Very low** | Covered by compile + tests |
| 5 | Drop `jido_ai` from mix.exs | 0 (12 packages, ~14.3 MB release) | **Low**: nothing references it; check compile, Dialyzer, release boot | Biggest win for the smallest change |
| 6 | Move `TurnProcessor.simulate!` (and other test-only helpers) to `test/support` | ~25 moved | Low | Keeps lib honest; not a deletion |
| 7 | Fix or remove the non-xAI LLM fallbacks (the Anthropic branch is broken; OpenAI/Ollama untested in CI) | 3 (Anthropic) to ~70 (all non-xAI) | Low–medium: someone may run Ollama/OpenAI locally | Fredrik's call |
| 8 | Retire `mix e2e.smoke` (and maybe `mix dev.check`) in favour of the playtest runner | 453 (+79) | Medium: documented in README/AGENTS.md; update the docs too | Ask whether anyone still runs them |
| 9 | Retire the Ash authoring layer: `Authoring` domain, 3 resources, `Authoring.Importer`, `mix tales.import_pack`, the Ash read paths in GameSessions/NPC/Admin, and the admin NPC-definition save (becomes read-only from pack JSON); migration to drop the 3 empty tables | ~1,446 + ~100 in callers | **Medium–high**: product decision (README Phase 2 plan); no data loss (0 rows on both envs) | If AdminResources' two AshPhoenix forms also move to Ecto, `ash`, `ash_postgres` and `ash_phoenix` can go too (+293 LOC, larger refactor) |
| — | World agents (`World.*`, 906 LOC) | keep | — | Off everywhere, but still being tried per the decision log |

Items 1–5 together: about 116 lines of lib code, a 199-line template, 12 packages and about 14 MB of release, at very low risk.
