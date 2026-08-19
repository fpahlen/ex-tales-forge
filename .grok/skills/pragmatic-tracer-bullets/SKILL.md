---
name: pragmatic-tracer-bullets
description: Prefer thin end-to-end tracer bullets over speculative full designs when building features or exploring solutions. Activate on new features architecture spikes prototyping or any work that risks big upfront design.
---

# Pragmatic Tracer Bullets

## Overview

Tracer bullets are thin working paths through the entire system that produce real feedback early. They are not prototypes to throw away and not complete features. They find the target by showing what actually works.

## Instructions

- When starting new work prefer a minimal end-to-end slice that touches every layer (input to output) over completing one layer at a time
- Make the tracer actually work and demonstrate the critical path even if many details are stubs or simplified
- Use the tracer to gather real feedback and adjust direction before thickening the implementation
- Avoid big speculative architectures that look complete on paper but have never been exercised end-to-end
- After the tracer works thicken it incrementally while keeping the path green
- Treat the tracer as living code that evolves into the real solution rather than disposable scaffolding
- If requirements are unclear fire a tracer first to make the unknowns visible

## Key Test

Does this produce a working path from one end of the system to the other right now If not it is not yet a tracer bullet.