# E2E Smoke Test Report

**Date:** 2026-07-03  
**Branch:** `test/local-e2e-smoke`  
**Elixir:** 1.20.2 / OTP 29  
**Overall:** PASS

## Preflight (`mix dev.check`)

| Check | Result |
|-------|--------|
| `.env` | ok |
| PostgreSQL | ok |
| `XAI_API_KEY` | ok (masked) |
| LLM provider | `xai` |
| Server `http://localhost:4000` | ok |

## Scenario: tavern smoke (3 turns)

| Step | Action | Status | Latency | LLM source |
|------|--------|--------|---------|------------|
| 1 | look around the tavern | PASS | 6024ms | api |
| 2 | I ask Marta what the chalk marks mean | PASS | 8034ms | api |
| 3 | I head outside to Crossroads Square | PASS | 5020ms | api |

All narratives were live Grok responses (no `_Mock GM:` marker). Mechanics applied on steps 1–2 (insight failure, persuasion partial success). Step 3 moved character to Crossroads Square.

Session ID: `e7ce873a-d28d-4515-9c40-47b7b3840eff`

Full machine-readable report: [e2e-smoke.json](./e2e-smoke.json)

## Warnings observed

### Ollama connection refused (noise, non-blocking)

During Tier 1 intent extraction, Req retried against Ollama (`connection refused`) before falling through to xAI. This happens when Ollama is not running but the reachability probe or model routing still attempts it.

**Recommendation:** Set `TIER1_MODEL=xai/grok-4.3` in `.env` to skip Ollama probes and reduce ~7s of retry latency per intent call.

### No errors

- No `turn processor failed` or `turn_failed` events
- No compile warnings
- `mix test` — 9 passed

## Bug fixed during this run

**Intent validation crash:** Tier 1 LLM sometimes omitted `parameters.skill` for observe/speak actions, raising `ArgumentError: primary action missing required skill`. Fixed in `lib/ex_tales_forge/game/intent.ex` by retrying the LLM call and inferring skill from player text as fallback (aligned with text-forge heuristics).

## How to reproduce

```bash
# Terminal 1
mix phx.server

# Terminal 2
mix e2e.smoke
```