# Two-step Jev: act class first, then each listener's reading (offline experiment, 2026-10-19)

Status: offline experiment. No game code changed. Run by Bobby on 2026-10-19 between 06:20 and 06:40 CEST. Approved by Fredrik via Case.

## Summary

- **Act class (step 1).** The minimal call gets the act class right on 160 of 168 reads (95%). The only miss is "Brenna, how much did you give me for the cloak?", which it reads as trade instead of speak, at low confidence (0.33–0.40). The current single call on main got all 84 live reads right. The older stored rows (playtest build of 2026-10-18) missed 5 price questions; main fixes those with `ask_price`.
- **Confidence.** 142 of 168 reads are ≥ 0.9, and the median is 1.0. "Yes." lines get 1.0 even when they are ambiguous, so this confidence cannot tell us when to ask.
- **Brenna vs Hilde.** Their readings differ believably on *who the line is for*. A line naming Brenna is "nothing for me" to Hilde, and the reverse. They also differ a little on tone: Brenna is warm on 12 of 55 reads (she likes the speaker, 0.4), Hilde on 2. OCEAN and Maslow barely move the social act. There are also bad reads, such as Brenna hearing her own accepted quote as "curt".
- **Cost and latency per speech turn** (live, from the box):

  | Turn shape | Cost | Wall p50 / p90 |
  |---|---|---|
  | single call | $0.000141 | 76 / 113 ms |
  | 1+1 | $0.000091 | 148 / 185 ms |
  | 1+3 | $0.000209 | 159 / 216 ms |

  The listener calls run in parallel. The step-1 call cannot replace the single call, because the single call also extracts targets, items, skill and safety.
- **Recommendation.** Keep the single call as step 1 and add a `voice` question to it. Do not add a separate act-class call. When listener readings are wanted, fold them into the existing per-NPC `npc_reaction` Jev call (`TalesForge.Game.NpcReactions`), only for listeners who pass the hearing cut below. At today's place granularity that is usually just the addressee (N ≈ 1).

Total experiment spend: **$0.060** of Jev on the playtest key. 962 calls: 706 in the main runs (including a warm-up round) and 256 in the level-2 runs. No xAI LLM calls were made. Prod was not touched.

## Input

