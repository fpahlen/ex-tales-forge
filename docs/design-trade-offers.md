# Design: trade offers (offer, then accept)

Status: proposal for PR B. It builds on #473, which introduced `%Offer{}`
and `Offer.to_trade/2`. Confirmed shape: Fredrik, 2026-10-18.

## The rule
A trade happens only if both sides accept; otherwise nothing moves. Asking
a price or proposing a deal creates an **open offer**. The player accepts
or declines by typing. The NPC's acceptance is decided by pure code. When
both have accepted, `Trade.execute/1` runs in the turn's transaction.

## Flow
1. **Offer.** A price question ("How much for an ale?") or a proposal
   ("I'll give you 10c for the knife") builds `%Offer{giver, receiver,
   item, price, options}` from the seller's stock, or from the buyer's
   buy price for a sale. `item` may be `nil` when the buy is unclear
   (see Unclear buy); `options` defaults to `[]`. It is stored as the
   session's open offer. Nothing moves. The GM gets the quote. Jev reads
   a price question as the main action `ask_price`, aimed at an item or a
   kind of goods for sale here ("a meal": the kind's items are the
   options). It plays as a buy that only asks (`Offer.asked/1`,
   `Offer.asks?/1`); the game never reads the player's words for it
   (Gentry's retest of #476, session 6d938a30).
2. **Player answer.** On the next turn, Jev classifies the player's
   message against the open offer as `accept`, `decline`, `other_offer`
   (something else offered in the narration, such as the GM's kindling
   work) or `other`. This question is asked only while an offer is open.
   There is no button. While an offer is open, Jev's state also carries
   it with its options (`"open_offer"`). Jev reports its probabilities for
   every answer; pure code decides whether the answer is clear (see
   Unclear intent). A clear accept is the purchase; an unclear one moves
   nothing and the seller asks.
3. **NPC acceptance (pure).** `Offer.accepts?/1` checks the same things as
   `Trade.execute`'s acceptance: the NPC still has the stock or wants the
   item (`buys`), and the paying side can afford it. Later it also checks
   the NPC's money concern. Neither Jev nor the GM ever decides it.
4. **Execute.** If both accept, `Offer.to_trade/2` is passed to
   `Trade.execute/1`, and both sides are saved in the turn's Multi. On
   `{:error, reason}`, nothing moves and the GM gets the reason.

## Where the open offer lives
Use the simplest option: one key on the session's `world_state`,
`"open_offer"` (the offer's ids, item and price, plus `made_at_tick`;
`item` may be `nil` and `options` is a list that defaults to `[]`),
saved with the session row in the turn's Multi. No new table: there is at
most one open offer per session, it is short-lived, and it is already in
the row each turn loads. The giver and receiver are reloaded as
GameCharacters when the offer is answered, so stale purses never trade.

## Expiry and replacement
- A new offer replaces the open one.
- The offer expires when the player answers it (accept or decline), when
  the player leaves the place, when the giver is no longer present, or
  after 2 turns with no answer (`other`).
- An expired offer moves nothing. If the player later says "yes", it is
  read as a new message, with no offer open.

## "I buy X"
An explicit purchase is a proposal plus the player's acceptance in one
step: build the offer and run the NPC check, then `Trade.execute`, all in
the same turn. This is today's behaviour after #473. Only questions and
counter-proposals (haggling) leave an offer open.

## Unclear buy
An unclear buy like "I order a meal" becomes an open offer whose item is
unresolved (`item: nil`). Jev aims the buy at a kind of goods for sale
(`goods:a meal`, a target built from stock only for kinds with two or
more priced items, `Offer.kinds/1`); code lists that kind's items with
prices from the seller's real stock — two or three options — and stores
them on the offer as `options`. The game never matches the player's
words against a list of kind words. The GM voices that list as a
counter-question ("The stew, or bread and cheese?"), and nothing moves.
The player's next message picks one option; Jev resolves the pick against
the listed options only. That pick counts as proposal plus acceptance in
one step. Then the NPC decides in code as usual (stock, purse). A plain
yes that picks no option is unclear (see below): nothing moves, the offer
stays open with the same options, and the seller asks which one. A buy
aimed at the seller with no kind target whose words name nothing in her
stock ("I order a meal") is unclear too: she asks, offering her priced
stock. If the reply matches none of the options, treat it like any other
message under the existing expiry rules.

## Unclear intent: the NPC asks, nothing moves
Fredrik's steer (via Case, the PR after #478). When the player's intent
is unclear, nothing moves and the person they address asks a short
clarifying question in character, echoing the player's own words ("A
meal? You hungry? Stew or bread and cheese?", "Yes to the ale, or the
kindling?"). This replaces the templated "Do you want to buy X, or talk
to X?" prompt (and clarification v2) for the Jev read.

**Jev** only reports its confidence and its candidate readings (the
probabilities of its labels), with the open offer in its context.
`ask_price` and the offer answer stay Jev intents; Elixir reads no words.

**Pure code** (`TalesForge.Game.Clarify.decide/1`,
`TalesForge.Game.IntentClarification.band/2`) returns `:act` or
`{:clarify, candidates}`:

| Case | Clarifies when | Candidates |
|---|---|---|
| Open offer | two or more offer answers at ≥ 0.25 with `accept` among them; or `accept` below the goods threshold; or `accept` of an offer with options and no pick | the answers ("yes to the open offer: …", "something else offered in the last narration"), or the options |
| Moving goods or coins (`buy`, `sell`, `trade`, `spend`, `pickup`, `drop`, `equip`, `give`) | calibrated confidence < `INTENT_ACT_MIN_CONFIDENCE` (0.70) | the top two readings |
| Talk and the rest | confidence < `INTENT_ASK_BELOW_CONFIDENCE` (0.45), or raw < `INTENT_ASK_BELOW_RAW_CONFIDENCE` (0.45), and the top two differ in class (or a move/fight target is unsure) | the top two readings |
| Any read | a runner-up of another class at ≥ 0.25 (two plausible readings) | the top two readings |
| A buy that names nothing | aimed at a seller, no item, no options, and the words name nothing in her stock | her priced stock, cheapest first, at most 4 |

A buy that only asks the price (`ask_price`) moves nothing, so it uses the
talk threshold. A free-text answer to a pick question (`never_ask`) plays
its best guess. A clarify turn plays as words to the asker: the board
moves nothing and keeps an open offer as it is, not aged. The GM gets the
`## Player's intent: unclear, nothing happened` section with the words
and the candidates.

**Style: how hard she tries.** One pure function,
`TalesForge.Game.Clarify.patience/1`, from data the character already has
(no new trait, column or pack field):

    patience = 0.6 × agreeableness + 0.4 × conscientiousness      (OCEAN, 0-10; 5 when not authored)
             + Maslow shift   physiological −4, safety −2, belonging 0, esteem +0.5, self-actualisation +1
             + mood shift     a short mood (uneasy, aggrieved, angry, annoyed, irritated, impatient,
                              hostile, busy, grim, tired) −1; a warm one (cheerful, friendly, content,
                              happy, pleased, warm) +1; else 0

At a patience of 5.0 or more she is **helpful**: she echoes the words and
offers the candidates. Below 5.0 she is **brusque**: a short brush-off
("Speak plainly or move on."), no list. Either way nothing moves. With the
packs as authored: Brenna (A 8, C 7, belonging, cheerful) is 8.6, helpful;
Hilde (A 4, C 8, safety, uneasy) is 2.6, brusque; Brenna going hungry
(physiological) drops to 4.6, brusque. Jev never picks the style.

## GM narration rules
- **Open offer:** "The server quotes: <Offer.text>. Nothing changed hands;
  narrate the quote and wait for the player's answer."
- **Unclear buy (open options):** "The server listed these options from
  stock: … Nothing changed hands; voice them as a counter-question and
  wait for the player's pick."
- **Unclear intent:** the `## Player's intent: unclear, nothing happened`
  section: the player's words, the candidates, and the asker's style
  (helpful: echo and offer; brusque: a short brush-off). No item and no
  coins changed hands.
- **Accepted and done:** the existing "The server made this trade: ..."
  line.
- **Declined, expired or refused:** "No item and no coins changed hands"
  plus the reason. The GM never narrates a payment or a handover that the
  server didn't make.

## Tests
- **Pure:** `Offer.accepts?/1` (stock, purse, buys), `Offer.to_trade/2`,
  and expiry by tick, place and presence.
- **Turn, via `GameSessions.submit_message/3` with Jev stubbed:**
  - "How much for an ale?" followed by "Yes, one please" → the cask goes
    down by one, Brenna +2c, player −2c, with totals conserved.
  - A question followed by "No thanks" → nothing moves, and the offer is
    cleared.
  - A question, then the player leaves → the offer expires; a later "yes"
    moves nothing.
  - An accept after the NPC's purse or stock changed → refused, nothing
    moves, and the GM gets the reason.
  - "I buy an ale" still trades in one turn.
  - "I order a meal" → open offer with `item: nil` and 2–3 stock options;
    nothing moves. A pick that matches an option → proposal plus accept
    in one step, then NPC check and trade. A reply that matches none →
    treated as `other` under expiry. No matching stock → no offer,
    nothing moves.
- **Acceptance:** extend `trade_retest_470_test.exs` with an accept turn
  after T3.

## Out of scope
UI buttons, offers between NPCs, multi-item bundles, and persistent offer
history.
