# Principles

## North star: ETC — Easy To Change
Good design is design that is easier to change than the alternative. Every decision, from a module name to a database table, is judged by one question: does this make the next change easier or harder? Code is read and changed far more often than it is written, by people and agents who do not remember why it is the way it is. Working code that is hard to change is a liability.

## What prevents ETC, and the principle against each

1. Duplicated knowledge → DRY — Don't Repeat Yourself.
   Every piece of knowledge has one authoritative place. DRY is about knowledge and intent, not about identical lines of code: two functions that look alike but mean different things may stay apart; one business rule written in two places must not. When a rule changes, you change it once.

2. Coupling → Orthogonality.
   Parts that do different jobs do not know about each other. A change in one place must not ripple into unrelated places. Signs of coupling: dependency cycles, modules that reach into another's internals, a function that needs eight arguments.

3. Hidden effects → Pure core, effects at the edges.
   Logic is plain data in, plain data out. Saving, sending, calling an API or an LLM happen at the edges, where they are easy to see, test and replace.

4. Irreversible decisions → Reversibility.
   No decision is final. Hide vendors, services and formats behind a small boundary so they can be swapped. Ship risky behaviour behind a switch.

5. Decay → No broken windows.
   One tolerated mess invites the next. The code health ratchet makes today the worst the code may ever be: no metric may get worse, and every improvement becomes the new floor.
   Kaizen: every PR leaves the code we write a little better, counted as the Credo ABC complexity of the `lib/` files it touches (`mix health.check`).
   - Net: the touched files that already exist on main must together score at least one point lower than on main. A deleted file counts as all of its score taken away. A new file is left out of the net; it only has to keep to the per-function limits (complexity, ABC size, 4+ parameters), like all code.
   - One existing file may get slightly worse only when the same PR improves other code we write so the net still drops by at least one point, and the PR description says why that file got worse.
   - Hard cap: no file may score more than 10% above main, or 3 points above it when that is more (so a small file can still grow). Beyond that it must be split.
   - The ratchet applies only to code we write (`lib/`), never to deps, framework-dictated shapes, `@impl` callbacks or `~p` router edges. Docs- and config-only PRs touch no `lib/` file, so the net does not apply to them.

6. Guessing → Prove it.
   Tests show behaviour, health metrics show structure, real use shows value. Do not trust what you have not measured.

7. Clever over clear → Write for the reader.
   The next reader is a tired human or a fresh agent with no context. Plain names, small functions, structs over long argument lists, comments that say why.

## Practices in Tales Forge
- A turn is a pipeline of data transformations (Jev, premise check, mechanics, NPCs, prompt, GM, save), with side effects at the edges.
- The server decides, the GM narrates. Game facts (money, debts, deals, prices, position, who fled) are exact data; the GM never invents them.
- There is only GameCharacter. Every character has the same data, rules, memory and abilities. A Player Character is a GameCharacter whose intentions come from a human; an NPC is a GameCharacter whose intentions come from the system or the GM. Nothing else may differ: code never branches on player versus NPC except where intentions come in. Memories fade and are biased by each character's interests; game facts never are. Character code gets turn data passed in and never calls back into the turn processor.
- The domain never calls the web layer. The UI is built from components first; layouts and styles come after.
- Risky game behaviour ships behind a flag that stays off on prod until it passes on playtest.
- Times are stored in UTC and shown in the viewer's local time. A dependency is added only if it is actively maintained or held in high standing in the community.
- Design, UX and plan docs live in docs/ on GitHub, never only on the bot box.
