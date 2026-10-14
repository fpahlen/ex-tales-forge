# Skill Domains and Progression System

This document defines the skill domain architecture for the RPG system, establishing how skills group together, transfer between each other, and scale with mastery.

Why: as you get better you see general patterns, not just exact moves.
Related skills transfer. See `PRODUCT.md` → Rules philosophy.

---

## The Five Domains

Skills are organized into five **Domains** — broad categories sharing underlying physical, mental, or social foundations.

### Domain Definitions

| Domain | Core Attributes | Description |
|--------|----------------|-------------|
| **Martial** | STR, DEX, CON | Combat and physical confrontation |
| **Finesse** | DEX, INT | Precision, stealth, and manipulation |
| **Social** | CHA, WIS | Interpersonal influence and perception |
| **Knowledge** | INT, WIS | Academic learning and lore |
| **Craft** | INT, DEX | Creation, repair, and practical application |

---

## Skill → Domain Mappings (skill list v2, 2026-10-12)

28 skills. A skill grows only from failures in that exact skill.

### Martial Domain
- Melee Combat
- Ranged Combat (includes throwing)
- Unarmed Combat
- Dodge (includes blocking with a shield)
- Tactics

### Finesse Domain
- Stealth
- Lockpicking
- Climbing
- Sleight of Hand (includes pickpocketing)
- Acrobatics (includes escaping bonds)

### Social Domain
- Persuasion (includes haggling)
- Deception
- Intimidation
- Insight (motives and lies)
- Etiquette
- Perception (search, spot, notice)
- Performance

### Knowledge Domain
- History (includes geography, law and religion)
- Arcana
- Survival (includes nature and finding herbs)
- Tracking
- Medicine (includes first aid)
- Appraisal (true value, scarcity and the fair local price)

### Craft Domain
- Smithing
- Carpentry
- Leatherworking
- Cooking (a simple meal needs no roll)
- Alchemy

There is no general crafting skill.

### Bargaining

Haggling is a Persuasion roll. Appraisal is a separate roll that the player can skip. A successful appraisal tells the true value, the local scarcity and the fair local price. Knowing the price gives +10 to the Persuasion roll (+15 at Appraisal 50 or higher), and the haggle starts from the fair price. A success moves the price 10-20% in the player's favour. A failure caps the deal at the fair price minus 10%.

---

## Progression Tiers

| Tier | Level Range | Phase | Hours (~) | Real-World Equivalent |
|------|-------------|-------|-----------|----------------------|
| **Novice** | 1-25 | Cognitive | 0-100 | Hobbyist, casual practitioner |
| **Adept** | 26-50 | Associative | 100-1,000 | Serious amateur, professional basics |
| **Expert** | 51-75 | Autonomous | 1,000-3,000 | Working professional, instructor |
| **Master** | 76-100 | Deliberate Practice | 3,000-10,000 | World-class, decades of dedication |

### Hours Formula (Power Law)
```
Hours = 10,000 × (Level / 100)³
```

---

## Domain Affinity (Intra-Domain Transfer)

When you reach threshold levels in one skill, related skills in the **same domain** gain a **floor** — you can't be truly incompetent at related things.

| Highest Skill in Domain | Floor for Other Domain Skills |
|-------------------------|-------------------------------|
| 1-49 | 0 (skills are still islands) |
| 50-74 | 10 (patterns starting to connect) |
| 75-89 | 20 (flow state, unconscious competence) |
| 90-100 | 30 (universal principles visible) |

**Note**: The floor applies only to skills the character has NOT trained. If they have actual skill levels, use the higher of floor or trained level.

---

## Summit Sight (Cross-Domain Recognition)

At **Level 90+** in any skill, masters gain the ability to **recognize principles** in other domains.

### Mechanical Effects
- **Narrative Recognition**: GM describes cross-domain insights
- **First Attempt Bonus**: +10 to initial tries at new "spiritually adjacent" skills

### Spiritually Adjacent Skills
Skills are "spiritually adjacent" when they share underlying principles despite being in different domains:

| Master Skill | Adjacent Skills (Other Domains) |
|--------------|--------------------------------|
| Melee Combat | Performance (dance), Smithing (weapons) |
| Stealth | Tactics, Deception |
| Persuasion | Performance, Leadership |
| Arcana | Alchemy |
| Smithing | Melee Combat (weapon feel), Alchemy (metallurgy) |

