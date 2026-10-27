# Architecture review: Tales Forge (October 2026)

By Alva, the WhyseFlow architect, as part of a review swap. This doc only asks questions and points out gaps and opportunities. Every claim cites a file and line at the sha below. None of it is a request to change anything.

## 1. What I read

Sha: `8a5a7ac32ede45b1e3f89419f3b0cc919f072ec9` on `main`, the merge of #599 (27 Oct 2026, 17:35 CET).

Files:

- Docs: `docs/principles.md`, `docs/decisions.md` (mainly the 2026-10-12 entries), `AGENTS.md`, `docs/health/README.md`.
- Turn entry: `lib/ex_tales_forge_web/live/play_live.ex`, `lib/ex_tales_forge/game_sessions.ex`, `lib/ex_tales_forge/game_sessions/turn_request.ex`.
- Job and serialiser: `lib/ex_tales_forge/workers/process_turn.ex`, `workers/process_scene.ex`, `workers/push_work_log_turn.ex`, `lib/ex_tales_forge/world/instance.ex`, `world/turn_request.ex`.
- Pipeline: `lib/ex_tales_forge/game/turn_processor.ex`, `game/turn.ex`, `game/turn/adapters.ex`, `game/turn/gm.ex`, `game/turn/store.ex`.
- LLM: `lib/ex_tales_forge/llm.ex`, `lib/ex_tales_forge/llm/{request,endpoint,gm_turn,stream}.ex`, `lib/ex_tales_forge/config.ex`.
- Runtime: `lib/ex_tales_forge/application.ex`, `config/config.exs`, `config/runtime.exs`, `config/prod.exs`, `config/test.exs`, `fly.toml`.
- Data: `lib/ex_tales_forge/schemas/game_session.ex`, `priv/repo/migrations/20260702190000_create_game_core.exs`, the list of 57 migrations.
- Tests: `test/test_helper.exs`, `test/ex_tales_forge/world/instance_test.exs`, `test/ex_tales_forge/workers/process_turn_test.exs`, `test/ex_tales_forge/turn_pipeline/*`, the layout of `test/`.

What I ran, locally, with no secrets and no network calls to any service:

- `mix compile`: OK. The one warning is inside the Oban dependency (`lib/oban/repo.ex:253`), not in this app.
- `mix health.check --out /tmp/health.json`: exit 0 against `origin/main`. It found 0 dependency cycles, 0 web references from the domain, 48 complex functions (limits: ABC 30, cyclomatic 9) and 3 functions with 4+ params. Two of the three are `on_mount/4`, a shape LiveView dictates. The third is `Mix.Tasks.Health.Snapshot.segment/5`.
- `mix test test/ex_tales_forge/world/instance_test.exs test/ex_tales_forge/workers/process_turn_test.exs test/ex_tales_forge/turn_pipeline`, against a local Postgres with `LLM_PROVIDER=mock`: 56 tests, 0 failures, 28 excluded as `:pending`.
- Not run: `mix health.snapshot`, because it writes to `docs/health/`. `mix dev.check`, because it inspects API keys. `mix e2e.smoke`, because it needs a live LLM.

## 2. Summary

1. **Can a turn be enqueued twice?** `ProcessTurn` has no `unique` option, and the clarification clear and `Oban.insert` are not in one transaction (Q1).
2. **Can the submit path overwrite `world_state` while a turn runs?** It writes outside both `World.Instance` and the advisory lock (Q2).
3. **What happens to a turn that outlives its caller?** That covers the 180 s call timeout, the blue-green deploy overlap, the 20 s shutdown grace and PubSub stopping before Oban (Q3 to Q5).

## 3. Questions

### Q1. What stops one player action from becoming two turns?

