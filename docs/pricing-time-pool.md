# Pricing decision draft: a pool of play time

Status: draft for discussion (2026-10-07). Numbers are rough and based on a tiny playtest sample.

## 1. Proposal

1. Players buy a pool of play time. No monthly subscription. Modules are paid separately (author revenue share later).
2. Only game processing time is deducted: the time from the player sending input until the GM response text comes back. Reading, thinking and idle time are free, so you can leave to do the dishes and the game waits at no cost.
3. Persona/bot think time from playtests is never part of player cost (same split as in playtest accounting).
4. The first character is free. Later characters cost time, since portrait generation and creation steps are LLM calls.
5. The app always shows "about N hours left" (or the equivalent unit) so nobody is surprised by an empty pool.
6. Target use: about 20 minutes of play on a commute.

The north star stays the first paying customer the founders don't know.

## 2. Rough cost estimate

Data: `ai_calls` on the Fly app `tales-forge-playtest`, refreshed 2026-10-07. All calls succeeded.

| Purpose | Calls | Sessions | Cost (USD) | Latency (s) |
|---|---|---|---|---|
| gm | 36 | 8 | 0.384 | 204.3 |
| scene | 8 | 8 | 0.049 | 22.6 |
| persona (excluded) | 45 | 7 | 0.069 | 82.4 |
| scorer (excluded) | 6 | 6 | 0.005 | 5.5 |

Sample size: 36 GM turns over 8 short sessions (mostly 5-turn Tin Valley smoke runs). This is far too small to set a price on.

Assumptions:

1. Player cost = `gm` + `scene` calls. Persona and scorer are playtest-only.
2. Billed time = GM latency only. Scene setup (about one call per session) is treated as overhead, not billed time.
3. Exchange rate fixed at 1 USD ≈ 10.5 SEK for this draft.
4. A commute turn takes 45–90 s of wall clock, so 20 minutes ≈ 13–27 turns.

Derived figures:

1. GM cost per turn: about $0.011 (≈ 0.11 SEK). GM time per turn: about 5.7 s.
2. Scene cost per session: about $0.006.
3. Game cost per billed GM-second, scene included: about $0.0021, so about $0.13 (≈ 1.3 SEK) per billed minute, or about $7.6 (≈ 80 SEK) per billed hour.
4. One 20-minute commute: 13–27 turns ≈ 1.2–2.6 billed minutes, costing about $0.15–0.30 (≈ 1.5–3.1 SEK). If longer context makes turns up to 50% more expensive, the top end is about $0.45 (≈ 4.7 SEK).

Implication for presentation: billed time is only about 6–13% of wall-clock play. A 20-minute commute uses only a few billed minutes, so "1 hour" of billed time is roughly 8–15 hours of real play. Selling "hours" of billed time would feel stingy and confusing ("I played all week and used 40 minutes?"). Options:

1. Sell "commute sessions" or "play hours" in wall-clock terms, each mapped internally to a fixed number of billed GM-seconds (for example 1 play hour ≈ 6 billed minutes).
2. Sell credits and show "about N commutes left".
3. Show raw billed time ("GM time"), which is accurate but needs explaining.

## 3. Character creation

1. The first character is free; cost is absorbed as acquisition cost.
2. Later characters: not measured yet (character creation is not ported). Expect a few text calls plus a portrait image, so roughly $0.03–0.10 per character until measured. Charge it as a fixed amount of time rather than measured latency, since image generation time is not GM time.

## 4. Risks and unknowns

1. Tiny sample: 36 turns, almost all from one module and one persona.
2. Longer sessions grow the context, so cost per turn rises over a session; billing per GM-second only partly tracks this (latency grows slower than token cost).
3. Model price changes (up or down) move the margin directly; price per billed second must be revisable.
4. Portraits and other images have different cost and latency profiles than text.
5. Failures and retries: errors and timeouts should probably not be billed, but retries still cost us.
6. Abuse (Ronny): very long inputs, prompt stuffing or scripted play to maximise output per billed second; may need caps on input length or output tokens per turn.
7. Latency depends on xAI load, so the same turn can bill differently on different days.

## 5. Open questions (most important first)

1. Price per pool and target margin: what does a pool cost in SEK, and what multiple of LLM cost do we need (payment fees, hosting, author share)?
2. What exactly counts as billed time: GM text only, or also scene, intent and image calls? Wall-clock latency or a token-based "time equivalent" that is stable across xAI load?
3. Do we bill failed calls and retries? Proposal: never bill errors; bill one successful response per input.
4. How is remaining time shown: billed minutes, play hours, or commutes left?
5. Price of extra characters: fixed time cost or measured?
6. Does a free starter pool come with the free character, and how big?
7. Abuse limits: input length caps, per-turn output caps, rate limits.
