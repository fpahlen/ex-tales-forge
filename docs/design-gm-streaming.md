---
title: "Design: GM thinking delay and smoothed streamed narration"
updated: 2026-10-18
status: design for review (no code)
---

# Design: GM thinking delay and smoothed streamed narration

**Status:** design, 2026-10-18, revised after Case's review of #471. No code yet.

**Decided (Fredrik, Case):**
- The GM narration keeps streaming. Before the first text there is a minimum "GM thinking" delay of **1.5 s**, shown as Slick's typing dots.
- After the delay, the text is revealed at the speed the tokens arrive, smoothed with a small floor so bursts do not jerk. There is **no reading-pace reveal**: 30 ms per character made a 30 s wall, and the complaint was only the instant start. Players read at their own pace, as in any chat.
- Input unlocks at the **commit** (about 5 s), as today. The tail (about 1.3 s) is acceptable for now. There is no unlock when the narrative closes, and no holding of actions before the commit.
- State commits **once**, after the full reply, in `Turn.Outcome.persist/1`. Engine results come from code, and the GM narrates only actual outcomes (#470).

**Numbers (prod `:lean`, [LLM latency](experiments/2026-10-llm-latency.md), #467/#468):** the first token comes at 551-724 ms. The narrative closes at about 3.6 s. The call ends at 4.9-5.4 s. A token takes about 12.3 ms, which is about 3 ms per character.

## 1. Current state

Streaming is **on for every GM turn, on prod and playtest, with no flag** (#191 and #197, merged 2026-10-12).

- `TalesForge.LLM.complete_turn/5` always streams (`gm_opts/3`). `stream_openai_compatible/3` reads the SSE chunks. `TalesForge.LLM.Stream.partial_narrative/1` reads the `narrative` string from the partial JSON. `narrative` is the first key in `narration_schema/1` (`Jason.OrderedObject`, strict `json_schema`). `maybe_emit/2` sends `{:text, so_far}` at most every 75 ms (`:llm_stream_throttle_ms`).
- `Turn.Gm.narrate/1` → `Turn.Adapters.broadcast/2` sends `{:turn_stream, _}` on the session PubSub topic. `PlayLive` assigns `:streaming_text`. `PlayComponents` renders `#gm-streaming`, and "The GM is thinking…" until the text starts. The text therefore starts as soon as the first token arrives, with no delay, and it arrives in 75 ms jumps.
- Input stays locked until `{:turn_completed, _}`, which is sent after the commit.
- **Bug, fixed separately (#472):** `Workers.ProcessTurn` had `max_attempts: 3`. A GM error showed "Turn failed" and then the whole turn ran again, which streamed new text onto that page and committed a turn.

## 2. Design

**Transport (unchanged).** PubSub `{:turn_stream, {:text, so_far}}` goes to `PlayLive.handle_info/2`, which sends `push_event("gm_text", %{text: so_far})`. Each event carries the whole text so far, so a lost or doubled event does no harm. The narrative-close signal is not needed.

**Reveal (client).** A colocated hook (`GmReveal`) owns a `phx-update="ignore"` container. Each frame it shows the next characters of the received text, at no more than one character per `GM_REVEAL_MIN_MS_PER_CHAR` (default 8 ms). When the backlog grows beyond that rate, it reveals faster so that the backlog clears in about 250 ms. Why the catch-up: the stream delivers about 3 ms per character. A hard floor of 8 ms would make a 1,000-character narrative take about 8 s, ending well after the commit. With the catch-up, the reveal lags arrival by a quarter of a second at most. Why on the client: smoothing done from the server would mean many diffs per second per player, plus socket jitter.

**Delay and dots.** The dots show when the submit is taken (the pending action from #197). The text starts at `max(GM_MIN_DELAY_MS, first text)`. The hook times this from the moment it mounts. The text that arrived during the delay (a few hundred characters) then catches up quickly, as above.

**Commit.** `:turn_completed` replaces `#gm-streaming` in place with the committed GM entry, which has the same text, and shows any part not yet revealed at once. Input unlocks then, as today.

## 3. Mid-stream failures: never overwrite text the player has read

Nothing commits on failure.

| Case | Behaviour |
|---|---|
| The stream drops or times out before the narrative closed | Dim the partial text and add a "*The GM rethinks…*" line. Make one fresh streamed retry under it. If that fails too, show "Turn failed". |
| The stream drops, or the JSON is invalid, after the narrative closed | Keep the text. Retry only the tail, once, as a non-streaming call that gets the shown narrative. If that fails, show "Turn failed" and mark the text "*the GM lost the thread; try again*". |
| A blank narrative (`:invalid_reply`) | No text was shown, so today's `:reset` and retry stay. |

Add an idle timeout of about 15 s without a chunk (today `receive_timeout` is 120 s). It is a constant.

## 4. Streamed text vs final state: the final state wins

- **Prevent.** The engine decides **before** the GM call (`Turn.Mechanics.apply/1`). The GM gets the outcome in the prompt, as with the trade outcome in #470. New engine results follow the same pattern.
- **Post-hoc conflict** (the `Turn.Outcome` prose checks log `turn.prose_mismatch`). **The final state wins.** When a mismatch changes something the player relies on (an item, money, a wound), code adds one short correction line under the GM entry, for example *"(The trade did not go through: Brenna keeps the lantern.)"*. We never rewrite the shown text.

## 5. Config

| Env | Default | Read by |
|---|---|---|
| `GM_MIN_DELAY_MS` | `1500` | `TalesForge.Config.gm_min_delay_ms/0` (`env_int`) |
| `GM_REVEAL_MIN_MS_PER_CHAR` | `8` | `TalesForge.Config.gm_reveal_min_ms_per_char/0` |

PlayLive reads both values at mount and hands them to the hook as `data-` attributes. Prod uses the defaults (nothing set in `fly.toml`). Playtest sets them in `fly.playtest.toml` `[env]`, so Fredrik can try 1000, 1500 and 2000. A change needs a deploy or restart, and the page picks it up on the next load.

## 6. Typing dots (spec: Slick)

- **Placement.** The dots sit where the GM's next paragraph will begin: in the narrative column, left-aligned to the text edge, with the paragraph top margin. No bubble, label or avatar. The text replaces the dots in place, so nothing shifts.
- **Look.** Three round dots of 6px (0.375em) with 0.375em gaps, centred on the x-height, in `currentColor`. This works in both themes and needs no new tokens.
- **Motion.** A staggered fade and lift. Each dot goes from opacity 0.25 to 1 and rises 2px, in a 1.2 s ease-in-out loop, offset 0.15 s per dot. The dots fade in over 150 ms. When the text starts, they fade out over 120 ms as the first word fades in. If the pause would end in under 300 ms, the dots do not show at all.
- **Reduced motion.** Static dots at opacity 0.55.
- **A11y.** The dots have `aria-hidden`. The container has one visually hidden `role="status"` with "The story continues…", set once.
- The dots replace "The GM is thinking…".

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

## 7. Tests and proof

- **LiveView** (`play_live_test.exs`). The dots show after a submit. `{:turn_stream, _}` gives `assert_push_event(view, "gm_text", _)` with the config values on the container. Input stays locked until `:turn_completed`, which replaces the streamed entry. Each test fails without its change.
- **Stubbed LLM.** `stub_llm/1` (`{:transport_error, _}` from #472) and the SSE test server (`llm_stream_test.exs`): a drop before and after the narrative closes, invalid JSON in the tail, and no commit on failure.
- **Look.** Screenshots at 390px and desktop, in both themes and with reduced motion, for Slick.
- **Playtest.** 20 turns each at 1.0, 1.5 and 2.0 s. Measure submit to first text, submit to the last character revealed, and submit to the commit (`ai_calls.ttft_ms` and `latency_ms`, plus page timings).

## 8. PR plan

1. **The Oban re-run bug:** [#472](https://github.com/whyse-ab/ex-tales-forge/pull/472) (one attempt per turn job, with a regression test).
2. **Delay, dots and smoothing:** the `GmReveal` hook, Slick's CSS, and `GM_MIN_DELAY_MS` and `GM_REVEAL_MIN_MS_PER_CHAR`. Proof: LiveView tests, screenshots, the playtest timings. Playtest first.
3. **Only if still needed:** the mid-stream failure handling (§3) and the correction line (§4).

## 9. Open questions (options)

1. **The tail-only retry fails after the narrative was shown:** (a) commit nothing (the default); (b) commit the narrative with an empty tail (the schema allows it).
2. **The Act button text while the GM writes:** (a) keep "Thinking…"; (b) "Act" while disabled, with the dots carrying the state; (c) Slick decides.
