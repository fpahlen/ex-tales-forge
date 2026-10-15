# Truth Tag Reference Guide

This document defines the Three Truths Framework conventions used across Merovingia documentation. These HTML comment tags enable the AI Game Master to respect canon while allowing creative interpretation during gameplay.

> **Full Framework:** See `docs/adventure-design/ai-constitution.md` for complete AI Constitution details.

---

## Overview

Truth tags are invisible HTML comments embedded in documentation. They tell the AI GM:
- What facts must never be contradicted
- What mysteries should remain ambiguous
- What opinions can be challenged

---

## The Three Truth Types

### 1. ABSOLUTE TRUTH

**Definition:** Immutable facts that must never be contradicted.

**Syntax:**
```markdown
<!-- TRUTH: ABSOLUTE -->
```

**Use for:**
- Geographic facts (regions, capitals, terrain)
- Ruler names and titles
- Physical descriptions and appearances
- Quick Reference tables
- Family trees and bloodlines
- Guild organizational structures
- Established alliances and tensions

**Example (from Aquilon):**
```markdown
<!-- TRUTH: ABSOLUTE -->
| Attribute | Value |
|-----------|-------|
| **Region** | Northern coastal plains |
| **Ruler** | Baroness Elara Thorne |
| **Capital** | Port-Vent |
```

**AI Behavior:** Reference consistently. Never contradict. No creative interpretation allowed.

---

### 2. CONTESTED TRUTH

**Definition:** Information that is disputed, mysterious, or hidden within the world.

#### Eternal Contested (Never Resolved)

**Syntax:**
```markdown
<!-- TRUTH: CONTESTED | resolution: eternal -->
```

**Use for:** Mysteries where ambiguity IS the point. No hidden answer exists.

**Example (from Miners Guild):**
```markdown
<!-- TRUTH: CONTESTED | resolution: eternal -->
Guild records mention a "Master Delve" abandoned centuries ago...
something was found that caused the Guild to seal the tunnels forever.
<!-- Note: What was found is intentionally unknowable -->
```

**AI Behavior:** Present multiple perspectives. Never declare a winner. The mystery itself is sacred.

#### Discoverable Contested (Can Be Uncovered)

**Syntax:**
```markdown
<!-- TRUTH: CONTESTED | resolution: discoverable -->
<!-- HIDDEN: [The actual truth] -->
```

**Use for:** Secrets players can learn through investigation, persuasion, or events.

**Example (from Beaumont Family):**
```markdown
<!-- TRUTH: CONTESTED | resolution: discoverable -->
<!-- HIDDEN: Marguerite is half-elven, daughter of a Sylvaine noble -->
Lady Marguerite's exact heritage has always been a subject of whispered speculation.
```

**AI Behavior:** Drop hints. Allow investigation to succeed. Reveal truth when earned.

---

### 3. PERSPECTIVE TRUTH

**Definition:** Opinions, beliefs, and interpretations held by specific characters or groups.

**Syntax:**
```markdown
<!-- TRUTH: PERSPECTIVE | holder: [Character or Group Name] -->
```

**Use for:**
- Personality descriptions
- One NPC's opinion of another
- Likes and dislikes
- Strategic assessments
- Rumors and whispered beliefs

**Example (from Lumière):**
```markdown
<!-- TRUTH: PERSPECTIVE | holder: Court observers -->
Baron Alain de Lumière presents himself as:
- Idealistic and scholarly
- Devoted to the light
- Perhaps too trusting of those who share his faith
```

**Example (from Miners Guild - Ambassador views):**
```markdown
<!-- TRUTH: PERSPECTIVE | holder: Master Dolgrim Ironvow -->
**Views on Merovingia's Rulers:**
- **King Clovis IV:** "A fair ruler, as humans go..."
```

**AI Behavior:** Present as character viewpoint. Allow disagreement. Other characters may see things differently.

---

## What NOT to Tag

### Plot Hooks
Plot hooks are GM tools, not canonical facts. They represent *potential* stories, not established truth.

```markdown
<!-- Note: Plot hooks are GM tools, not canonical truths -->
## Plot Hooks
- The Stolen Shipment...
```

### Placeholders
Sections marked "to be expanded" or similar are not yet canonical.