- Evidence:
  - `ProcessTurn` is `use Oban.Worker, queue: :llm, max_attempts: 1` with no `unique:` (`lib/ex_tales_forge/workers/process_turn.ex:15`).
  - `ProcessScene` does have one: `unique: [period: 60, fields: [:args], keys: [:session_id], states: :incomplete]` (`workers/process_scene.ex:10`).
  - `enqueue_turn` clears the clarification with its own `Repo.update`. It then inserts the job in a second, separate step (`lib/ex_tales_forge/game_sessions.ex:594-606`, `:640-646`).
  - The `case` after `clear_clarification` only matches `{:ok, session}` (`game_sessions.ex:596-597`). A changeset error would become a `CaseClauseError`, not `{:error, _}`.
  - `World.Instance` serialises turns but does not drop repeats. Its test plays two submits as turns 1 and 2 (`test/ex_tales_forge/world/instance_test.exs:58-98`).
- Why it matters:
  - A double click or a LiveView reconnect that re-sends the event can play the same action twice. That costs two GM calls.
  - The second turn is real game state. Mechanics, coins and time all move twice.
- Opportunity: a client-side id for the submit, carried in the job args and in an Oban `unique` key. Or `Ecto.Multi` with `Oban.insert/3`, so the clear and the insert commit together.

### Q2. Can the submit path and a running turn overwrite each other's `world_state`?

- Evidence:
  - `save_clarification` and `clear_clarification` write a full `world_state` map built from the session the submit path loaded (`game_sessions.ex:631-646`). They do not go through `World.Instance` or the advisory lock.
  - The turn writes `world_state` from the session it read at the start (`game/turn_processor.ex:65`, `game/turn/store.ex:166`).
  - The advisory lock is taken inside the turn transaction (`store.ex:188-198`), so it covers the write but not that earlier read.
- Why it matters:
  - If a player sends a second message while a turn runs (the instance test shows this is possible), one write can drop the other's keys. For example, a pending clarification could vanish, or a turn's world tick could roll back.
  - This kind of bug is rare and hard to reproduce.
- Opportunity: run clarification writes through the same per-session path as turns. Or add an optimistic lock (`lock_version`) on `game_sessions`, so a stale write fails loudly.

### Q3. What should happen when a turn outlives the 180 s call timeout?

- Evidence:
  - `@call_timeout :timer.seconds(180)`, with the comment "Covers the GM call and its JSON retry" (`world/instance.ex:43-44`).
  - The timeout starts when the job calls. Time spent waiting behind earlier turns in the queue counts too (`instance.ex:94`, `:126-128`).
  - Each LLM request has `receive_timeout: 120_000` (`llm.ex:908`, `:955`). A JSON retry sends a second request (`llm.ex:673-677`), so two requests can take more than 180 s.
  - On timeout the job gets `{:error, {:turn_down, _}}` (`instance.ex:105-106`). The request stays in the Instance queue and may still run and commit. The job, with `max_attempts: 1`, is recorded as failed (`process_turn.ex:15`, `:39`).
  - Each waiting job holds one of the 5 `llm` queue slots on the machine (`config/config.exs:29`).
- Why it matters:
  - Oban's record says "failed" for a turn that later succeeds. That makes support and cost analysis harder.
  - A slow provider can fill the 5 slots, so other sessions wait.
- Opportunity: a total time budget for the turn, checked in one place. Or start the timeout when the turn leaves the queue, not when the job calls.

### Q4. During a blue-green deploy, which machine owns a session?

- Evidence:
  - A deploy runs a second machine for about a minute (`fly.toml:19-22`).
  - The Registry that finds an Instance is node-local (`instance.ex:74`, `application.ex:15`). `DNSCluster` is in the tree (`application.ex:19`).
  - The turn number is read before the lock (`turn_processor.ex:71`, `store.ex:270-279`). The unique index on `turns [:game_session_id, :turn_number]` (`priv/repo/migrations/20260702190000_create_game_core.exs:29`) would reject the second of two parallel turns. The comment calls the advisory lock a backstop for "another machine, a script" (`store.ex:188-192`).
