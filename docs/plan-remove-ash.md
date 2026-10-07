---
title: "Plan: remove Ash (plain Ecto)"
updated: 2026-10-07
status: plan (code not started; waiting for go-ahead)
---

# Plan: remove Ash, keep plain Ecto

Decision: [Ash removed for now; plain Ecto](decisions.md#2026-10-07-ash-removed-for-now-plain-ecto-revisit-if-an-in-app-adventure-editor-needs-it) (Fredrik via Case, 2026-10-07). Evidence: the [module audit](module-audit-2026-10-07.md).

**Why it's safe:** only two things use Ash.
- **The authoring layer.** Its three tables (`adventures`, `locations`, `npc_definitions`) have **0 rows on prod and playtest**. Every read already falls back to the pack files in `priv/`.
- **Four admin "resources".** They are thin Ash wrappers over tables that already have Ecto schemas.

The game loop is Ecto-only already (`TurnProcessor`, `Context`, `ActionHandler` say "No Ash").

## 1. What goes

| Remove | Lines | Notes |
|---|---:|---|
| `TalesForge.Authoring` (domain) and `Authoring.Adventure`, `Authoring.Location`, `Authoring.NpcDefinition` | 358 | Ash resources over the 3 empty tables |
| `TalesForge.Authoring.Importer` | 914 | Markdown pack importer into those tables; never run on prod/playtest, no tests |
| `mix tales.import_pack` (+ alias in `mix.exs`) | 174 | Only caller of the importer |
| `TalesForge.AdminResources` (domain) and `AdminResources.GameSession`, `.Turn`, `.NpcInstance`, `.Scene` | 293 | Replaced by the existing Ecto schemas (below) |
| **Fallback code in the callers:** `GameSessions.resolve_adventure_world_state/1` and `load_authored_locations/1` (Ash reads, then rescue to defaults); `NPC` "prefer Ash defs" branch and `ash_npc_to_definition_map/1`; the Ash branches in `Admin.list_npc_definitions/0`, `get_npc_definition!/1`, `save_npc_definition/2` | about 100 | After this, the pack files are the only source, as they already are in practice |
| Config: `ash_domains: [...]`, `config :ash, ...`; `:ash` in `.formatter.exs` `import_deps` | ~5 | |

## 2. The admin edit forms on plain Ecto

Only two forms use `AshPhoenix.Form`. Neither edits authoring data: both edit **live session data that already lives in Ecto tables with Ecto schemas and changesets**. So the data stays where it is; only the form plumbing changes.

| Page | Edits | Table (unchanged) | Ecto replacement |
|---|---|---|---|
| `/admin/sessions/:id` (`SessionLive.Show`) | `name`, `status`, `world_state`, `world_clock` | `game_sessions` | `Schemas.GameSession.changeset/2` (already casts these four fields and validates status) via `to_form/1`; save with `Repo.update/1` |
| `/admin/sessions/:id/npcs/:npc_id` (`NpcLive.Show`) | `personality`, `runtime_state`, `disposition` | `npc_instances` | `Schemas.NpcInstance.changeset/2` (already casts these) or a narrower `admin_changeset/2` that casts only those three |

The other admin uses of `AdminResources` move to `Repo` calls in `TalesForge.Admin`:
- dashboard counts: `Repo.aggregate(:count)` instead of `length(Ash.read!(...))`, which is also cheaper;
- session list, sorted by `inserted_at`;
- NPC instance lookup by session and NPC id;
- **session delete:** `Repo.delete/1`. The child tables (`turns`, `scenes`, `npc_instances`, `session_events`, `front_instances`, `playtest_runs`) already have `on_delete: :delete_all` foreign keys, and `ai_calls` uses `:nilify_all`. Behaviour stays the same.

**Pack-derived NPC definitions** (`/admin/npc-definitions/:id`) are the only screen that writes authoring data. Its "save" button writes an Ash `NpcDefinition` row, and has never been used: 0 rows anywhere.

**Recommendation:** make the NPC-definition pages **read-only views of the pack JSON** (`priv/npcs`, the adventure packs) and remove the save button. Content changes go through the pack files in git, which matches [Game data vs sessions](design-game-data-vs-sessions.md): game data is versioned and published, not edited live.

I don't recommend new Ecto "override" tables for pack data now. Nobody has used the feature, it would bring back a second source of truth, and the decision already says to revisit if an in-app adventure editor is needed. If that happens, design the editor and its tables then.

## 3. Migration: drop the 3 empty tables

New migration, e.g. `priv/repo/migrations/2026100xxxxxxx_drop_authoring_tables.exs`.

`up`:
1. **Safety check first.** Count the rows in `adventures`, `locations` and `npc_definitions` with `repo().query!/1`. If the total is above 0, `raise` with the counts and a message to export the rows first. Nothing is dropped, and the deploy's release command fails, so the machine keeps running the old release.
2. `drop table(:locations)`, `drop table(:adventures)`, `drop table(:npc_definitions)`. No other table references them, and they have no foreign keys.

`down`: recreate the three tables and their indexes exactly as in `20260709120000`/`121000`/`122000`, copied into the migration so it doesn't depend on deleted code. Rollback restores the schema; there's no data to restore.

Keep the three original create migrations (history); the new one supersedes them.

## 4. Dependencies

- Remove `ash`, `ash_postgres` and `ash_phoenix` from `mix.exs`, then `mix deps.unlock --unused`. In prod this also drops `ash_sql`, `spark`, `reactor`, `crux`, `ets`, `iterex`, `stream_data` and `ymlr` (11 apps). `splode` stays because `jido` uses it.
- **`igniter`** (dev/test only): our code doesn't use it; it was there for the Ash generators. `jido` lists it as optional. **Remove it** too; no release impact.

## 5. Tooling, standards and tests

- **Credo:** no Ash-specific config. Credo strict must stay clean.
- **Dialyzer:** the PLT cache key includes `mix.lock`, so the first CI run rebuilds it (about 5 min). Must stay at 0 warnings with an empty ignore file.
- **Coding standards:** `coding_standards_test` and the `Readability.Specs` file list don't include Ash modules, so no list changes. The rewritten `Admin` functions and the two LiveViews follow the rules (moduledoc, `@doc`/`@spec` on public functions).
- **ExDoc:** remove the `Authoring`/`AdminResources` groups from `groups_for_modules` in `mix.exs` if listed.
- **Tests:**
  - The existing `session_live_test.exs` and `npc_live_test.exs` cover the two forms. They must pass unchanged, plus a validation-error case each.
  - Add tests for `Admin` counts and session delete (children deleted, `ai_calls` nilified).
  - Add tests for NPC-definition pages being read-only.
  - Add a migration test, or a check in CI, that the safety check raises when a row exists.
  - Keep coverage at or above the 72% floor. Removing the untested 914-line importer should raise it.
- **Docs:** update `README.md` (Phase 2 line), `AGENTS.md` and `docs/architecture.md` in the code repo, and [Why Elixir](why-elixir.md)'s Ash mentions with a pointer to the decision.

**Expected size:**
- about **−1,800 lines** in `lib/`: about −1,740 removed modules, about −100 in callers, plus a little added for the Ecto forms;
- about **−11 MB** of release (11 apps), measured on the post-#46 release;
- with #46 (−15 MB), the release goes from about 114 MB to about 88 MB (local prod release, no code docs).

## 6. Rollout

Prod and playtest both run `/app/bin/migrate` as the Fly release command before the new machines start.

| Risk | Likelihood | Mitigation |
|---|---|---|
| Rows appear in the authoring tables before the deploy (e.g. someone presses "save" on an NPC definition) | Low | The migration's safety check aborts, so the release command fails and the old release keeps running. Before merging, run the same counts read-only on both apps. |
| An admin page still calls Ash somewhere that was missed | Low | `mix compile --warnings-as-errors` fails on any leftover `Ash.*` call once the deps are gone. LiveView tests cover all admin pages. |
| Session delete behaves differently | Low | The behaviour comes from DB-level foreign keys, not Ash. A test asserts that children are deleted. |
| Playtest and prod diverge | Low | Same SHA. Playtest deploys after prod via the existing workflow; check `/admin/sessions/:id` and an NPC edit on playtest first. |

**Order:**
1. Code PR (CI green: Test and Dialyzer).
2. Read-only row counts on prod and playtest (all 0).
3. Merge after Fredrik approves. CI deploys prod; check `Migrations` in the release-command log, 200s, `/admin`, and a session and an NPC edit.
4. The playtest workflow follows; same checks.

**Rollback:**
- **Code:** redeploy the previous release (`fly deploy --image <previous image>`, or revert the merge on main and let CI deploy). The old code would find its three tables missing.
- **Tables:** so before redeploying old code, run the migration's `down` (`bin/ex_tales_forge eval 'Ecto.Migrator.run(TalesForge.Repo, :down, to: <version>, all: false)'`, or `rollback` from a one-off machine) to recreate the empty tables. The old code would also start without them, since every Ash read has a rescue fallback, but the admin NPC-definition and session pages would error.
- **No data can be lost:** the tables are empty, and the safety check guarantees it.
