---
name: pragmatic-dry
description: Enforce the DRY principle by eliminating every duplication of knowledge not just code. Activate whenever generating reviewing or refactoring logic data configuration documentation or tests that risk repeating the same fact in multiple places.
---

# Pragmatic DRY

## Overview

DRY means Don't Repeat Yourself. Every piece of knowledge must have a single unambiguous authoritative representation within a system. Duplication of knowledge is the root of many maintenance problems.

## Instructions

- Never allow the same piece of knowledge (business rule data structure algorithm configuration meaning) to exist in more than one place
- When you see or generate duplicated logic extract it into a single function module constant or configuration source
- Prefer parameterization and abstraction over copy-paste even for small fragments
- Treat documentation comments and tests as knowledge that must also stay in sync with the code they describe
- If a change requires updating multiple locations that is a DRY violation — fix the structure first
- Distinguish intentional repetition for clarity from accidental duplication of knowledge
- When generating new code scan for existing knowledge that can be reused rather than restated

## Key Test

If a single fact changes and you must edit more than one place the system is not DRY.