- Why it matters:
  - Two parallel turns for one session can happen during every deploy. The outcome is a turn error that the player sees as "Turn failed".
  - It is cheap to answer now, while production runs one machine.
- Opportunity: read `next_turn_number` inside the locked transaction. Or decide that a deploy-time collision is acceptable and write that down in `docs/decisions.md`.

### Q5. Does shutdown order let a turn finish cleanly in the grace period?

- Evidence:
  - Children stop in reverse order. `Phoenix.PubSub` starts after Oban (`application.ex:18`, `:20`), so it stops before Oban's 20 s `shutdown_grace_period` ends (`config/config.exs:30-33`).
  - A turn that finishes in that window broadcasts `{:turn_completed, payload}` (`turn_processor.ex:105`). The comment at `application.ex:13-14` covers the Instance and Task, not PubSub.
  - The grace period is 20 s, while one GM request may take up to 120 s (`llm.ex:908`).
  - A killed job is rescued by Lifeline after 5 minutes (`config/config.exs:41-44`). With `max_attempts: 1` it is then discarded, and nothing tells the player.
- Why it matters: a deploy mid-turn can leave the play page waiting, or commit a turn whose broadcast fails.
- Opportunity: start PubSub before Oban. And decide what the player should see when a turn is lost to a deploy.

### Q6. Is `TalesForge.LLM` one module or several?

- Evidence:
  - `llm.ex` has 1179 lines and 9 `complete_*` functions with the same shape: pick a model, check `mock?`, build a `%Request{}`, call `complete_json` (for example `llm.ex:180-214` and `:217-239`).
  - The same file holds schemas, provider choice, HTTP transport for xAI, OpenAI and Ollama, streaming state, spend-cap checks, `ai_calls` recording and mocks (`llm.ex:668-1050`, `:1126-1150`).
  - `mix health.check` lists three of its functions as complex: `conv_id`, `maybe_emit`, `stream_openai_compatible`.
  - The SSE parsing already moved out to `llm/stream.ex` (145 lines), and `Request` is a struct (`llm/request.ex`).
- Why it matters:
  - DRY and orthogonality. A new purpose copies a block.
  - A provider change touches the same file as a prompt-budget change.
- Opportunity: one table of purposes (tier, max_tokens, temperature, schema, validator), plus a provider behaviour. The `complete_*` functions would then become one-liners.

### Q7. Is the provider fallback chain still wanted?

- Evidence:
  - With no `TIER*_MODEL` set, the model falls back through xAI, OpenAI, a live Ollama probe and Anthropic (`llm.ex:1126-1133`).
  - `send_request` has no Anthropic branch, so that choice ends in `{:error, {:unsupported_model, _}}` (`llm.ex:783-796`).
  - Without an xAI key, each `tier*_model()` call can make an HTTP probe with a 1.5 s timeout (`llm.ex:1138-1149`). `tier2_model()` runs on every GM call (`llm.ex:587`).
  - `AGENTS.md:363` says "never Ollama" when the xAI key is set.
- Why it matters:
  - Dead branches are reading cost.
  - A local setup without an xAI key gets slow turns or a confusing error.
- Opportunity: decide which providers are supported, and remove the rest. Or move the choice to boot time, in `config/runtime.exs`.

### Q8. Is "no spend caps in production" a deliberate, written decision?

- Evidence:
  - "Production has no caps set; playtest has session and day caps" (`AGENTS.md:179`).
  - Caps are nil when the env var is unset (`config/runtime.exs:279-295`). They are checked before each request (`llm.ex:733-736`).
  - The JSON-correction retry sends the full prompt again (`llm.ex:673-677`). The prompt-cache comment says the retry keeps the cached prefix (`llm.ex:63-64`).
- Why it matters: running cost. A loop, a bot, or a spike of invalid JSON has no upper bound in production.
- Opportunity: a generous day cap as a fuse. Changing a cap needs Fredrik's OK (`AGENTS.md:179`), so this is a question for him.

