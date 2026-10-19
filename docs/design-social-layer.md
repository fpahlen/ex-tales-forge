---
title: "Design: social layer (listener readings, liking, obligations, two-speed)"
updated: 2026-10-19
status: design (for Case's review, no code yet)
---

# Design: social layer

**Status:** design note, 2026-10-19. Docs only, no code. Scope set by Fredrik
(via Case). Code: [whyse-ab/ex-tales-forge](https://github.com/whyse-ab/ex-tales-forge),
main `908280f`. Inputs:

- [`analysis-social-levers.md`](analysis-social-levers.md) (PR #479): the 14
  social-act labels (G1), regard per pair (G2), the obligations ledger (G4).
- PR #481, `docs/experiments/2026-10-two-step-jev.md` (open): keep the single
  Jev call, add `voice`, fold listener readings into the existing
  `npc_reaction` call.
- PR #486, `docs/experiments/2026-10-social-act-survey.md` (open): founder
  survey 5 (40 lines) and the System 1 vs System 1 + System 2 comparison.

**The motivating case (measured).** Live Jev reads the bare reply "Yes." as
action `buy`, target `ale_mug`, at confidence 0.47–0.77. The old test stubs said
`speak` at 0.95, which was wrong. The single call alone cannot tell "yes, I take
the ale" from "yes, I hear you". The listener who made the quote can. This case
drives listener readings (§2) and System 2 (§5).

## 1. What you're deciding

Each item lists options. This doc does not pick for the founders.

1. **Who gets a listener reading.**
   (a) every present character except the speaker, at most 4 (today's
   `@max_npcs`); (b) only the addressee; (c) the #481 hearing cut (needs
   positions inside a place, which the world does not have yet).
2. **Liking scale N.** (a) −3..+3; (b) −5..+5; (c) −10..+10. Integers in all
   cases.
3. **Liking direction.** (a) directed: A's liking of B and B's liking of A are
   two rows; (b) symmetric: one row per unordered pair.
4. **Start value of liking.** (a) 0 for everyone; (b) seed from today's
   `relationship_score` (rounded and clamped); (c) per-NPC seed in world data
   (for example the innkeep starts at +1 toward travellers).
5. **Ledger kinds in the first build.** (a) `promise` only; (b) `promise`,
   `debt` (coin or item); (c) all of `promise`, `debt`, `favour`, `gift`.
6. **Does a gift create a favour owed?** (a) no, a gift only changes liking;
   (b) yes, a small `favour` the receiver owes.
7. **An `accept` act.** The 14 labels have no `accept`. "Yes." to a quote is
   today answered by the frozen open-offer question. (a) keep the 14 labels;
   (b) add `accept` and `decline` (breaks comparison with survey 5).
8. **The System 2 model.** (a) a reasoning LLM (grok, short budget);
   (b) a second Jev call with the listener's full state; (c) decide after the
   comparison runs both.
9. **The ship bar for System 2** (§5.4). Proposed values are in the table there.
10. **Rollout flags.** (a) playtest only until the survey comparison is done;
    (b) playtest and new production sessions after each PR's own check.

## 2. Listener readings in the per-NPC reaction call

### 2.1 Where it goes

The per-NPC call already exists: `TalesForge.Game.NpcReactions`
(`lib/ex_tales_forge/game/npc_reactions.ex`), Jev purpose `npc_reaction`. Stage 4
of the turn, `TalesForge.Game.Turn.Npcs.react/1`, calls it through the `npc`
adapter, one call per present character, concurrently (`Task.async_stream`,
600 ms). It asks three questions today: `emotion`, `intensity`, `stance`.

The reading adds **three questions to the same call**, not a new call:

| Field | Jev type | Labels | Into |
|---|---|---|---|
| `social_act` | Choice | the 14 G1 labels, with the survey-5 descriptions word for word (`SOCIAL_ACTS` in `build_survey.py`) | `Reading.act` |
| `meant_for` | Choice | `me`, `someone_else`, `everyone`, `no_one` | `Reading.target` |
| `voice_heard` | Choice | `whisper`, `talk`, `shout`, `none` (#481 levels) | `Reading.voice` |

Changes, all in `NpcReactions`:

- `questions/1` (line 302) adds the three questions. Labels and descriptions are
  module attributes, so the request stays byte-stable.
- `state/3` (line 268) adds two lines: the listener's liking toward the speaker
  (§3) and her open ledger entries with the speaker (§4), as labels from code.
- `reaction/3` (line 379) decodes the reply into `%Reaction{}` with a
  `%Reading{}` inside (§2.2).
- `Moment` gets `speaker_id` (default `nil`) and `readings?: false`. With
  `readings?: false` the call is byte-identical to today.

Cost (from #481): about +100 input tokens per listener, about $0.000004. No added
wait: the questions ride in a call that already runs.

### 2.2 Structs

```elixir
defmodule TalesForge.Social.Reading do
  @enforce_keys [:listener_id, :speaker_id]
  defstruct [:listener_id, :speaker_id,
             act: :none,           # one of the 14 labels
             target: :no_one,      # :me | :someone_else | :everyone | :no_one
             voice: :talk,         # :whisper | :talk | :shout | :none
             confidence: 0.0,      # min of the three questions
             probs: %{},           # %{act: %{label => p}}, for S2 triggers
             turn_number: nil]
end

defmodule TalesForge.Game.NpcReactions.Reaction do
  @enforce_keys [:character_id, :turn_number]
  defstruct [:character_id, :turn_number, name: nil,
             emotion: nil, intensity: nil, stance: nil, stance_score: nil,
             confidence: nil, reading: nil]   # reading: %Reading{} | nil
end
```

`%Reaction{}` replaces today's string-keyed reaction map. `intentions/1`,
`Turn.Prompt` and the playtest views match on `%Reaction{}`. The mood that
carries over on the character (`runtime["reaction"]`) keeps its JSON shape.

### 2.3 Rules

- Readings come from **listeners**: the characters present except the speaker.
  No code checks if a character is a PC or an NPC. Today the speaker is always
  the human's character, so today the listeners are NPCs.
- A reading below the confidence gate (proposed 0.6, same gate as G1) becomes
  `act: :none` before anything uses it. It changes nothing social.
- The speaker's own act comes from System 1 (§5). The listener's reading is how
  she heard it. Liking and the ledger use the **listener's** reading, because two
  listeners can hear one line differently (#481: Brenna vs Hilde).
- The GM gets one short line per listener in the existing `npc_reactions` prompt
  section ("Brenna heard a thanks, meant for her").

## 3. Signed per-pair liking

### 3.1 Today

Regard is one float per NPC toward the player (`runtime_state["relationship_score"]`,
mirrored to `characters.relationships` keyed by the PC slug). It only goes up:
`Actions.NPC.OnPlayerTalked` gives `{:warm, 0.05}` for every line, also an insult.

### 3.2 Model

```elixir
defmodule TalesForge.Social.Liking do
  @enforce_keys [:from_id, :to_id]
  defstruct [:from_id, :to_id, value: 0, last_turn: nil]   # value in -N..N
end
```

Pure core, `TalesForge.Social.Likings`:

- `delta(%Reading{}, %GameCharacter{} = listener) :: integer` — a table from act
  label to base delta (for example `thanks` +1, `insult` −2, `threat` −2,
  `flattery` 0 or +1 by agreeableness). The heard voice scales it: `shout` makes
  a minus larger, `none` gives 0. OCEAN scales it as G2 says: high A softens a
  minus, high N makes it larger. `target: :someone_else` or `:no_one` gives 0 for
  now.
- `apply(%Liking{}, delta) :: %Liking{}` — adds and clamps to −N..N.
- `band(%Liking{}) :: :hostile | :cool | :neutral | :warm | :close` — for
  prompts and Jev state, so no number reaches a model.

Effects at the edge: `Turn.Npcs` turns each reading into an Intention
`{:like, to_id, delta}` of the listener. `Turn.Intentions.apply_all/2` writes it
in the turn's Multi. `{:warm, number}` stays for sessions with the flag off and
goes away in a later PR.

### 3.3 Data model

Table `character_likings` (migration described, not written):

| Column | Type | Note |
|---|---|---|
| `id` | binary_id | PK |
| `game_session_id` | binary_id, FK `game_sessions`, on delete cascade | |
| `from_character_id` | binary_id, FK `characters`, on delete cascade | |
| `to_character_id` | binary_id, FK `characters`, on delete cascade | |
| `value` | integer, not null, default 0 | check `value between -N and N` |
| `last_turn` | integer, null | |
| `inserted_at`, `updated_at` | `utc_datetime_usec` | UTC |

Unique index on `(from_character_id, to_character_id)`. If the founders pick
symmetric (decision 3), add a check `from_character_id < to_character_id`.
Writes are upserts (`on_conflict: {:replace, [:value, :last_turn, :updated_at]}`).
Reads: one query per turn for the present characters, loaded beside the cast.

## 4. Obligations ledger

### 4.1 Model

```elixir
defmodule TalesForge.Social.Obligation do
  @enforce_keys [:debtor_id, :creditor_id, :kind]
  defstruct [:id, :debtor_id, :creditor_id, :kind,  # :promise | :debt | :favour
             item_id: nil, amount_copper: nil, service: nil,  # service: a label from code
             status: :open,                # :open | :kept | :broken | :forgiven
             due_tick: nil, source_turn: nil, settled_turn: nil]
end
```

Pure core, `TalesForge.Social.Ledger`:

- `open(%Reading{}, %Stakes{}) :: [%Obligation{}]` — a clear `promise` reading
  (confidence ≥ gate) by the creditor opens a `promise`. What was promised is a
  Jev Choice over the same candidates as the intent target (items, coins,
  "a service"), never parsed from words in Elixir.
- `settle(ledger, %TradeDone{}) :: {ledger, [change]}` — a finished trade whose
  giver is the debtor and receiver is the creditor, with the item or amount
  owed, marks the entry `:kept`.
- `age(ledger, tick) :: {ledger, [change]}` — an open entry past `due_tick`
  becomes `:broken`. A broken entry gives the creditor a liking delta (§3).
- `forgive(ledger, id)` — from a clear `thanks` or `gift` reading toward the
  debtor, if the founders want it (decision 5).

### 4.2 The trade rules hold

- **The ledger never moves anything.** It is a record of who owes whom. Items and
  coins move only through `Trade.execute/1`, both sides accept, nothing is
  created or destroyed.
- **Trade code is frozen.** The ledger reads trades **after** they happen, from
  the turn's trade events (`board.traders` and the trade event rows). It does not
  change `Offer`, `Trade`, `Offer.accepts?/1` or the open-offer question. NPC
  acceptance does not consult the ledger in this design.
- A "debt" for an unpaid price is out of scope while trade is frozen: today a
  trade that cannot be paid does not happen.

### 4.3 Data model

Table `obligations`: `id` (binary_id PK), `game_session_id` (FK, cascade),
`debtor_id`, `creditor_id` (FK `characters`, cascade), `kind` (string, check in
list), `item_id` (string, null), `amount_copper` (integer, null, check ≥ 0),
`service` (string, null, a code label), `status` (string, default `open`),
`due_tick`, `source_turn`, `settled_turn` (integer, null),
`inserted_at`, `updated_at` (`utc_datetime_usec`). Index on
`(game_session_id, status)` and on `(creditor_id, debtor_id)`. Ecto schema
`TalesForge.Schemas.Obligation`; `Ecto.Enum` for `kind` and `status`.

## 5. Two-speed understanding

### 5.1 System 1

The single Jev intent call (`TalesForge.Game.JevIntent`, called from
`TalesForge.IntentJev.resolve/3`) on every line. It gains two questions:
`social_act` (the 14 labels) and `voice` (#481). About +100 tokens. Its output
becomes `%Understanding{}`:

```elixir
defmodule TalesForge.Social.Understanding do
  @enforce_keys [:speaker_id]
  defstruct [:speaker_id, act: :none, target: nil, voice: :talk,
             goods_confidence: nil, act_confidence: 0.0, act_probs: %{},
             source: :s1,                 # :s1 | :s2
             triggers: []]                # why S2 ran, if it did
end
```

### 5.2 The trigger (code decides, not the model)

`TalesForge.Social.Trigger.check(%Understanding{}, %Stakes{}) :: [trigger]`, pure.
`%Stakes{}` holds the open offer (from world state), the listeners' likings toward
the speaker and their top concern priorities. Triggers, from the survey doc:

| Trigger | Test |
|---|---|
| `:low_confidence` | `goods_confidence < 0.8` or `act_confidence < 0.8` |
| `:two_readings` | second act p ≥ 0.25, or top two within 0.15 |
| `:open_deal` | an open offer the line can answer |
| `:strong_stakes` | a listener's liking toward the speaker ≥ 0.6·N or ≤ −0.6·N, or a concern with priority ≥ 7 touching the line |

"Yes." with Brenna's open quote fires `:low_confidence` (0.47–0.77) and
`:open_deal`.

### 5.3 System 2

Runs only when `check/2` returns a non-empty list. It reasons briefly **as the
listener** (the addressee, or the first listener with stakes) and returns one
reading (act, target, voice) with a confidence. It never decides. Code merges:
take System 2's answer on a question only when its confidence is higher than
System 1's; then the G1 gate applies, the same for both. The result goes back
through the existing clarify bands of `IntentJev`, so an unclear "Yes." still
asks rather than buys. System 2 runs after System 1, so it adds wait on
triggered turns only. Each call is an `ai_calls` row (purpose `intent_s2`).

### 5.4 Does System 2 ship? The survey comparison decides

Offline, on the 40 survey-5 lines, after the founders answer and Fredrik sets the
pass bar. Both systems get the same state. The report gives, per system:
accuracy vs the founder majority (act, target, voice; real and scripted apart),
harmful confusions, confident-wrong reads; for System 2 the trigger rate (and
which trigger), lines changed (right→wrong, wrong→right), cost per line and per
triggered line, and p50/p95 added latency.

Proposed ship rule (decision 9; founders set the numbers):

| Measure | Proposed bar |
|---|---|
| Act accuracy gain, S1+S2 over S1 | ≥ +5 points, and S1+S2 meets the pass bar |
| Right→wrong changes | fewer than wrong→right, and no new harmful confusion |
| Trigger rate | ≤ 30% of lines |
| Added cost | ≤ $0.001 per triggered line |
| Added latency | p95 ≤ 1.5 s on triggered lines |

If S1 alone passes and S2 does not meet the bar, S2 does not ship and the
triggers stay as logged data only.

## 6. Module sketch and hooks

```
lib/ex_tales_forge/social/
  reading.ex         %Reading{}            (pure)
  understanding.ex   %Understanding{}      (pure)
  liking.ex          %Liking{}             (pure)
  likings.ex         delta/2, apply/2, band/1             (pure)
  obligation.ex      %Obligation{}         (pure)
  ledger.ex          open/2, settle/2, age/2, forgive/2   (pure)
  stakes.ex          %Stakes{}, from_board/2              (pure)
  trigger.ex         check/2                              (pure)
  store.ex           load/2, write_multi/2  (Ecto, the only effects)
lib/ex_tales_forge/schemas/character_liking.ex, obligation.ex
```

| Piece | Hooks into |
|---|---|
| Reading | `NpcReactions.questions/1`, `state/3`, `reaction/3`; `Moment` new fields |
| Liking deltas | `Turn.Npcs.reactions/3` emits `{:like, to_id, delta}`; `Intention` type gains it |
| Liking writes | `Turn.Intentions.apply_all/2` → `Social.Store` in the turn's Multi (`Turn.Store`) |
| Liking reads | loaded with the cast in `Turn.new/3`; into reaction `state/3` and the GM section |
| Ledger open/age | `Turn.Npcs` (readings) and the `:npc_intentions` step (ticks) |
| Ledger settle | `Turn.Outcome.persist/1`, after the trade events exist; reads, never writes trade |
| S1 questions | `JevIntent.questions/2` |
| S2 trigger + pass | `IntentJev.resolve/3`, after the S1 read, before the clarify band |
| Old regard | `OnPlayerTalked` stops emitting `{:warm, 0.05}` when `LIKING` is on |

Framework only: Ecto for both tables and the Multi; the turn already runs in the
`ProcessTurn` Oban job; no new process. PubSub only if the play page later shows
liking (screen-only signal).

## 7. Plan: small verifiable PRs, most important first

Each PR is behind a flag (default off) and leaves the files it touches better.

1. **Live stubs for "Yes."** Replace the `speak 0.95` stubs with recorded live
   Jev replies (buy `ale_mug` 0.47–0.77) in the intent and reaction test
   fixtures. Check: a test that pins today's real behaviour.
2. **`%Reaction{}` struct.** Replace the string-keyed reaction map in
   `NpcReactions`, `Turn.Npcs`, `Turn.Prompt` and the playtest views. No behaviour
   change. Check: golden prompt fixtures byte-identical.
3. **Listener reading** (`SOCIAL_READINGS`). Three questions, `%Reading{}`,
   logged on the `turn.npc_reactions` row meta, one line to the GM. Check: a
   playtest batch; readings vs founder labels on the real survey lines.
4. **S1 questions** (`social_act`, `voice` in `JevIntent`), logged only. A
   `mix social.eval` task scores S1 on survey 5. Check: the report against the
   pass bar.
5. **Liking table and pure core** (`LIKING`). Migration, `Likings`, `{:like, …}`
   Intention, upsert in the Multi. Check: property tests (clamp, bands), and an
   insult lowers liking in a playtest.
6. **Liking in use.** Into reaction `state/3`, the GM section and `%Stakes{}`;
   `{:warm, 0.05}` off under the flag. Check: playtest diff of reactions.
7. **S2 offline comparison.** `Trigger.check/2` (pure, unit tested) and the S2
   pass inside `mix social.eval`; a results doc. Check: the §5.4 report. Founders
   decide.
8. **S2 live, shadow then on** (only if 7 passes). Hook in `IntentJev.resolve/3`.
   Check: `ai_calls` trigger rate, cost and latency match the offline numbers.
9. **Obligations table and `Ledger`** (`OBLIGATIONS`). Open from `promise`
   readings, age by tick, settle from trade events. Check: unit tests on the pure
   core; a test that no trade module changed (`git diff` empty under `game/trade.ex`
   and `game/offer.ex`).
10. **Ledger in use.** Open entries into reaction state and the GM section; a
    broken promise lowers liking. Check: a scripted playtest with a promise.

PRs 4 and 7 can run in parallel with 3–6: they touch only the eval path.

## 8. Risks

- **Jev misreads in the extremes.** Playtest data has no insults, threats, jokes
  or whispers (#481). The scripted survey lines are the only test until real play
  has them. Mitigation: the gate, and liking deltas that are small against N.
- **Bad listener reads change liking.** #481 saw Brenna hear her own accepted quote
  as "curt". Mitigation: gate, clamp, and readings logged per turn so a bad
  pattern shows in the playtest view.
- **The 14 labels lack `accept`.** "Yes." to a quote may read as `none` or
  `request` (decision 7).
- **Stakes leak into S1.** S1 must stay the same call on every line; liking goes
  only into the reaction call and `%Stakes{}`, never into the intent state.
- **Latency.** S2 adds wait on triggered turns. A high trigger rate (open deals
  are common at the inn) can make it felt. The ship bar caps it.
- **Two regard stores during rollout.** `relationship_score` and
  `character_likings` live side by side until PR 6; old sessions keep the old one.
- **Prompt growth.** Each listener adds about 100 tokens to her call and a line to
  the GM. Cap stays at 4 listeners.
- **Existing word checks.** `Offer.asked?/1` reads player words in Elixir. It is
  trade code, so it stays frozen; noted for when trade unfreezes.

## 9. Out of scope

- Any change to trade: `Offer`, `Trade`, the open-offer question, NPC
  acceptance by liking or debt, credit and unpaid prices.
- The hearing cut with positions and dB (#481 design); needs place positions.
- Theory of mind level 2 (#481 later stage).
- NPC-to-NPC speech readings, and readings of GM-narrated NPC lines.
- Knowledge per character, lies and secrets (G5), groups and norms (G6/G7).
- The System 2 prompt text and model tuning (after the comparison).
- UI for liking or the ledger; PubSub signals for them.
- Any DB backfill on production; decision 4 picks the start values first.