---

## Attribute Echo (Skill → Stat Feedback)

High skill levels in a domain grant **contextual stat bonuses** when performing domain-related tasks.

| Domain Mastery Level | Stat Bonus (in-domain only) |
|---------------------|----------------------------|
| 50-74 (Adept) | +1 to linked attributes |
| 75-89 (Expert) | +2 to linked attributes |
| 90-100 (Master) | +3 to linked attributes |

**Example**: A Level 75 Melee Combat character (Martial domain) gets +2 to effective STR, DEX, and CON when performing any Martial domain action.

---

<!-- skill_split:on -->
## Skill Split by Skill Family

The rule is in `core_mechanics.md`, "Skill split". This table gives the meaning of each part for a skill family.

| Skill family | Meaning of a split |
|--------------|--------------------|
| Combat (melee, ranged, unarmed) | Each part is one attack. One foe parries one attack at most, so the other attacks get no parry. |
| Climbing | Each part is one stretch of the climb. Two successful parts give double climb speed. |
| Lockpicking | Each part is one lock. |
| Persuasion | Each part is one listener. |
| Default (a skill with no entry) | Each part is a separate attempt in the same turn. |

<!-- /skill_split:on -->
## LP Progression: Learn From Failure, Sleep On It (Physical Skills: Right Away)

A failure or a near miss banks one Learning Point for the skill rolled; a success, a critical success or a critical failure banks nothing, and nothing spills to other skills. Banked LP are resolved on the next long rest (sleep, or six hours or more of rest). One improvement roll costs ceil(level / 15) LP; roll 1d100, and at least 51 and at least the current level raises the skill by 1d6+1 (at most 100). The rolls stop at the first success, at most one success per skill per night, and then the skill's LP are gone, success or not. From level 50 the character must also reflect on the skill (think it over, practise or study it deliberately, or train with a trainer) before a rest resolves it; until then its LP stay banked.

Physical skills (melee combat, ranged combat, unarmed combat, dodge, climbing, lockpicking) improve right away instead: at the end of the turn of the failure, with the same LP cost, roll and reflection rule. They also improve at most once between two long rests: once one has improved, its LP are dropped until the character has slept. A failed roll spends its LP; LP too few for a roll wait for the next failures, and the long rest clears what is left.

| Level | LP per roll | Chance per roll |
|-------|-------------|-----------------|
| 0-15 | 1 | 50% |
| 16-30 | 2 | 50% |
| 31-45 | 3 | 50% |
| 46-60 | 4 (+ reflection from 50) | 50% to 41% |
| 61-75 | 5 (+ reflection) | 40% to 26% |
| 76-90 | 6 (+ reflection) | 25% to 11% |
| 91-100 | 7 (+ reflection) | 10% to 1% |

### Trainer Bonuses
- Trainers must have skill level ≥25 above student
- A training session is one free attempt (no LP) with +25 to the roll (the roll + 25 must reach 51 and the level)
- Skills stop at 100. Past 75, a trainer's bonus helps most

---

## Design Rationale

### Why Domains?
Skills don't exist in isolation. A master swordsman has developed body awareness, timing, and spatial reasoning that transfers to other physical disciplines. Domains capture this reality.

### Why Floors Instead of Bonuses?
Floors represent baseline competence, not enhancement. A master fighter doesn't get +30 to unarmed — they can't be *worse* than level 30 at unarmed. This distinction matters narratively.

### Why Learn Only From Failure, and Mostly Overnight?
You learn where you fall short, not where you already succeed, and practice sinks in while you sleep. The body is the exception: a missed handhold or a parry that came too late teaches on the spot. The 10,000-hour research shows diminishing returns at high levels: a novice improves quickly, a master grinds for marginal gains. Each level needs more failures in a day before a roll is even possible, a night gives at most one gain, and from level 50 you must also reflect on what you have learned.

### Why Trainers?
Beyond Expert level, self-study plateaus. Real masters seek other masters. A trainer's +25 matters most where attempts mostly fail, and near level 100 little else works. This creates natural quest hooks and emphasizes that true mastery is rare.
