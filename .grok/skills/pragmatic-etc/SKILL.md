---
name: pragmatic-etc
description: Enforce Easy to Change (ETC) as the primary measure of design quality when writing reviewing or refactoring any code architecture APIs modules or data structures. Activate on design decisions generation of new components or suggestions that affect maintainability.
---

# Pragmatic ETC

## Overview

A thing is well designed if it is easy to change. This is the single most important design principle from The Pragmatic Programmer. Every decision must be judged by how it affects future change.

## Instructions

- Before proposing or accepting any design ask Does this make the system easier or harder to change later
- Prefer solutions that localize the impact of change to a single place
- Reject or rewrite any suggestion that creates irreversible decisions tight coupling across modules or duplicated knowledge
- When generating structure explicitly list the change scenarios the design supports
- Favor composition small focused units and clear boundaries over inheritance deep hierarchies or global state
- If a change would be painful stop and redesign for reversibility and orthogonality first
- Treat every generated artifact as temporary until it has proven easy to evolve

## Key Test

If you cannot describe how a future requirement would be implemented with minimal disruption the design fails ETC.