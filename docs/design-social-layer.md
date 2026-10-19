---
title: "Design: social layer (listener readings, liking, obligations, two-speed)"
updated: 2026-10-19
status: design (rev. 2 after Case's review; no code yet)
---

# Design: social layer

**Status:** design note, 2026-10-19, rev. 2 after Case's review. Docs only, no
code. Scope set by Fredrik (via Case). Code:
[whyse-ab/ex-tales-forge](https://github.com/whyse-ab/ex-tales-forge), main
`d41554c`. Inputs:

[`analysis-social-levers.md`](analysis-social-levers.md) (#479: the 14 labels,
G1/G2/G4); #481 `experiments/2026-10-two-step-jev.md` (open: `voice`, listener
readings in `npc_reaction`, hearing cut, theory of mind);
[`experiments/2026-10-social-act-survey.md`](experiments/2026-10-social-act-survey.md)
(#486, merged: survey 5, S1 vs S1+S2). Rev. 1 merged as #488.

> **Building waits for the survey 5 results (#486).** The riskiest assumption
> is that Jev can read the social act of free player text at all. No PR in §8
> starts before the founders have answered, Fredrik has set the pass bar, and
> System 1 has been scored against the founder majority. If System 1 fails the
> bar, this plan is re-planned, not built.

**The motivating case (measured).** Live Jev reads the bare reply "Yes." as
action `buy`, target `ale_mug`, at confidence 0.47–0.77. The old test stubs said
`speak` at 0.95, which was wrong. The single call alone cannot tell "yes, I take
the ale" from "yes, I hear you". The listener who made the quote can. This case
drives listener readings (§3) and System 2 (§6).

## 1. What you're deciding

Each item lists options. This doc does not pick for the founders.

1. **Voice dB at 1 m (§2.2).** (a) whisper 40, talk 60, shout 85, Lombard rise
   for talk and shout; (b) no Lombard rise; (c) other values after a playtest.
2. **Clarity thresholds (§2.3).** (a) clear ≥ −3 dB SNR, partial ≥ −12;
   (b) stricter: clear ≥ 0, partial ≥ −9.
3. **Default noise and distance (§2.5).** (a) `ambient_db` per place file,
   fallback 50; addressee 1 m, others 3 m; (b) a default per place `scale` only.
4. **Whisper to the addressee in a loud room** (physics: none at 70 dB).
   (a) physics stands; (b) the addressee of a whisper is never below partial.
5. **Hearing modifier (§2.4); no hearing field exists today.** (a) race only
   (elf +3 dB); (b) race + `perception` skill (only with `JEV_CATALOGUE_V2`);
   (c) a new `hearing` value on `GameCharacter`.
6. **Liking scale N:** (a) 3; (b) 5; (c) 10. Integers in −N..N.
7. **Liking direction:** (a) directed, A→B and B→A are two rows; (b) symmetric.
8. **Liking start:** (a) 0; (b) from today's `relationship_score`; (c) world data.
9. **Partial hearing and liking:** (a) same delta (the misread is the effect);
   (b) half the delta.
10. **Ledger kinds first:** (a) `promise`; (b) + `debt`; (c) + `favour`, and a
    gift creates a small favour owed.
11. **An `accept` act** (the 14 labels lack it): (a) keep 14; (b) add `accept`,
    `decline` (breaks comparison with survey 5).
12. **System 2 model:** (a) a reasoning LLM; (b) a second Jev call; (c) decide
    after the comparison.
13. **The System 2 ship bar** (§6.5) and the level-2 labels (§6.4).

## 2. Hearing (pure game code, no LLM)

Fredrik's rule: hearing is computed in game code. Jev never says who heard what.
Jev reports the speaker's voice **once**, in the System 1 intent call (§6.1).
Code turns that voice, the room's noise, the distance and the listener's hearing
into a clarity per listener:

- **clear** → the listener gets the full line and a full reading;
- **partial** → the listener gets fragments of the line, so misunderstanding
  comes from what she actually heard;
- **none** → no reading, no Jev call, no tokens.

### 2.1 Structs and function

```elixir
# Social.Utterance: @enforce_keys [:speaker_id, :voice]  (:whisper | :talk | :shout | :none)
defstruct [:speaker_id, :voice, text: "", ambient_db: 50, addressee_id: nil, turn_number: 0]
# Social.Listener: @enforce_keys [:character_id]
defstruct [:character_id, distance_m: 3.0, hearing_db: 0]
# Social.Clarity: keep = share of words heard
defstruct level: :none, snr_db: nil, keep: 0.0

@spec clarity(Utterance.t(), Listener.t()) :: Clarity.t()
def clarity(%Utterance{} = u, %Listener{} = l)
```

`Hearing.listeners/2` builds `%Listener{}`s from the board (present characters
except the speaker).

### 2.2 Formula

```
voice_db      = level at 1 m (table below), with the Lombard rise
level_at_ear  = voice_db − 20·log10(max(distance_m, 0.25))   # inverse square: −6 dB per doubling
snr_db        = level_at_ear − ambient_db + hearing_db
```

| Voice | dB at 1 m | Lombard rise in noise (#481) |
|---|---|---|
| `whisper` | 40 | none: a whisper does not rise |
| `talk` | 60 | `min(max(60, ambient + 8), 75)` |
| `shout` | 85 | `min(max(85, ambient + 15), 90)` |
| `none` | no speech | every listener gets `:none`; the mood reaction still runs on what she sees |

Addressee distance: whisper 0.25 m (leaning in), talk or shout 1 m. No walls:
a character in another place is never a listener.

### 2.3 Thresholds

| Level | SNR | `keep` |
|---|---|---|
| clear | ≥ −3 dB | 1.0 |
| partial | −12 ≤ SNR < −3 | linear from 0.3 (at −12) to 0.9 (at −3) |
| none | < −12 dB | 0.0 |

Worked numbers (defaults of §2.5, hearing 0):

| Case | SNR | Result |
|---|---|---|
| talk to the addressee, quiet inn 50 dB | 60 − 0 − 50 = +10 | clear |
| talk, bystander 3 m, quiet inn | 60 − 9.5 − 50 = +0.5 | clear |
| talk, bystander 3 m, busy inn 70 dB | 75 − 9.5 − 70 = −4.5 | partial (keep 0.8) |
| whisper, bystander 3 m, quiet inn | 40 − 9.5 − 50 = −19.5 | none |
| whisper to the addressee, quiet inn | 40 + 12 − 50 = +2 | clear |
| whisper to the addressee, busy inn | 52 − 70 = −18 | none (decision 4) |
| shout, 6 m, busy inn | 85 − 15.6 − 70 = −0.6 | clear |

### 2.4 Hearing modifier

`hearing_db` comes from the character, through one pure function
`Hearing.modifier(%GameCharacter{}) :: integer`. No branch on PC or NPC.
Proposal (decision 5): race elf +3 dB (half-elf +1), and `perception` skill
level / 25 rounded down (0..+4 dB). Kept small so that distance and noise
dominate.

### 2.5 What exists today (inventory of `lib/` and the Tin Valley pack)

- **Room noise: none.** No `noise`, `ambient` or dB value exists in `lib/` or in
  `priv/adventures/tin_valley/world/*.md`. The only related data is the
  `quietly` manner (`Game.Catalogue`, `JevIntent`: stealth, +1 roll) and the
  "quiet turn" rule in `NPCSignals` (wait and train give no overhearing).
- **Distance inside a place: none.** A place is one point: `present_npcs` lists
  who is there, nothing says where. `Movement` "positions" are byte offsets in
  text, not space.
- **Place grid: in the pack, unused.** Tin Valley place files have
  `at: [x, y]` (a cell inside the parent place) and some have `scale`
  (`region`, `settlement`, `building`; only three files set it). `lib/` reads
  `parent` (`TalesForge.World`) but not `at` or `scale`. It is distance
  between places, not inside one.
- **Hearing: none as a value.** `GameCharacter` has `race` and `skills`. The
  `perception` skill exists only in skill list v2 (`JEV_CATALOGUE_V2`,
  `Mechanics`). The elf "Keen Senses" trait (+10 to perception-based skills in
  natural settings) is rule text in `rules/races.md`, not code.

**Minimal default:** an optional `ambient_db` key in each place file, read with
the place; fallback 50 dB. Proposed seeds: valley inn 60 (busy evening 70 is a
later time-of-day rule), market square 60, mine workings 70, cellar 35,
outdoors 40. Distance: the addressee at 1 m (whisper 0.25 m), everyone else in
the same place at 3 m. `%Listener{distance_m}` is a field, so positions inside a
place can replace the default later without changing `clarity/2`.

### 2.6 Fragments (deterministic)

`Hearing.fragment(text, %Clarity{keep: keep}, seed) :: String.t()` drops words.
It splits on whitespace only, so it reads no player-language keywords. Each word
is kept when a seeded draw is below `keep`; a dropped run becomes one "…". The
seed is `:erlang.phash2({session_id, turn_number, listener_id})`, so a replay
and a test give the same fragment. The partial listener's reaction call gets
the fragment in place of the line, marked "what she caught". Jev then reads what
she heard. The misunderstanding is real, not invented by the GM.

## 3. Listener readings in the per-NPC reaction call

### 3.1 Where it goes

The per-NPC call is `TalesForge.Game.NpcReactions` (`game/npc_reactions.ex`, Jev
purpose `npc_reaction`): stage 4, `Turn.Npcs.react/1`, one call per present
character, concurrent, 600 ms. Today it asks `emotion`, `intensity`, `stance`.

Before the calls, `Turn.Npcs` computes `Hearing.clarity/2` per listener. A
listener at `:none` gets no reading questions; if she also saw nothing (no
visible outcome), she gets no call at all. For the others the reading adds **two
questions to the same call**, not a new call:

| Field | Jev type | Labels | Into |
|---|---|---|---|
| `social_act` | Choice | the 14 G1 labels, survey-5 descriptions word for word (`SOCIAL_ACTS` in `build_survey.py`) | `Reading.act` |
| `meant_for` | Choice | `me`, `someone_else`, `everyone`, `no_one` | `Reading.target` |

There is no per-listener voice question: the voice is the speaker's, read once
by System 1, and clarity is code.

Changes, all in `NpcReactions`:

- `questions/1` (line 302) adds the two questions (module attributes, so the
  request stays byte-stable).
- `state/3` (line 268) gets the full line or the fragment (§2.6), the listener's
  liking toward the speaker (§4) and her open ledger entries with the speaker
  (§5), as labels from code.
- `reaction/3` (line 379) decodes into `%Reaction{}` with a `%Reading{}` inside.
- `Moment` gets `utterance: nil` and `clarities: %{}` (defaults). With no
  utterance the call is byte-identical to today.

Cost (#481): about +80 input tokens per heard listener. No added wait.

### 3.2 Structs

```elixir
# Social.Reading: @enforce_keys [:listener_id, :speaker_id]. act: one of the 14 labels;
# target: :me | :someone_else | :everyone | :no_one; clarity: :clear | :partial
defstruct [:listener_id, :speaker_id, act: :none, target: :no_one, clarity: :clear,
           confidence: 0.0, probs: %{}, depth: 1, about_me: nil, turn_number: nil]

# NpcReactions.Reaction: @enforce_keys [:character_id, :turn_number]
defstruct [:character_id, :turn_number, name: nil, emotion: nil, intensity: nil,
           stance: nil, stance_score: nil, confidence: nil, reading: nil]
```

`%Reaction{}` replaces today's string-keyed reaction map. The mood carried on
the character (`runtime["reaction"]`) keeps its JSON shape.

### 3.3 Rules

- Listeners are the characters present except the speaker. No PC/NPC check.
  Today the speaker is the human's character, so today the listeners are NPCs.
- A reading below the confidence gate (proposed 0.6, as G1) becomes `act: :none`
  and changes nothing social.
- Liking and the ledger use the **listener's** reading: two listeners can hear
  one line differently (#481: Brenna vs Hilde), and a partial one may mishear.
- The GM gets one short line per listener in the `npc_reactions` section
  ("Hilde caught fragments, heard a threat, meant for someone else").

## 4. Signed per-pair liking

**Today:** one float per NPC toward the player
(`runtime_state["relationship_score"]`, mirrored to `characters.relationships`).
It only goes up: `Actions.NPC.OnPlayerTalked` gives `{:warm, 0.05}` for every
line, also an insult.

`%Social.Liking{from_id, to_id, value: 0, last_turn: nil}` (value in −N..N;
`from_id`, `to_id` enforced). Pure core, `TalesForge.Social.Likings`:

- `delta(%Reading{}, %GameCharacter{} = listener) :: integer` — a table from act
  to base delta (`thanks` +1, `insult` −2, `threat` −2, …). OCEAN scales it (G2:
  high A softens a minus, high N enlarges it). `target` not `:me` gives 0 for
  now. Partial clarity per decision 9.
- `apply(%Liking{}, delta) :: %Liking{}` — adds and clamps to −N..N.
- `band(%Liking{}) :: :hostile | :cool | :neutral | :warm | :close` — for prompts
  and Jev state, so no number reaches a model.

Effects at the edge: `Turn.Npcs` turns each reading into an Intention
`{:like, to_id, delta}` of the listener; `Turn.Intentions.apply_all/2` writes it
in the turn's Multi. `{:warm, number}` stays for sessions with the flag off.

**Table `character_likings`** (migration described, not written): `id`
(binary_id PK), `game_session_id` (FK, cascade), `from_character_id`,
`to_character_id` (FK `characters`, cascade), `value` (integer, not null,
default 0, check `between -N and N`), `last_turn` (integer, null), `inserted_at`,
`updated_at` (`utc_datetime_usec`). Unique index `(from_character_id,
to_character_id)`; symmetric (decision 7) adds a check `from < to`. Writes are
upserts. One read per turn for the present characters, beside the cast.

## 5. Obligations ledger

```elixir
# Social.Obligation: @enforce_keys [:debtor_id, :creditor_id, :kind]  (:promise | :debt | :favour)
defstruct [:id, :debtor_id, :creditor_id, :kind, item_id: nil, amount_copper: nil,
           service: nil, status: :open,   # :open | :kept | :broken | :forgiven
           due_tick: nil, source_turn: nil, settled_turn: nil]
```

Pure core, `TalesForge.Social.Ledger`:

- `open(%Reading{}, %Stakes{}) :: [%Obligation{}]` — a clear `promise` reading
  (clarity `:clear`, confidence ≥ gate) by the creditor opens a `promise`. What
  was promised is a Jev Choice over the intent candidates (items, coins, "a
  service"), never parsed from words in Elixir.
- `settle(ledger, %TradeDone{}) :: {ledger, [change]}` — a finished trade from
  debtor to creditor with what was owed marks the entry `:kept`.
- `age(ledger, tick) :: {ledger, [change]}` — past `due_tick` → `:broken`, which
  gives the creditor a liking delta (§4).
- `forgive(ledger, id)` — only if the founders want it (decision 10).

**The trade rules hold.** The ledger never moves anything: items and coins move
only through `Trade.execute/1`, both sides accept, nothing is created or
destroyed. **Trade code is frozen:** the ledger reads trades after they happen
(the turn's trade events, `board.traders`) and does not change `Offer`, `Trade`,
`Offer.accepts?/1` or the open-offer question. NPC acceptance does not consult
the ledger. An unpaid-price "debt" is out of scope while trade is frozen.
`TalesForge.World` already keeps free-text facts of kind `"promise"` for the GM;
the ledger is the typed record and does not replace them in this design.

**Table `obligations`:** `id` (binary_id PK), `game_session_id`, `debtor_id`,
`creditor_id` (FKs, cascade), `kind`, `status` (`Ecto.Enum`, check), `item_id`,
`service` (string, null), `amount_copper` (integer, null, ≥ 0), `due_tick`,
`source_turn`, `settled_turn` (integer, null), `inserted_at`, `updated_at`
(`utc_datetime_usec`). Indexes `(game_session_id, status)`, `(creditor_id, debtor_id)`.

## 6. Two-speed understanding

### 6.1 System 1

The single Jev intent call (`TalesForge.Game.JevIntent`, from
`TalesForge.IntentJev.resolve/3`) on every line. It gains two questions:
`social_act` (the 14 labels) and `voice` (`whisper`, `talk`, `shout`, `none`;
#481). About +100 tokens. `voice` feeds `%Utterance{}` (§2). The output becomes:

```elixir
# Social.Understanding: @enforce_keys [:speaker_id]; source :s1 | :s2
defstruct [:speaker_id, act: :none, target: nil, voice: :talk, goods_confidence: nil,
           act_confidence: 0.0, act_probs: %{}, source: :s1, triggers: []]
```

### 6.2 The trigger (code decides, not the model)

`TalesForge.Social.Trigger.check(%Understanding{}, %Stakes{}) :: [trigger]`,
pure. `%Stakes{}` holds the open offer, the listeners' likings toward the speaker
and their top concern priorities. Triggers (survey doc):

| Trigger | Test |
|---|---|
| `:low_confidence` | `goods_confidence < 0.8` or `act_confidence < 0.8` |
| `:two_readings` | second act p ≥ 0.25, or top two within 0.15 |
| `:open_deal` | an open offer the line can answer |
| `:strong_stakes` | a listener's liking toward the speaker ≥ 0.6·N or ≤ −0.6·N, or a concern with priority ≥ 7 touching the line |

"Yes." with Brenna's open quote fires `:low_confidence` and `:open_deal`.

### 6.3 System 2

Runs only when `check/2` returns a non-empty list. It reasons briefly **as the
listener** (the addressee, or the first heard listener with stakes) and returns
one reading (act, target) with a confidence. It never decides. Code merges: take
System 2's answer on a question only when its confidence is higher than System
1's; then the G1 gate applies, the same for both. The result goes through the
existing clarify bands of `IntentJev`, so an unclear "Yes." still asks rather
than buys. It adds wait on triggered turns only. `ai_calls` purpose `intent_s2`.

### 6.4 Theory-of-mind depth (code decides, at most 2)

- **Level 1 (default):** what the speaker meant (the `%Reading{}` of §3).
- **Level 2:** what the speaker thinks of me, or of my reaction. One extra Choice
  `about_me` in the same listener call (or the same System 2 pass when S2 runs as
  that listener), never a new call. Proposed labels: `likes_me`,
  `distrusts_me`, `wants_something_from_me`, `testing_me`, `indifferent`.
- `Depth.for(%Listener{}, %Stakes{}) :: 1 | 2`, pure. Level 2 only when that
  listener has something at stake: the same stakes as the S2 triggers (an open
  deal with the speaker, a concern with priority ≥ 7, liking ≥ 0.6·N or
  ≤ −0.6·N). A `:partial` listener stays at level 1.
- **Never deeper than 2:** `@max_depth 2` is a module constant; no field or
  config raises it. Cost (#481): about +190 tokens per level-2 listener, no
  added wait. #481 earned level 2 on 19% of lines (Brenna, open deals).

### 6.5 Does System 2 ship? The survey comparison decides

Offline, on the 40 survey-5 lines, after the founders answer and Fredrik sets the
pass bar. Both systems get the same state. Per system: accuracy vs the founder
majority (act, target, voice; real and scripted apart), harmful confusions,
confident-wrong reads; for System 2 the trigger rate (and which trigger), lines
changed (right→wrong, wrong→right), cost per line and per triggered line, p50/p95
added latency. Proposed ship rule (decision 13):

| Measure | Proposed bar |
|---|---|
| Act accuracy gain, S1+S2 over S1 | ≥ +5 points, and S1+S2 meets the pass bar |
| Right→wrong changes | fewer than wrong→right; no new harmful confusion |
| Trigger rate | ≤ 30% of lines |
| Added cost | ≤ $0.001 per triggered line |
| Added latency | p95 ≤ 1.5 s on triggered lines |

If S2 misses the bar, it does not ship and the triggers stay as logged data.

## 7. Module sketch and hooks

`lib/ex_tales_forge/social/`: the structs above plus `hearing.ex`, `likings.ex`,
`ledger.ex`, `trigger.ex`, `depth.ex` (all pure), and `store.ex` (`load/2`,
`write_multi/2`, the only Ecto effects). Schemas `character_liking.ex`,
`obligation.ex`.

| Piece | Hooks into |
|---|---|
| Voice | `JevIntent.questions/2` (with `social_act`) |
| Hearing | `Turn.Npcs.react/1`, before the calls; `ambient_db` read with the place in `TalesForge.World` |
| Reading | `NpcReactions.questions/1`, `state/3`, `reaction/3`; `Moment` new fields |
| Liking | `Turn.Npcs` emits `{:like, …}`; `Turn.Intentions.apply_all/2` → `Social.Store` in `Turn.Store`'s Multi |
| Ledger | open in `Turn.Npcs`, age in `:npc_intentions`, settle in `Turn.Outcome.persist/1` (reads trade, never writes it) |
| S2 + depth | `IntentJev.resolve/3` after the S1 read; `Depth.for/2` in `Turn.Npcs` |
| Old regard | `OnPlayerTalked` stops `{:warm, 0.05}` when `LIKING` is on |

Framework only: Ecto, the turn's Multi, the existing `ProcessTurn` Oban job; no
new process. PubSub only for a later screen-only signal.

## 8. Plan: small verifiable PRs, most important first

**Gate 0 (not a build): survey 5 results (#486).** Founders answer; Fredrik
sets the pass bar; System 1 (with `social_act`) is scored offline on the 40
lines. Nothing below starts before this. If System 1 fails, re-plan.

Each PR is behind a flag (default off) and leaves the files it touches better.

1. **Live stubs for "Yes."** Replace the `speak 0.95` stubs with recorded live
   replies (buy `ale_mug` 0.47–0.77). Check: a test pins real behaviour.
2. **`Hearing` pure module.** Structs, `clarity/2`, `modifier/1`, `fragment/3`,
   no wiring. Check: unit tests for the §2.3 table, −6 dB per doubling (property
   test), same seed → same fragment.
3. **`%Reaction{}` struct** in `NpcReactions`, `Turn.Npcs`, `Turn.Prompt`, the
   playtest views. No behaviour change. Check: golden prompts byte-identical.
4. **S1 questions** `social_act`, `voice` in `JevIntent`, logged only; `mix
   social.eval` on survey 5. Check: the score against the bar.
5. **Hearing wired + listener readings** (`SOCIAL_READINGS`). `ambient_db` in
   the place files, default distances, clarity per listener, two questions,
   fragments for partial, logged on `turn.npc_reactions`. Check: playtest batch;
   `ai_calls` shows no call for `:none` listeners.
6. **Liking table and pure core** (`LIKING`). Migration, `Likings`, `{:like, …}`.
   Check: property tests (clamp, bands); an insult lowers liking in a playtest.
7. **Liking in use.** Into reaction state, the GM section, `%Stakes{}`;
   `{:warm, 0.05}` off under the flag. Check: playtest diff of reactions.
8. **S2 offline comparison.** `Trigger.check/2`, `Depth.for/2` (pure, tested)
   and the S2 pass in `mix social.eval`; a results doc. Founders decide.
9. **S2 live, shadow then on; level 2 in the listener call** (only if 8 passes).
   Check: trigger rate, cost, latency match the offline numbers.
10. **Obligations table and `Ledger`** (`OBLIGATIONS`). Check: unit tests; `git
    diff` empty under `game/trade.ex` and `game/offer.ex`.
11. **Ledger in use.** Into reaction state and the GM section; a broken promise
    lowers liking. Check: a scripted playtest with a promise.

PRs 2 and 8 touch no game path and can run beside the others.

## 9. Risks

- **Jev misreads in the extremes.** Playtest data has no insults, threats, jokes
  or whispers (#481); only the scripted survey lines test them. Gate 0 exists
  for this.
- **Bad listener reads change liking.** #481 saw Brenna hear her own accepted
  quote as "curt". Mitigation: gate, clamp, readings logged per turn.
- **Fragments mislead too much.** A 0.3 keep can turn any line into a threat.
  Mitigation: partial readings get a lower confidence in practice; decision 9.
- **Untuned dB numbers and one bystander distance.** Rough real-world values in
  one module attribute; every bystander in a place hears alike until positions.
- **The 14 labels lack `accept`** (decision 11).
- **Latency.** S2 adds wait on triggered turns (open deals are common); the bar caps it.
- **Existing word checks.** `Offer.asked?/1` reads player words in Elixir. It is
  trade code, so it stays frozen; noted for when trade unfreezes.

## 10. Out of scope

- Any change to trade: `Offer`, `Trade`, the open-offer question, NPC acceptance
  by liking or debt, credit and unpaid prices.
- Positions inside a place, walls, time-of-day noise; "lean in" as an action.
- Theory of mind deeper than level 2.
- NPC-to-NPC speech readings, readings of GM-narrated NPC lines.
- Knowledge per character, lies and secrets (G5), groups and norms (G6/G7).
- The System 2 prompt text and model tuning (after the comparison).
- UI for liking or the ledger; PubSub signals for them.
- Any DB backfill on production; decision 8 picks the start values first.
