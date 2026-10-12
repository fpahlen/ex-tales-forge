---
title: "Infrastructure in one page (for the founders' presentation)"
updated: 2026-10-12
source: ../infrastructure-setup.md
---

# How Tales Forge runs

Tales Forge runs as two apps on Fly.io in Stockholm. Playtest gets each change first. Production is what players use. GitHub keeps our code and our docs. GitHub also tests each change before it ships.

Three bots work with us. Case refines ideas and reviews work. Bobby builds and ships. Gentry tries to break things on playtest. When you move a card on the idea board, the board wakes the right bot. When you move a card to Building, the board writes the decision in our decision log.

```
Idea board ──wakes──> Case / Bobby ──PR──> GitHub checks
                                              │
                                              v
                                   Playtest ──Gentry checks──> Production
                                              (admin and security fixes ship by themselves)
```

## Key facts

- **Two apps, two databases.** Playtest and production each have their own database. A test never touches player data.
- **Playtest first.** Every change goes to playtest before production.
- **One founder OK is enough.** Any founder approves a PR on its board card.
- **Fast lanes.** Admin-page changes and safe security fixes ship without a manual OK.
- **Cards finish by themselves.** A card moves to Done when its change is live on production.
- **Only the team gets in.** You sign in with GitHub. Only members of the Tales Forge team can open the site.

The full runbook is [Infrastructure setup](../infrastructure-setup.md).