- **Sessions.** All 42 player lines from Gentry's three playtest sessions on 2026-10-18, as `QaRetest470/473/476` on the playtest DB:

  | Session | Retest | Turns | Time |
  |---|---|---|---|
  | `8a9dbde9-5971-47eb-b4a6-d0d852869014` | #470 | 11 | 18:07–18:10 CEST |
  | `253e26a5-e4ab-46cb-b472-7af6cdb3c25d` | #473 | 14 | 19:08–19:10 CEST |
  | `6d938a30-aaa6-46cf-8db8-f7e6f8c28f39` | #476 | 17 | 20:04–20:07 CEST |

  The session ids come from `/workspace/qa-470-trade-retest`, `qa-473-trade-retest` and `qa-476-offer-retest`, checked against `turns`. Other sessions on that day (for example `3d9788e0`, `643b8031`, and Fredrik's long `edeac566` / `3705591b` runs) were outside the brief.
- **The current single call.** Every turn has a stored `turn.intent` row with the Jev read (`ai_calls.meta`: action, confidence, top2, band). Those rows are from the playtest build of the day, before #478, so there is no `ask_price`. The single call was also re-run live on main (86cbefa) for the latency comparison.
- **Characters.** The `characters` rows of session 6d938a30 were used, with real values only:

  | Character | Race | OCEAN (O C E A N) | Maslow | Mood | Liking toward the player | Stats |
  |---|---|---|---|---|---|---|
  | Brenna Holt (innkeep) | human | 6 7 8 8 3 | belonging | cheerful | 0.1 (#470, #473), 0.4 (#476) | INT 10 |
  | Hilde Brask (smith) | human | 4 8 4 4 6 | safety | uneasy | 0.0 | INT 10 |
  | Caldern Voss (prospector), the third NPC for N = 3 | human | 6 5 6 6 5 | physiological | neutral | 0.0 | INT 9 |

  Their concerns are their stored concerns. "Facts she knows" are her backstory, her first three hooks and her public facts (pack data in `definition`).
- **Database access.** All reads were done in `BEGIN TRANSACTION READ ONLY … ROLLBACK` with `SET default_transaction_read_only = on`, through `flyctl postgres connect` on `tales-forge-playtest-db-wa`. `transaction_read_only` reported `on` each time. The queries are in [the scripts folder](2026-10-two-step-jev-scripts/).

## Method

- **Runs.** Two measured rounds and one warm-up round, all on jev-1.13.0 with the playtest TypeSafe key, from the box. For each line, three arms ran back to back, and the order rotated per line and per round (A B C, B C A, C A B):
  - **single:** the current main `JevIntent` request. The context is the Valley Inn eval world (item r084) with Brenna's stock, the line, the previous narration as `last_narration`, and the ale offer when the previous line was a price question. This is the same method as the #478 and #480 measurements.
  - **1+1:** the step-1 call, then Brenna's listener call if step 1 says speech.
  - **1+3:** the step-1 call, then Brenna, Hilde and Caldern in parallel if step 1 says speech.
- **What counts as speech.** Step-1 class `speak` or `trade`, and voice not `none`. This gate is pure code.
- **Ground truth.** I labelled every line by hand, using the class definitions in the prompt. Five lines have two acceptable answers:
  - "Yes." ×4 and "No, thank you.": speak or trade (each could be an answer to a quote or to a question);
  - "I stretch and yawn.": other or physical.
- **Mapping the single call's action to a class.**
  - speak → speak;
  - observe, freeform, wait, rest, train, other → other;
  - buy, sell, trade, spend, ask_price → trade;
  - everything else → physical.

## Prompts

Jev only answers typed questions. It returns a label plus probabilities, never free text. So "meaning" is a closed set of labels, not a sentence. Each prompt is a JSON *state* plus typed *questions*.

### Step 1: act class and voice

State:

```json
{"task": "A player in a fantasy role-playing game wrote one line for their character. Classify it.",
 "what_just_happened": "<last 500 characters of the previous narration>",
 "player_line": "<the line>"}
```

Questions:

- `act_class` asks "What kind of act is the player's line?":
  - `speak`: Talks: says something, asks a question, answers yes or no, greets, jokes or threatens with words. No goods or coins change hands by this line itself.
  - `physical`: Does a physical action in the world: moves somewhere, attacks, picks a lock, takes, gives, uses or handles something, works.
  - `trade`: Buys, sells, orders, pays, asks a price, or accepts or refuses a price that was just offered.
  - `other`: Anything else: looks around, waits, rests, thinks, or a gesture with no effect.
- `voice` asks "How loudly does the player's character speak in this line?":
  - `whisper`: Whispers or speaks under the breath, meant for one person close by.
  - `talk`: Ordinary speaking voice.
  - `shout`: Shouts, calls out across a room or street, or raises the voice.
  - `none`: Says nothing aloud (a silent action).

### Step 2: one listener's reading

State:

```json
{"task": "Read the speaker's words as Brenna Holt hears them, from her point of view. The speaker is a traveller in her place of work.",
 "listener": {"name": "Brenna Holt", "role": "innkeep", "race": "human",
   "personality_ocean_1_to_10": {"openness": 6, "conscientiousness": 7, "extraversion": 8, "agreeableness": 8, "neuroticism": 3},
   "maslow_level": "belonging: safe and fed; cares about friends, guests and community",
   "mood": "cheerful",
   "concerns": ["Keep the common room full, warm and talking, and her regulars safe while the hills are restless"],
   "liking_toward_speaker": "0.4 (likes the speaker)",
   "facts_she_knows": ["<backstory>", "<hook 1>", "<hook 2>", "<hook 3>", "<public facts>"],
   "open_offer": "She just answered the speaker: <first 350 characters of her quote> | none"},
 "what_just_happened": "<last 500 characters of the previous narration>",
 "speaker_says": "<the line>"}
```

The Maslow levels are described in words:

- physiological: basic needs unmet (hungry, cold, short of sleep or wages)
- safety: does not feel safe; worried about threats or ruin
- belonging: safe and fed; cares about friends, guests and community
- esteem: secure; cares about respect, status and recognition
- self_actualisation: secure and respected; cares about craft and meaning

Liking is put into words too:

- ≥ 0.5: likes the speaker a lot
- ≥ 0.2: likes the speaker
- above −0.2: neutral
- above −0.5: dislikes the speaker
- otherwise: dislikes the speaker strongly

Questions:

- `social_act` asks "As this listener hears it, what social act is the speaker making toward her?":
  - `request`: asks her for goods, a service, a favour or help
  - `offer`: offers her goods, coin, help or work
  - `accept`: agrees to something she offered
  - `decline`: turns down something she offered
  - `insult`, `compliment`, `threat`, `apology`, `joke`
  - `question`: asks her for information: a price, news, directions or advice
  - `unclear`: she cannot tell
- `meaning` asks "What does she take the speaker to want from her?": `wants_goods`, `wants_price`, `accepts_offer`, `refuses_offer`, `wants_info`, `wants_work`, `wants_to_sell`, `company`, `provoke`, `nothing` (not addressed to her, or just an action), `unclear`.
- `tone` asks "How does the line come across to her, given who she is and how she feels about the speaker?": `warm`, `neutral`, `curt`, `rude`, `threatening`.

Confidence is Jev's confidence on `social_act`. The full criteria text is in `exp.exs`.

## Step 1 results

### Accuracy

| Read | Correct | Notes |
|---|---|---|
| Stored single call (playtest build of 2026-10-18) | 37 / 42 (88%) | 5 price questions read as speak |
| Current single call on main, live | 84 / 84 (100%) | price questions are `ask_price` |
| Step 1, minimal prompt, live | 160 / 168 (95%) | 8 misses, all on the cloak question |

### Confidence on `act_class` (168 reads)

| Range | 0.3–0.4 | 0.4–0.5 | 0.5–0.6 | 0.6–0.7 | 0.7–0.8 | 0.8–0.9 | 0.9–1.0 |
|---|---|---|---|---|---|---|---|
| Reads | 6 | 5 | 2 | 7 | 0 | 6 | 142 |

Quantiles: minimum 0.33, p10 0.61, p25 0.93, median 1.00. The reads below 0.7:

- the cloak question (0.33–0.40, wrong);
- "I'd like a meal." (0.49–0.51, trade, right);
- "No, thank you." (0.61, speak, acceptable);
- "I stretch and yawn." (0.57–0.61, other, right).

Every "Yes." scored 0.95–1.00, so the act-class confidence does not flag the ambiguous yeses. The offer question in #480 does that job.

**Voice:** 109 `talk` and 59 `none`. There were no `whisper` or `shout` reads, because no line in these sessions whispers or shouts. One problem: narrated trades with implied speech, such as "I buy a loaf of bread and pay her.", came out as `none`, so the speech gate skipped the listener call. Brenna would still react to a sale, so the gate should be "talk or trade", not "voice ≠ none".

### Disagreements with the single call, and who is right

| Line | Stored single | Main single (live) | Step 1 | Right |
|---|---|---|---|---|
| "How much for an ale?" (6d938a30 T1, T3, T11), "How much for the bread and cheese?" (T7), "How much for three hundred mugs of ale?" (T15) | speak | ask_price → trade | trade 0.88–0.97 | **step 1** and main. The stored build had no `ask_price`. |
| "Brenna, how much did you give me for the cloak?" (8a9dbde9 T6, 253e26a5 T6) | speak | speak | trade 0.33–0.40 | **single call**. It asks about a past sale; nothing changes hands. |
| "Yes." after the 300-mugs quote (6d938a30 T16) | buy → trade | speak | speak 1.00 | Both acceptable. It is an accept of the quote, so trade is the closer reading, and step 1's 1.00 is overconfident. |

The full per-line data is in [per-line.csv](2026-10-two-step-jev-scripts/per-line.csv).

## Step 2 results: Brenna vs Hilde (and Caldern)

The same 27 speech lines (as gated by step 1) went to all three listeners, in two rounds. Each listener was treated as the person spoken to. That is counterfactual for Hilde and Caldern, who were not in the inn; I did it so that the listener data is the only thing that changes.

- **Stability across the two rounds** (same social act and meaning): Brenna 26/27, Hilde 27/27, Caldern 21/27.
- **Brenna vs Hilde:** same act and meaning on 15 lines, different on 13.
- **Tone, over all reads:**

  | Listener | warm | curt | neutral |
  |---|---|---|---|
  | Brenna | 12 | 7 | 36 |
  | Hilde | 2 | 3 | 50 |
  | Caldern | 2 | 3 | 50 |

### Believable differences (good)

| Line | Brenna | Hilde | Why it is believable |
|---|---|---|---|
| "I sell my travel cloak to Brenna Holt." | offer / wants_to_sell 0.91–0.94 | unclear / nothing 0.64–0.68 | Not addressed to Hilde. |
| "I sell my hunting knife to Hilde Brask." | unclear / nothing 0.43–0.57 | offer / wants_to_sell 0.93–0.94 | The mirror case. |
| "I order a meal." | request / wants_goods 1.00 | request / nothing 0.52–0.60 | Hilde serves no meals. |
| "Brenna, how much did you give me for the cloak?" | question / wants_price 0.94–0.98 | question / wants_price 0.44–0.89 | Brenna knows she is asked. Hilde is unsure. |
| "I'd like a meal.", "The bowl of stew, please.", "How much for an ale?" (#476) | warm | neutral | Brenna likes the speaker (0.4) and is cheerful. Hilde is neutral and uneasy. |

### Unbelievable readings (bad)

- **"Yes." to Brenna's own ale quote** (6d938a30 T2, T16): Brenna hears it as **curt**. A cheerful host who likes the speaker should not.
- **"Yes." after the loaf and Osric lead** (T10): Hilde and Caldern read **offer**, though nobody offered them anything. On "I buy an ale." Hilde reads **accept** when she has no ale offer.
- **"Yes." in the square, to Osric's job** (T13): all three read **offer / wants_work**. None of them is Osric, and none was in the square. The hearing cut below would remove these calls entirely.
- **Personality has little effect.** Hilde's safety level, unease and A4 never made her suspicious or rude. Caldern's hunger (physiological) never showed. The differences come mostly from names and roles in the line, and from liking. The data has no insults, threats, jokes or haggling, so the extremes are untested.

**Verdict:** believable on *addressee* and *warmth*, not yet on *personality*. Before building this, the listener state should say explicitly whether she is the addressee, and add a bystander case.

## Cost and latency

Measured live from the box, two rounds, arms alternating per line. Jev bills input tokens only, at $0.042 per million. It also reports output tokens, which are not billed.

### Per call

| Call | Calls | Input tokens | Output tokens (reported) | Cost per call | p50 | p90 |
|---|---|---|---|---|---|---|
| Single (main) | 84 | 3,356 | 1,023 | $0.000141 | 76 ms | 113 ms |
| Step 1 (act class + voice) | 168 | 723 | 92 | $0.000030 | 64 ms | 104 ms |
| Listener reading | 219 | 1,421 | 265 | $0.000060 | 70 ms | 114 ms |

From the playtest app (Fly, arn region), the stored single calls of these sessions had p50 239 ms and p90 264 ms at about 3,447 tokens. The box is closer to TypeSafe, so add about 160 ms per sequential call in production.

### Per turn

Listeners run in parallel. Only speech turns get listener calls; 64% of these turns were speech.

| Turn shape | Cost, speech turn | Cost, average turn | Wall p50 / p90, speech turn |
|---|---|---|---|
| Single call (today) | $0.000141 | $0.000141 | 76 / 113 ms |
| 1+1 (step 1 + Brenna), measured | $0.000091 | $0.000069 | 148 / 185 ms |
| 1+3 (step 1 + Brenna, Hilde, Caldern), measured | $0.000209 | $0.000147 | 159 / 216 ms |
| **Realistic: single + voice + N listeners, busy tavern, today's granularity** (N = 1 clear; partial bystanders get no call) | $0.000205 (est.) | $0.000183 (est.) | ≈ 150 / 200 ms sequential; ≈ 80 / 120 ms if the addressee call runs alongside the single call |
| Same, if each partial bystander gets a garbled-reading call (inn with Cobb and Rusk present: N = 3) | $0.000325 (est.) | $0.000260 (est.) | ≈ 160 / 215 ms |
| Realistic, market by day (N = 1: only the addressee hears ordinary talk) | $0.000205 (est.) | $0.000183 (est.) | ≈ 150 / 200 ms |
| **Level 2 theory of mind, busy tavern** (earned on 19% of turns, as a field in the listener call) | +$0.000008 per level-2 listener | +$0.0000015 | +4 ms (within noise) |
| Level 2 as a second call (for comparison) | +$0.000044 per level-2 listener | +$0.0000084 | +84 ms p50 on those turns |

The step-1 call cannot replace the single call. The single call is the one that extracts targets, items, skill and safety. So the honest comparison is **single + N listeners**, not 1 + N. The `voice` question added to the single call is estimated at about 100 tokens ($0.000004). For comparison, the existing `npc_reaction` calls in these sessions (prototype, flag on) cost 942 tokens and $0.000040 each, p50 217 ms, about 1.7 calls per turn.

## Design: who hears it (hearing cut, pure code)

Who hears a line is decided in pure code, using physics:

```
level_at_listener = voice_level − 20·log10(distance_m) − walls_dB
snr               = level_at_listener − ambient_dB + hearing_dB
clarity           = clear    if snr ≥ +3
                    partial  if −6 ≤ snr < +3
                    nothing  if snr < −6
```

What each clarity means:

- **Clear:** she gets her own listener reading.
- **Partial:** she gets fragments. The proposal is pure code: a few words kept and the rest replaced with "…", stored as an "Overheard (fragments): …" memory. No Jev call at first. A garbled reading call is the costed alternative above.
- **Nothing:** no call and no memory.

The addressee at conversation distance always counts as clear, whatever the voice. The speaker leans in to whisper and raises her voice in a noisy room. The physics is for bystanders.

### Proposed numbers

**Voice at 1 m** (from step 1's `voice`):

- whisper 35 dB;
- talk 60 dB;
- shout 80 dB.

People raise their voices in noise (the Lombard effect), so talk = min(max(60, ambient + 8), 75) and shout = min(max(80, ambient + 15), 90).

**Ambient noise:**

| Setting | dB |
|---|---|
| quiet night | 30 |
| quiet inn by day | 45 |
| market at dusk | 50 |
| market by day | 62 |
| busy tavern, evening | 65 |
| working forge | 85 |

**Wall loss:**

| Path | dB |
|---|---|
| open doorway | 6 |
| interior timber wall or closed door | 20 |
| exterior wall | 30 |
| different building | exterior wall + distance |

**Hearing:**

- human and dwarf: 0;
- half-elf: +3;
- elf: +6 (rules "Keen Senses", +10 to perception skills);
- Perception skill: + skill/20 (0 to +5);
- an impaired or sleeping listener: −10.

**Distance, while there are no positions inside a place:**

- addressee: 1 m;
- bystander in the same building-scale place: 4 m (two cells of 2 m);
- bystander in a settlement-scale place such as the square: 10 m;
- another place: the `at` distance × the parent's `cell_m`, plus walls.

### What this gives

| Case | Level at listener | SNR | Result |
|---|---|---|---|
| Busy tavern (65), talk (73 at 1 m), bystander at 2 m | 67 | +2 | partial |
| same, at 4 m | 61 | −4 | partial |
| same, at 6 m | 57 | −8 | nothing |
| Busy tavern, shout (80), at 4 m | 68 | +3 | clear |
| Busy tavern, shout (80), at 6 m | 64 | −1 | partial |
| Busy tavern, whisper, at 1 m | below the noise | | nothing (only the addressee hears) |
| Quiet night (30), whisper, at 2 m | 29 | −1 | partial |
| Market by day (62), talk (70), at 10 m | 50 | −12 | nothing |
| Market by day (62), shout (80), at 10 m | 60 | −2 | partial |
| Smithy, forge working (85), shout (capped at 90), bystander at 4 m | 78 | −7 | nothing: only the addressee at the anvil hears anything |
| Inn to yard through an open door, shout (80), 20 m (one settlement cell) | 48 | vs yard 45: +3 | clear; talk does not carry |

### Listener counts at today's granularity

At the end of each session, the read-only `characters.location_id` query showed:

| Session | Valley Inn | Market Square |
|---|---|---|
| 8a9dbde9 | Brenna, Cobb, Rusk | Osric |
| 253e26a5 | Brenna | Osric |
| 6d938a30 | Brenna | Osric |

The inn crowd in the narration (miners, drovers) is prose, not characters.

- **Busy tavern:** 1 clear (the addressee). Every same-place bystander is at the default 4 m, so they are partial: 0 in two sessions, 2 (Cobb, Rusk) in one. So N = 1 with "partial = pure code", or N = 1–3 with garbled-reading calls.
- **Market:** N = 1 (the addressee, if any). Ordinary talk does not reach the default 10 m.
- **Compared with the measured runs:** N = 3 overstates today's world by about 3×. N = 1 matches it.

### Data that exists, and what is missing

| Need | Exists | Where | Missing |
|---|---|---|---|
| Place positions | `at: [x, y]` in the parent's grid, plus `parent` and `scale` | location front matter, e.g. `priv/adventures/tin_valley/world/valley_inn.md`; `TalesForge.Game.Pack.validate_positions!/1` | — |
| Distances between places | grid distance × `cell_m` (building 2 m, settlement 20 m, region 200 m) | `TalesForge.Game.Travel` (`cell_m/2`, private `distance/2`) | a public helper |
| Character positions inside a place | no; only `characters.location_id` and `world_state["present_npcs"]` | `lib/ex_tales_forge/schemas/character.ex` | sub-place or cell positions (bar, hearth table, door) |
| Walls and doors | no; `exits` lists neighbours only | location front matter | the wall or door type per exit, and door state |
| Ambient noise | no; `world_clock` (time of day) and `situation_lines` exist and could feed a derivation | `world_state` | a per-place base level plus a time-of-day curve |
| Race | yes (`definition.race`; everyone in Tin Valley is human); race rules exist | `characters.definition`; `priv/adventures/tin_valley/rules/races.md`; `priv/characters/creation.json` | a hearing modifier per race |
| Hearing skill | Perception is in the rules (Social domain). No pack NPC has it, and the Jev intent skill list leaves it out. WIS exists. | `priv/adventures/tin_valley/rules/skills.md`; `TalesForge.Schemas.Character.Stats` | Perception values on NPCs |
| Who hears today | every present NPC except the addressee "overhears" every non-quiet turn | `TalesForge.NPCSignals.overheard/3` (`Actions.NPC.OnOverheard`) | the hearing cut itself |

## Later stage, not the first build: theory of mind (how deeply she thinks about the speaker)

- **Level 1 (default):** what she thinks the speaker meant. That is the listener reading above.
- **Level 2:** what she thinks the speaker expects from her reaction. This covers bluffing, lying, haggling, flirting and testing her. Depth is capped at 2 for now.

### What exists for the depth limit

- OCEAN `openness` (`characters.ocean`).
- An intelligence stat: `INT` in `TalesForge.Schemas.Character.Stats` (fields str, dex, con, int, wis, cha) and in the pack `stats`. Values in Tin Valley run 9 to 11.
- `insight` ("motives and lies") is a skill on Brenna and Osric, and could later add a bonus.

### Pure-code depth rule (proposal)

```
max_depth(npc) = 2 if openness >= 6 and INT >= 10, else 1
earned?(npc, turn) =
     open deal with her as a party       (world "open_offer" giver or taker)
  or |liking toward speaker| >= 0.5      (strong liking or distrust)
  or an open concern of priority >= 7    (high stakes)
depth = if clarity == :clear and earned?, do: max_depth, else: 1
```

Applied to the pack:

| Character | Openness | INT | Max depth |
|---|---|---|---|
| Brenna | 6 | 10 | 2 |
| Old Maude | 7 | 11 | 2 |
| Hilde | 4 | 10 | 1 |
| Caldern | 6 | 9 | 1 |
| Osric | 4 | 10 | 1 |

In these sessions, liking stayed ≤ 0.4 and concern priority ≤ 6. So level 2 is earned only for Brenna, on open-deal lines: 8 of 42 lines (19%).

### Measured cost (Brenna, 32 lines × 2 rounds)

The level-2 question was `speaker_stance`: sincere, bluffing, lying, haggling, flirting, testing, unclear.

| Variant | Input tokens | Cost per listener | p50 / p90 |
|---|---|---|---|
| Level 1 only | 1,437 | $0.000060 | 72 / 140 ms |
| Level 2 as a field in the same call | 1,629 (+192) | $0.000068 (+$0.000008) | 76 / 124 ms (no real change) |
| Level 2 as a second call (with the level-1 reading in its state) | 2,466 (+1,029) | $0.000104 (+$0.000044) | 156 / 208 ms (+84 ms, sequential) |

Both variants gave the same picture: sincere 59/64 (field) and 60/64 (second call). "Yes." to the 300-mugs quote came out as **testing** (0.45). That is a sensible level-2 read: the speaker is testing her prices.

For the busy tavern there is about 1 clear listener and 19% earned turns. That adds +0.19 level-2 reads per turn: +36 tokens and +$0.0000015 per turn as a field. As a second call it would add +$0.0000084 per turn and +84 ms on those turns.

**Recommendation:** make level 2 a field in the same listener call, asked only when the depth rule says 2. It costs a fifth as much as a second call and adds no wait. A second call only pays off if level 2 must see a *corrected* level-1 reading, which our data gave no sign of. These lines have no bluffing, lying or flirting, so the level-2 labels need a test set with those before they are trusted.

## Caveats

- **Small, scripted data.** 42 lines, many repeated across the three retests (the #470 and #473 scripts are almost the same). No insults, threats, jokes, whispers or shouts. Treat the step-2 labels as a smoke test, not an accuracy figure.
- **Counterfactual listeners.** Hilde and Caldern were placed as the addressee in the inn so that only listener data changed. In play, the hearing cut would have removed most of their calls.
- **The single-call context is an approximation.** It is the Valley Inn eval world with Brenna's stock, not each turn's exact world state (for example, the smithy turns use the inn world). Act-class accuracy does not depend on it much. Targets would.
- **Latency is from the box.** The playtest app sees about +160 ms per call (stored p50 239 ms). Parallel listener calls hide most of N, but not the first sequential call.
- **The ground truth is mine.** It was labelled by hand by one person.
- **The hearing numbers are proposals.** They use real-world rough values (speech about 60 dB at 1 m, a busy pub 65–75 dB). Tune them in playtests.

## Files

- [Scripts and data](2026-10-two-step-jev-scripts/):
  - `exp.exs`: the three arms, alternating; run with `mix run --no-start` from a main worktree, with the playtest key in `TYPESAFE_INTENT_PLAYTEST_API_KEY`;
  - `exp_l2.exs`: level 2, field vs second call;
  - `q1.sql`, `q2.sql`, `q3.sql`: read-only queries;
  - `analyze*.py`: the tables in this note;
  - `per-line.csv`: every line with the stored, live, step-1 and listener reads.
- The input file `lines.json` is built from the `q2.sql` dump. It is not committed, because it holds full GM narrations.