### Q9. How pure are the pipeline stages today?

- Evidence:
  - The decision says stages are pure, IO sits behind adapters, and no ad hoc `Map.put` (`docs/decisions.md:566-567`).
  - In the code:
    - `Turn.new` reads the cast from the DB by default (`game/turn.ex:122`).
    - `Store` reads it again if it is missing (`game/turn/store.ex:182`).
    - `TurnProcessor.run` does `Repo.get` and `next_turn_number` before the pipe (`turn_processor.ex:65`, `:71`).
  - Some fields are loose: `outcome: map()` and `prompt: map()` (`turn.ex:74`, `:76`). The `gm` adapter is typed as a bare `function()` (`game/turn/adapters.ex:32`).
  - `Store.persist` ends with `Map.put(:npc_initiatives, ...)` (`store.ex:71`).
- Why it matters:
  - "Pure core, effects at the edges" (`docs/principles.md:14-15`).
  - Loose types hide where a field is written. Hidden reads make the replay tests depend on the DB.
- Opportunity: load the cast and the turn number once, at the edge, into the struct. Then give `outcome` and `prompt` their own structs.

### Q10. Why are there two ways to persist a turn and two `TurnRequest` structs?

- Evidence:
  - `TurnProcessor.simulate!/2` (`@doc false`) builds a `Store` directly, beside the main pipe (`turn_processor.ex:137-171`).
  - `TalesForge.GameSessions.TurnRequest` (`game_sessions/turn_request.ex:1`) and `TalesForge.World.TurnRequest` (`world/turn_request.ex:1`) share a name but are different structs.
  - The two intent paths each look up a clarification option and raise on a miss (`game_sessions.ex:448-453` and `:500-509`).
- Why it matters:
  - DRY. A fix to persistence or option handling has two places to land.
  - Two structs with one name slow down readers and agents.
- Opportunity: route `simulate!` through `Turn.Outcome.persist`. Rename one struct, for example `SubmitRequest`. Share the option lookup.

### Q11. Should bad input from the client raise?

- Evidence:
  - An unknown `option_id` raises `ArgumentError` (`game_sessions.ex:451`, `:508`). So does a clarification that vanished between two reads (`game_sessions.ex:550`). The option id comes from the play page event `pick_clarification` (`play_live.ex:55-58`, `:261`).
  - `AGENTS.md:265` says `raise` is for programmer bugs. The turn decision says "a rejected action is data on the struct, not an exception" (`docs/decisions.md:568`).
  - `ClarificationNeeded` uses raise and rescue as control flow (`game_sessions.ex:494`, `:339-340`). `AGENTS.md:265` allows that one by name.
- Why it matters:
  - A stale or crafted event crashes the LiveView process, and the player sees a reconnect.
  - It is also easy to change: `action_text/3` already returns `{:error, :clarification_expired}` (`game_sessions.ex:247-248`).
- Opportunity: return `{:error, :invalid_option}` like `:clarification_expired`. `submit_failed/2` already shows a flash for that (`play_live.ex:273-279`).

### Q12. Is the string-keyed `world_state` map the main barrier to easy change?

- Evidence:
  - `world_state` appears 284 times in `lib/`.
  - The key `"world_tick"` alone is read in 19 files (29 uses).
  - The field is one custom type, `TalesForge.Schemas.WorldState` (`schemas/game_session.ex:21`). Writers use `Map.put` on it (for example `game_sessions.ex:632-633`).
- Why it matters:
  - "Structs flowing through functions" and DRY of knowledge (`docs/principles.md:8-9`, `:32`).
  - Renaming a key, or knowing who writes it, means a grep across the app. The compiler does not help.
- Opportunity: a small struct, or accessor functions, for the keys the turn reads and writes. That would be a step on the way to the Character plan's read switch (`AGENTS.md:73`).

### Q13. What is the Instance cache for, today?