### Implementation Notes
Meta-commentary for documentation authors should not be tagged as truth.

---

## Truth Hierarchy

When truths conflict, resolve using this priority:

1. **ABSOLUTE** — Always wins
2. **Player Timeline** — What happened in the player's game
3. **CONTESTED** — Mysteries and secrets
4. **PERSPECTIVE** — Character opinions (can be wrong)

---

## Quick Reference Table

| Truth Type | Tag Syntax | AI Must Preserve | AI Can Interpret |
|------------|------------|------------------|------------------|
| ABSOLUTE | `<!-- TRUTH: ABSOLUTE -->` | Everything | Nothing |
| CONTESTED (eternal) | `<!-- TRUTH: CONTESTED \| resolution: eternal -->` | The mystery itself | How NPCs discuss it |
| CONTESTED (discoverable) | `<!-- TRUTH: CONTESTED \| resolution: discoverable -->` | The hidden truth | Clues and hints |
| PERSPECTIVE | `<!-- TRUTH: PERSPECTIVE \| holder: X -->` | That X believes this | How others react |

---

## Tagging Patterns by Document Type

### Barony Files

| Section | Truth Type | Holder (if PERSPECTIVE) |
|---------|------------|-------------------------|
| Quick Reference table | ABSOLUTE | — |
| Atmosphere | PERSPECTIVE | Visitors |
| Resources | ABSOLUTE | — |
| Geography | ABSOLUTE | — |
| Capital description | ABSOLUTE | — |
| Ruler facts (name, race, spouse) | ABSOLUTE | — |
| Ruler personality | PERSPECTIVE | Court observers |
| Strengths/Weaknesses | PERSPECTIVE | Strategic observers |
| Alliances/Tensions list | ABSOLUTE | — |

### Family Files

| Section | Truth Type | Notes |
|---------|------------|-------|
| Family tree/ages/residences | ABSOLUTE | — |
| Personality sections | PERSPECTIVE | Holder varies by observer |
| Hidden heritage/secrets | CONTESTED (discoverable) | Include HIDDEN comment |
| Unresolved historical questions | CONTESTED (eternal) | When ambiguity is intentional |

### Guild Files

| Section | Truth Type | Notes |
|---------|------------|-------|
| Organization/Ranks | ABSOLUTE | — |
| Ambassador appearance | ABSOLUTE | — |
| Ambassador personality | PERSPECTIVE | holder: Guild members or Court |
| Ambassador's views on others | PERSPECTIVE | holder: Ambassador name |
| Guild secrets | CONTESTED | eternal or discoverable based on intent |

---

## Tagged Documentation

All 17 Merovingia files use this framework:

**Core:**
- `modules/merovingia/README.md`
- `modules/merovingia/king-clovis-iv.md`

**Baronies (12 files):**
- `modules/merovingia/baronies/aquilon.md`
- `modules/merovingia/baronies/arborin.md`
- `modules/merovingia/baronies/ferroigne.md`
- `modules/merovingia/baronies/glaciere.md`
- `modules/merovingia/baronies/lumiere.md`
- `modules/merovingia/baronies/marecage.md`
- `modules/merovingia/baronies/montfort.md`
- `modules/merovingia/baronies/pyremont.md`
- `modules/merovingia/baronies/rochedur.md`
- `modules/merovingia/baronies/sylvaine.md`
- `modules/merovingia/baronies/vallombre.md`
- `modules/merovingia/baronies/ventdor.md`

**Guilds:**
- `modules/merovingia/guilds/README.md`
- `modules/merovingia/guilds/miners-guild.md`
- `modules/merovingia/guilds/thieves-guild.md`
- `modules/merovingia/guilds/ancient-aurelias.md`

**Families:**
- `modules/merovingia/families/beaumont.md`

---

## Adding New Documentation

When creating new Merovingia documentation:

1. **Start with ABSOLUTE facts** — Names, locations, organizational structure
2. **Add PERSPECTIVE for opinions** — Personalities, strategic assessments, likes/dislikes
3. **Use CONTESTED sparingly** — Only for genuine mysteries or secrets
4. **Leave Plot Hooks untagged** — They're tools, not canon
5. **Follow the patterns** — Match the structure of existing files of the same type
