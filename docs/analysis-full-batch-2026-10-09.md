# Analysis: full batch 2026-10-09

Series `full-2026-10-09` on tales-forge-playtest (main `dd5dc7e`, playtest v75, `INTENT_JEV=on`), compared with the previous full batch `post-rework-2026-10-08`. Five personas, 5 runs each, 10 turns (Hawk 12). Finished 2026-10-09 12:28.

Runs used: 25 new (24 hit the turn limit, 1 Lars run ended with the character dead) and 23 previous. Five new sessions failed with errors and were rerun (Ronny 1, Paul 3, Hawk 1); three previous sessions timed out. Those are excluded. Each persona is scored with the same Jev rubric version in both series.

## Jev scores

| Persona | Series | n | Session score | Weighted turn score (headline) | Unsure turns |
|---|---|---|---|---|---|
| Paul | prev | 5 | 4.86 | 4.27 | 48% |
| Paul | new | 5 | 4.96 | 4.54 | 24% |
| Lotta | prev | 5 | 3.71 | 3.31 | 30% |
| Lotta | new | 5 | 4.30 | 3.41 | 66% |
| Lars | prev | 4 | 4.05 | 3.76 | 40% |
| Lars | new | 5 | 3.92 | 3.64 | 66% |
| Ronny | prev | 4 | 4.09 | 4.55 | 70% |
| Ronny | new | 5 | 4.30 | 4.67 | 46% |
| Hawk | prev | 5 | 3.34 | 2.12 | 27% |
| Hawk | new | 5 | 3.23 | 2.20 | 38% |
| All | prev | 23 | 4.01 | 3.55 | 41% |
| All | new | 25 | 4.14 | 3.69 | 48% |

Change, new minus previous, with bootstrap 95% confidence intervals:

| Persona | Session score Δ | Weighted turn Δ |
|---|---|---|
| Paul | +0.10 (+0.05 to +0.15) | +0.27 (+0.17 to +0.37) |
| Lotta | +0.59 (−0.07 to +1.17) | +0.10 (−0.19 to +0.34) |
| Lars | −0.13 (−0.32 to +0.10) | −0.12 (−0.38 to +0.18) |
| Ronny | +0.22 (−0.37 to +0.80) | +0.12 (−0.08 to +0.30) |
| Hawk | −0.11 (−1.09 to +0.94) | +0.08 (−0.26 to +0.43) |
| Persona-balanced | +0.13 (−0.13 to +0.40) | +0.09 (−0.02 to +0.20) |

Only Paul's gain is clearly real. The rest are within noise. Hawk is now very spread out (session sd 1.21): two runs near 4.5, three between 2.1 and 2.6. Lotta and Lars were scored "unsure" much more often (66%), so their headline numbers are less reliable.

## Cost (USD)

| | Previous (23 runs) | New (25 runs) |
|---|---|---|
| Game | $2.005 (intent $0.028) | $2.337 (intent $0.034) |
| Persona bot | $0.613 | $0.646 |
| Jev scorer | $0.005 | $0.007 |
| Total | $2.62 | $2.99 |
| Game per run | $0.087 | $0.094 |
| Game per turn | $0.0084 | $0.0090 |

The game got about 7% dearer per turn. Hawk's game cost rose most ($0.095 to $0.110 per run).

## Intent

Jev read intent on all 260 turns, all status ok: median 232 ms, p95 275 ms, max 374 ms, well inside the 1.5 s deadline. There were no LLM intent fallbacks. Decisions were 246 "act" and 14 "best guess", with no clarifying questions (previous batch: 5 asks in 240 turns). Time from intent to saved turn: median 6.3 s, p95 10.5 s (previous 5.9 s and 9.6 s), mostly GM LLM time (median 5.6 s).

## Product changes (#86, #87, #88)

- **Gestures (#87):** more variety. "Shifts his weight" fell from 48 mentions to 20, and "leans a hip" from 14 to 5, while "tilts her head" (9 to 14) and "on the house" (7 to 11) appear in more runs.
- **Forge and Maude hooks (#88):** the GM mentions the forge or smith in 17/25 runs (was 9/23) and Maude or the cottage in 14/25 (was 4/23). Players picked them up in 4/25 (forge) and 5/25 (Maude) runs, up from 1/23 each.
- **Tinjacks (#86):** Rusk or Cobb were named in 20/25 runs (was 16/23), first named at a median of turn 6. For Hawk they now show up in 4 of 5 runs (turns 4 to 10, was 2/5).
- **Hawk's fights:** still only 1 of 5 runs had a combat roll (turn 9). That run scored 4.52, against 2.91 average without a fight. Getting Hawk into a fight remains the main lever for his score.

## Growth and dice rolls

Rolls per run jumped from 0.70 to 4.72, improvement attempts from 20 to 153 and levels gained from 13 to 112. Scene changes rose from 1.78 to 2.48 per run.

| Persona | Rolls/run prev | Rolls/run new | Attempts / gained new |
|---|---|---|---|
| Paul | 0.6 | 8.4 | 69 / 39 |
| Ronny | 0.0 | 6.2 | 35 / 29 |
| Lars | 2.0 | 4.6 | 28 / 26 |
| Hawk | 0.4 | 2.8 | 15 / 13 |
| Lotta | 0.6 | 1.6 | 6 / 5 |

Paul now rolls on most of his 10 turns. That fits his practice-heavy play, and his scores went up, but it is worth checking whether every-turn intent (`INTENT_JEV=on`) makes routine actions count as skill attempts too easily, and whether 39 levels in five 10-turn sessions is faster growth than we want.

Raw output: `/workspace/full-batch/analysis.txt` on the box.