- Evidence:
  - "Its state is a cache, never the truth … Nothing reads the cache yet" (`world/instance.ex:26-28`).
  - It still runs `load/1` after every turn (`instance.ex:136`): a `Repo.get` and `Store.list_for_session` (`instance.ex:191-202`).
- Why it matters: two queries per turn for data nobody reads. The cost is small, but so is the payoff.
- Opportunity: load lazily when a reader appears, or note which coming step needs it.

### Q14. How far has AGENTS.md drifted from the code?

- Evidence:
  - "Last checked against `main`" (`AGENTS.md:7-8`).
  - It names `NpcInstance` (`AGENTS.md:30`, `:375`), `npc_instances` (`:73`), `NPCRegistry`/`NPCAgent`/`NPCRecovery` (`:378`) and `actions/npc/` (`:406`). None of these appear in `lib/`, and the `npc_instances` table has a drop migration (`priv/repo/migrations/20261021190000_drop_npc_instances.exs`).
  - "Two-tier LLM … a small-model LLM call" (`AGENTS.md:349-351`) contradicts "no intent LLM call" (`AGENTS.md:74`, `docs/decisions.md:606`).
  - The test name "gives an error Oban retries" (`test/ex_tales_forge/world/instance_test.exs:101`) predates `max_attempts: 1`. Its body already plays the retry as a new player action (`:135-137`).
- Why it matters: agents read AGENTS.md first. Stale structure sends them to code that does not exist, and that costs time on every task.
- Opportunity: a check like `mix docs.check_links` that fails when a module named in AGENTS.md does not exist.

### Q15. Which turn-pipeline behaviours have no test?

- Evidence:
  - All unit tests run with `LLM_PROVIDER=mock` (`test/test_helper.exs:3`). The HTTP path is stubbed with `Req.Test` in 12 files.
  - The replay suite tags items `:pending` until their PRs land (`test/ex_tales_forge/turn_pipeline/replay_test.exs:31`). In my run, 28 tests were excluded.
  - I found tests for serialisation (`instance_test.exs:58`), a killed instance (`:101`) and no retry after a GM error (`process_turn_test.exs:23`).
  - I did not find tests for a double submit through Oban (Q1), the 180 s timeout (Q3), or a write race on `world_state` (Q2).
  - The coverage threshold is 72% (`mix.exs:153`).
- Why it matters: "Prove it" (`docs/principles.md:28-29`). The gaps are exactly the paths that cost money or corrupt state.
- Opportunity: one test per question above. They can use the existing `stub_llm` helper and the `:go` message pattern from `instance_test.exs:61-71`.

## 4. What looks strong

- **The turn is really one pipe.** You can read the whole turn in ten lines (`turn_processor.ex:73-86`), and the IO sits behind named adapters (`game/turn/adapters.ex`).
- **The commit is one transaction.** The turn, events, NPC rows and the work-log job commit together (`store.ex:149-186`, `:168`). The work-log push is deduplicated on the Workflow side (`workers/push_work_log_turn.ex:7-11`).
- **Prompt-cache care is written down and measured.** Schema order, an appended retry and per-purpose `x-grok-conv-id` all have dated measurements in the comments (`llm.ex:57-61`, `:63-66`, `:845-860`).
- **Secrets stay out of code and tests.** Keys come from the environment (`config.ex:13-15`, `config/runtime.exs:189`, `:237`). Tests force the mock provider and nil keys (`test/test_helper.exs:3`, `config/test.exs:72-82`). Bad cap and threshold values fail at boot (`config/runtime.exs:206`, `:287`).
- **The health ratchet works and is cheap.** It ran locally in a few seconds, and it reports cycles, web references and wide functions at zero or near zero.
- **Spend is visible.** Every call writes an `ai_calls` row with purpose, latency, TTFT and conv id (`llm.ex:812-836`). Spend caps are checked before the request, not after (`llm.ex:733`).
