---
name: pragmatic-test-to-code
description: Treat tests as the first user of the code and design to the tests. Activate when writing features fixing bugs generating implementations or reviewing code that lacks clear test coverage or feedback.
---

# Pragmatic Test to Code

## Overview

Testing is not primarily about finding bugs. A test is the first user of your code. Writing the test first or alongside the code forces better design and provides immediate feedback. Property-based tests further validate assumptions.

## Instructions

- Prefer writing or demanding a test (or property) before or together with the implementation
- Treat every test as the first consumer of the API — if the test is awkward the API is probably wrong
- Design the code so it is easy to test isolate and exercise in isolation
- When assumptions matter use property-based tests to explore the space of inputs rather than a few examples
- Never consider code done until the relevant tests run and pass
- After fixing a bug first write a test that would have caught it then fix the code
- Prefer small focused tests that document intent over large brittle end-to-end suites
- If generation produces code without tests immediately add or request the missing tests

## Key Test

Is there a clear test or property that acts as the first user of this code and would fail if the behavior changed incorrectly If not the feedback loop is incomplete.