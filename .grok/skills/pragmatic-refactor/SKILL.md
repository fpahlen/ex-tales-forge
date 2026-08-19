---
name: pragmatic-refactor
description: Refactor early and often to keep the code easy to change. Activate after generating or modifying non-trivial code when structure can be improved while tests still pass or when technical debt becomes visible.
---

# Pragmatic Refactor

## Overview

Refactoring is continuous hygiene not a later phase. Small deliberate improvements while the tests remain green keep the system easy to change and prevent entropy from accumulating.

## Instructions

- After any non-trivial generation or change look for structural improvements that can be made safely
- Refactor in small verified steps keeping the tests green after each change
- Prefer improving names extracting methods removing duplication and clarifying intent over large rewrites
- Never leave known structural problems just because the code currently works
- Refactor before adding the next feature when the current structure would make that feature harder
- Treat refactoring as part of the normal work not a separate cleanup task
- If a change feels risky because of poor structure stop and improve the structure first

## Key Test

Is the code easier to understand and change after this step than before and do the tests still pass.