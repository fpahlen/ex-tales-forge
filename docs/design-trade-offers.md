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
   message against the open offer as `accept`, `decline` or `other`. This
   is a new question in the Jev request, asked only while an offer is open.
   There is no button. While an offer is open, Jev's state also carries
   it with its options (`"open_offer"`), so the reply is read against the
   offer and not a side offer in the narration. A yes or a pick to the
   open offer never gets the generic "Do you want to …?" clarification;
   the offer was the question.
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
yes that picks no option buys nothing: the offer stays open with the same
options, and the GM asks which one the player wants, as an innkeeper
would. That turn does not count toward the 2-turn expiry; leaving the
place, the giver gone or a new offer still end it. If
nothing matches the stock, there is no offer and nothing moves. If the
reply matches none of the options, treat it like any other message under
the existing expiry rules.

## GM narration rules
- **Open offer:** "The server quotes: <Offer.text>. Nothing changed hands;
  narrate the quote and wait for the player's answer."
- **Unclear buy (open options):** "The server listed these options from
  stock: … Nothing changed hands; voice them as a counter-question and
  wait for the player's pick."
- **Yes with no pick:** "The player said yes but picked none of the
  options (…). Nothing changed hands; ask which one they want."
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
