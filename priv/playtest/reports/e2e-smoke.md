# E2E Smoke Test Report

**Date:** 2026-07-03  
**Branch:** `feature/grok-fast-llm`  
**Model:** `grok-4.20-0309-non-reasoning`  
**Overall:** PASS (all turns < 3s)

## Preflight

| Check | Result |
|-------|--------|
| `.env` | ok |
| PostgreSQL | ok |
| `XAI_API_KEY` | ok |
| LLM provider | `xai` |
| Server | ok |

## Scenario: tavern smoke (3 turns, 3000ms budget)

| Step | Action | Status | Latency | Tier 1 |
|------|--------|--------|---------|--------|
| 1 | look around the tavern | PASS | 2510ms | heuristic (2ms) |
| 2 | I ask Marta what the chalk marks mean | PASS | 2512ms | heuristic (0ms) |
| 3 | I head outside to Crossroads Square | PASS | 2009ms | heuristic (0ms) |

Tier 2 GM calls used `grok-4.20-0309-non-reasoning` with `max_tokens=700`. Typical Tier 2 duration ~2s.

## Changes from prior run (grok-4.3)

| Metric | Before | After |
|--------|--------|-------|
| Step 1 latency | 6024ms | 2510ms |
| Step 2 latency | 8034ms | 2512ms |
| Step 3 latency | 5020ms | 2009ms |
| Tier 1 | LLM (~3-4s) | Heuristic (~0-2ms) |
| Ollama retry noise | ~7s | None |

## Warnings

None in this run.

## How to reproduce

```bash
mix phx.server   # terminal 1
mix e2e.smoke    # terminal 2
```