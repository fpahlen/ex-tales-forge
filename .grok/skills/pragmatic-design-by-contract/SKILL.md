---
name: pragmatic-design-by-contract
description: Design with explicit contracts preconditions postconditions and invariants and crash early when they are violated. Activate when writing functions APIs modules or any code that has clear expectations about inputs outputs or state.
---

# Pragmatic Design by Contract

## Overview

Design by Contract makes the obligations of callers and callees explicit. Crash early when a contract is broken so problems surface close to their source instead of corrupting state further downstream.

## Instructions

- State clear preconditions that must be true before a unit of code runs
- State clear postconditions that the unit guarantees if the preconditions held
- Prefer failing fast and loudly over continuing with invalid state
- Use assertions or explicit checks for conditions that must never be false
- Make contracts part of the public interface so callers know their obligations
- When generating code include the contract as comments assertions or type-level constraints
- Avoid silent recovery or default values that hide contract violations
- Treat violated contracts as programming errors not runtime conditions to paper over

## Key Test

If the contract is broken does the code fail immediately and obviously near the violation or does the problem travel further before becoming visible.