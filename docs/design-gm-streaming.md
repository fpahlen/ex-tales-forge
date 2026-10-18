---
title: "Design: stream GM narration and hand the turn back at narrative close"
updated: 2026-10-18
status: design for review (no code)
---

# Design: stream GM narration, hand the turn back at narrative close

**Status:** design, 2026-10-18. No code yet. Reviewer: Case.

**Intent (Fredrik, approved):** the player gets the turn back when the `narrative` field closes, not when the whole JSON reply ends. The narrative streams to the page. State still commits **once**, with the full reply, in the same place as today. The tail (`npc_memory_updates`, `context_summary`) is processed after the narrative. Engine results (trades, rolls) come from code, and the GM narrates only actual outcomes ([#470](https://github.com/whyse-ab/ex-tales-forge/pull/470) adds the trade outcome to the prompt).

**Why:** on prod (`:lean`, `grok-4.20-0309-non-reasoning`, `max_tokens` 700) the first token comes at 551-724 ms and the call ends at 4.9-5.4 s, at about 12.3 ms per token. The narrative closes at about 3.6 s (token 234). The tail is about 122 tokens and 1.3-1.7 s, so about 25% of the wait is bookkeeping the player never reads ([LLM latency, 2026-10](experiments/2026-10-llm-latency.md), #467/#468).

## 1. Current state

Streaming is **on for every GM turn, on prod and playtest, with no flag**. #191 ("GM: stream the narration; lean GM reply on production") and #197 (the player's action before the streamed reply; Act disabled until the page connects) were merged on 2026-10-12.

- **LLM client.** `TalesForge.LLM.complete_turn/5` always sends `stream: true` (`gm_opts/3`). `stream_openai_compatible/3` reads the SSE chunks with Req `into:`. `TalesForge.LLM.Stream.events/1` and `decode_event/1` split and decode them. `Stream.partial_narrative/1` reads the `narrative` string from the partial JSON. `maybe_emit/2` calls `on_text.({:text, narrative_so_far})` at most every `:llm_stream_throttle_ms` (75 ms), plus once at the end. `ai_calls.ttft_ms` records the first token. `receive_timeout` is 120 s.
- **Schema order.** `narration_schema/1` builds the properties with `Jason.OrderedObject`. `narrative` comes first in both variants (`:lean`: `narrative, npc_memory_updates, context_summary`; `:full` adds `location_name` second). Strict `json_schema` writes keys in schema order, so the narrative always comes first. Only `narrative` is `required`.
- **Retry.** `complete_json/2` retries once on `:invalid_json` or `:invalid_reply` (`valid_gm_reply?/1`: the narrative is not blank). It sends `:reset` first, and the retry streams new text. A transport error or timeout has no retry in the call. The turn returns `{:error, _}`, `TurnProcessor.finish/2` broadcasts `:turn_failed`, and then `Workers.ProcessTurn` (`max_attempts: 3`) runs the **whole turn again**. That retry streams new text onto a page that has already said "Turn failed".
- **To the page.** `Turn.Gm.narrate/1` passes `on_text: &adapters.stream.(session.id, &1)`. `Turn.Adapters.broadcast/2` sends `{:turn_stream, chunk}` on the session PubSub topic. `PlayLive.handle_info({:turn_stream, {:text, text}})` assigns `:streaming_text`. `PlayComponents` renders it in `#gm-streaming`, and shows "The GM is thinking…" while the text is empty.
- **Lock and commit.** `:thinking` stays true until `{:turn_completed, _}`. That message is broadcast only after `Turn.Outcome.persist/1` (prose check, NPC memory, the store Multi). Input and Act stay disabled until then, so the player waits for the tail and the commit. Turns run one at a time per session in `World.Instance` (a queue).

So the text already appears early. What is missing: a signal when the narrative closes, the unlock at that point, a paced reveal, the minimum delay, and a safe failure path once text has been shown.

## 2. Design

**Narrative close.** `Stream.partial_narrative/1` returns `{:open | :closed, text}`. Its reader already stops at the closing quote. The client emits `{:closed, narrative}` once, right away (no throttle), and records `narrative_ms` on the `ai_calls` row next to `ttft_ms`. The incremental parser stays as it is: it reparses the buffer each time, and at about 1 KB of narrative that costs little.

**Transport (framework first).** Keep what #191 built: PubSub `{:turn_stream, …}` on the session topic to `PlayLive.handle_info/2`. This also covers several tabs and the playtest runner. Each event still carries the whole text so far, so a lost or doubled event does no harm. PlayLive passes the text to the client with `push_event("gm_text", %{text, closed})`.

**Reveal (client).** A colocated hook (`GmReveal`) owns a `phx-update="ignore"` container. It shows characters at a steady pace from a buffer of the received text. **Slick's pace:** about **30 ms per character** (roughly 350-400 wpm, a little faster than reading), plus **150 ms extra at sentence ends** (`.`, `!`, `?`, `…`). A tap on the story, or a scroll, shows the rest at once. Why on the client: a pace of 30 ms per character done from the server would mean about 33 diffs per second per player, with jitter from the socket. The stream delivers about 330 characters per second, ten times the reveal rate, so the buffer never runs dry after the first chunk and the text does not jerk. At this pace a 1,000-character narrative takes about 30 s to reveal, so for most turns the commit (about 5.3 s) lands long before the reveal ends.

**Minimum delay.** The dots show from the moment the submit is taken (the pending action from #197). The text starts at `max(min_delay, first narrative chunk)`, default **1.5 s**. The hook times this from the moment it mounts the dots.

**Unlock rule: narrative closed AND reveal finished (or skipped by a tap).** The narrative closing alone is not enough: input that unlocks while the text is still revealing invites an action on text the player has not read yet. The tap makes this a choice, not a wait. When the reveal ends, the hook sends `pushEvent("gm_revealed")`. PlayLive then unlocks if the narrative has closed.

## 3. Commit point and the tail

There is no change to where state commits. `Turn.Outcome.persist/1` runs once, after the full reply parses and validates, and then `:turn_completed` is broadcast. The tail (`npc_memory_updates`, `context_summary`) is used there, as it is today.

**If the player acts before the commit** (usually because they tapped through the reveal), **queue it in the LiveView.** Show the action as the pending entry and hold it. Call `GameSessions.submit_message/3` on `:turn_completed`. If the turn fails, drop the action and leave it in the input. Why not submit at once: `submit_message` runs the intent step and `clear_clarification/1` against the session **before** the commit. That reads stale state and can race the store write. `World.Instance` would order the turns, but not that pre-job work. A hard lock would bring back the wait we are removing. Queueing keeps the feeling that the turn is back, without a second writer.

## 4. Mid-stream errors and retries

The rule: **never stream new prose over prose the player has read. Nothing commits on failure.**

| Case | Behaviour |
|---|---|
| The stream drops or times out **before the narrative closed** | Dim the partial text and show a one-line "*The GM rethinks…*" marker. Stream one fresh retry under it. If the retry fails, show `:turn_failed`. Nothing commits. |
| The stream drops, or the JSON is invalid, **after the narrative closed** | Keep the shown text. Retry **only the tail** once, as a non-streaming call. Pass the shown narrative and use a tail-only schema. If it passes, commit the shown narrative plus that tail. If it fails, show `:turn_failed`, mark the text "*the GM lost the thread; try again*", and commit nothing. |
| The narrative is blank (`:invalid_reply`) | No text was shown, so today's `:reset` and retry stay as they are. |

**Timeouts.** Add an idle timeout of about 15 s with no chunk, and an overall deadline of about 25 s. Today `receive_timeout` is 120 s. Both are constants.

**Oban.** After the GM call has started, a GM error must not re-run the turn. Return `{:cancel, reason}` for GM errors and keep the retries for crashes before the GM call. This closes the current hole, where a retry streams onto a page that has already reported "Turn failed".

## 5. Streamed text vs final state

The narrative is already on screen when validation or the engine might refuse something.

- **Prevent (the main path).** The engine decides **before** the GM call, as `Turn.Mechanics.apply/1` already does. The GM gets the outcome in the prompt (the trade outcome from #470), and it narrates that outcome. Every new engine result follows the same pattern.
- **Post-hoc conflict** (today only `Turn.Outcome` prose checks, which log a `turn.prose_mismatch` and do not re-run the GM). **The final state wins.** When a mismatch changes something the player would rely on (an item, money, a wound), code adds a short correction line under the GM entry, for example *"(The trade did not go through: Brenna keeps the lantern.)"*. The other mismatches stay log-only.
- **Rejected:** rewriting or retracting the shown narrative (it is jarring and erodes trust), and holding the text until the checks pass (that throws away the gain).

When the turn commits, its GM entry replaces `#gm-streaming` in place with the same text, so nothing jumps.

## 6. Config

| Value | Default | Read by |
|---|---|---|
| `GM_MIN_DELAY_MS` | `1500` | `TalesForge.Config.gm_min_delay_ms/0` (`env_int`) |
| `GM_REVEAL_MS_PER_CHAR` | `30` | `TalesForge.Config.gm_reveal_ms_per_char/0` |

The sentence-end pause (150 ms) is a constant in the hook. Slick's spec fixes it, and one pace knob is easier to tune. PlayLive reads both values at mount and hands them to the hook as `data-` attributes. **Prod** sets nothing in `fly.toml` and uses the defaults. **Playtest** sets them in `fly.playtest.toml` `[env]`, so Fredrik can try 1000, 1500 and 2000. A change needs a playtest deploy (or `fly secrets set`, which restarts the app). The page picks it up on the next load.

## 7. Typing dots (spec: Slick)

Slick's spec. The dots replace the "The GM is thinking…" text.

- **Placement.** The dots sit where the GM's next paragraph will begin: in the narrative column, left-aligned to the text edge, with the paragraph top margin. No bubble, label or avatar. The text replaces the dots in place, so nothing shifts.
- **Look.** Three round dots of 6px (0.375em) with 0.375em gaps, centred on the x-height, in `currentColor`. This works in both themes and needs no new tokens.
- **Motion.** A staggered fade and lift. Each dot goes from opacity 0.25 to 1 and rises 2px, in a 1.2 s ease-in-out loop, offset 0.15 s per dot. The dots fade in over 150 ms. When the text starts, they fade out over 120 ms as the first word fades in. If the pause would end in under 300 ms, the dots do not show at all. With the 1.5 s default this matters only when the delay is set low.
- **Reduced motion.** Static dots at opacity 0.55.
- **A11y.** The dots have `aria-hidden`. The container has one visually hidden `role="status"` with "The story continues…", set once.
- **Reveal.** 30 ms per character, plus 150 ms at sentence ends. A tap or scroll shows the rest (§2).

```css
.gm-typing{display:flex;gap:.375em;align-items:center;height:1lh;margin-top:var(--para-gap,1em);color:currentColor;animation:gm-in .15s ease-out}
.gm-typing span{width:.375em;height:.375em;border-radius:50%;background:currentColor;opacity:.25;animation:gm-dot 1.2s ease-in-out infinite}
.gm-typing span:nth-child(2){animation-delay:.15s}
.gm-typing span:nth-child(3){animation-delay:.3s}
@keyframes gm-dot{0%,60%,100%{opacity:.25;transform:none}30%{opacity:1;transform:translateY(-2px)}}
@keyframes gm-in{from{opacity:0}}
@media (prefers-reduced-motion:reduce){.gm-typing,.gm-typing span{animation:none}.gm-typing span{opacity:.55}}
```

```html
<div class="gm-typing" aria-hidden="true"><span></span><span></span><span></span></div>
```

## 8. Tests and proof

- **Unit.** Doctests for `partial_narrative/1` with `{:open | :closed, _}`, including an escaped quote just before the close and a chunk that splits there. The tail-only retry builds the right messages and schema.
- **Stubbed streaming LLM.** Extend the streaming test server (`:xai_api_base`, `test/ex_tales_forge/llm_stream_test.exs`) with scripted chunks: a normal stream, a drop before the close, a drop after the close, and invalid JSON in the tail. Assert the events, the retry kind, and that nothing commits on failure (no turn row, `world_state` unchanged).
- **LiveView** (`play_live_test.exs`). Send `{:turn_stream, …}` messages and assert `push_event` payloads with `assert_push_event`. The form stays locked until both `closed` and `render_hook(view, "gm_revealed")` have happened. A submit before `:turn_completed` is queued and goes out on `:turn_completed`. A failure drops the queued action. The "rethinks" marker appears. Each test fails without its change.
- **Look.** Screenshots at 390px and desktop, in both themes and with reduced motion, for Slick.
- **Latency on playtest.** 20 turns each at 1.0, 1.5 and 2.0 s. From `ai_calls` (`ttft_ms`, the new `narrative_ms`, `latency_ms`) and the page timings, report: submit to first text, submit to narrative close, submit to unlock, and submit to commit. Compare with the [latency doc](experiments/2026-10-llm-latency.md).

## 9. PR plan (most important first, each small)

1. **The LLM signals narrative close.** `{:closed, text}` from the stream, `narrative_ms` on `ai_calls` (add-only migration), and the idle timeout and overall deadline. No UI change. Proof: stub-server tests.
2. **Unlock at close, queue until commit.** In PlayLive, unlock on `closed` (no reveal yet) and queue the action until `:turn_completed`. Proof: LiveView tests. This is the latency win on its own.
3. **Reveal and minimum delay.** The `GmReveal` hook, the two config values, Slick's dots (CSS above), and the unlock that also waits for `gm_revealed`. Proof: LiveView tests and screenshots. Playtest first.
4. **Safe failures.** The "rethinks" marker, the tail-only retry, and `{:cancel, _}` for GM errors in `ProcessTurn`. Proof: stub-server drop tests.
5. **Correction line** for post-hoc mismatches that matter. Proof: a test with a forced trade mismatch.
6. **Measure on playtest** and add the numbers to the latency doc (docs only).

## 10. Open questions (options)

1. **Unlock:** (a) close and reveal finished or tapped (recommended); (b) close only, with the reveal still running.
2. **The player acts before the commit:** (a) queue in the LiveView (recommended); (b) hard lock until the commit; (c) submit at once and let `World.Instance` order the turns.
3. **The tail-only retry fails after the narrative was shown:** (a) commit nothing (as approved; the shown text gets "lost the thread"); (b) commit the narrative with an empty tail (the schema allows it; the NPC memory and summary are skipped for one turn).
4. **The pace at 30 ms per character makes a 1,000-character narrative take about 30 s:** (a) keep it and rely on the tap; (b) speed the reveal up after N seconds; (c) a shorter narrative target (latency doc, option 2).
5. **The Act button text "Thinking…" while the GM writes:** (a) keep it; (b) plain "Act" while disabled (the dots carry the state); (c) Slick decides.
6. **Text that streamed before a reload is lost until the commit:** (a) accept it (rare); (b) keep the narrative so far in `World.Instance` and replay it on mount.
