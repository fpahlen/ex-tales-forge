# 2. Raw player text never reaches the storyteller

![A sealed envelope passing a gate toward a waiting GM](images/02-intent.jpg)

We learned this the hard way: if you hand the GM the messy sentence, it starts inventing dice.

So we clean it first.

```mermaid
flowchart TD
  A["Player: I sneak past the cut"] --> B["Heuristic first, else Tier 1 LLM"]
  B --> C["PlayerAction JSON"]
  C --> D["Server: dice, move, inventory"]
  D --> E["Table GM"]
  F["Perceived world only"] --> E
```

- **Tier 1** is the only prompt that sees messy language. Jailbreak theater lives there — not in the Guild’s brain, not in the GM.
- Clear “go to the square” is a heuristic (~0 ms). Ambiguity **asks**; it does not guess the plot.
- The table GM receives validated intent, a handler result, and facts. It **narrates**. It does not parse.

---

**Speaker notes.** Two-tier is not fashion. Raw text in the storyteller is how you get invented mechanics and prompt injection in the same breath. Clear “go to the square” does not even need a model. Heuristics keep the common case off Grok so a full turn can stay under a few seconds.
