## Runs

| arm | persona | run | sha | status/stop | turns | session | turn mean | game $ | persona $ | Jev scorer $ |
|---|---|---|---|---|---|---|---|---|---|---|
| off | paul | 2d335582 | f4ea6ad | finished/turn_limit | 10/10 | 4.65 | 4.03 | 0.0980 | 0.0244 | 0.0003 |
| off | paul | 67cf83bc | f4ea6ad | finished/turn_limit | 10/10 | 4.78 | 4.20 | 0.0804 | 0.0280 | 0.0003 |
| off | lotta | 45b8086e | f4ea6ad | finished/turn_limit | 10/10 | 4.17 | 3.70 | 0.1435 | 0.0249 | 0.0002 |
| off | lotta | 08240e4b | f4ea6ad | finished/turn_limit | 10/10 | 4.04 | 3.68 | 0.0772 | 0.0222 | 0.0002 |
| off | lars | f62ada63 | f4ea6ad | stopped/timeout | 4/10 | 3.68 | 3.54 | 0.0453 | 0.0066 | 0.0001 |
| off | lars | ada4689d | f4ea6ad | finished/turn_limit | 10/10 | 3.61 | 3.40 | 0.0880 | 0.0325 | 0.0002 |
| off | lars | a9c4ff90 | f4ea6ad | finished/turn_limit | 10/10 | 3.23 | 3.16 | 0.0894 | 0.0245 | 0.0002 |
| off | ronny | 53d232e9 | f4ea6ad | finished/turn_limit | 10/10 | 4.56 | 4.70 | 0.1333 | 0.0231 | 0.0002 |
| off | ronny | 677d4033 | f4ea6ad | finished/turn_limit | 10/10 | 4.47 | 4.23 | 0.0676 | 0.0205 | 0.0002 |
| off | hawk | 2d705e66 | f4ea6ad | finished/turn_limit | 12/12 | 4.80 | 2.52 | 0.1184 | 0.0292 | 0.0003 |
| off | hawk | 91d02c47 | f4ea6ad | finished/turn_limit | 12/12 | 4.41 | 2.35 | 0.1120 | 0.0268 | 0.0003 |
| on | paul | c8581588 | f4ea6ad | finished/turn_limit | 10/10 | 4.80 | 4.16 | 0.1475 | 0.0673 | 0.0003 |
| on | paul | c0feec58 | f4ea6ad | finished/turn_limit | 10/10 | 4.83 | 4.34 | 0.1464 | 0.0542 | 0.0003 |
| on | lotta | 751e0f86 | f4ea6ad | finished/turn_limit | 10/10 | 3.87 | 3.73 | 0.0856 | 0.0189 | 0.0002 |
| on | lotta | 88aaad40 | f4ea6ad | finished/turn_limit | 10/10 | 4.01 | 3.84 | 0.1012 | 0.0333 | 0.0003 |
| on | lars | fa948c45 | f4ea6ad | stopped/dead | 10/10 | 3.08 | 3.49 | 0.1116 | 0.0569 | 0.0002 |
| on | lars | 5ae43a5e | f4ea6ad | finished/turn_limit | 10/10 | 3.64 | 3.20 | 0.0825 | 0.0289 | 0.0002 |
| on | ronny | 60333425 | f4ea6ad | failed/error | 8/10 | – | – | 0.0969 | 0.0205 | 0.0000 |
| on | ronny | cc0a7d36 | f4ea6ad | finished/turn_limit | 10/10 | 4.72 | 4.63 | 0.1088 | 0.0395 | 0.0002 |
| on | ronny | 765d64fa | f4ea6ad | finished/turn_limit | 10/10 | 2.75 | 3.49 | 0.0895 | 0.0321 | 0.0002 |
| on | hawk | a2a3a008 | f4ea6ad | failed/error | 0/12 | – | – | 0.0115 | 0.0000 | 0.0000 |
| on | hawk | 4eb24957 | f4ea6ad | finished/turn_limit | 12/12 | 4.69 | 2.40 | 0.1331 | 0.0487 | 0.0003 |
| on | hawk | 82819029 | f4ea6ad | finished/turn_limit | 12/12 | 4.83 | 2.51 | 0.1199 | 0.0381 | 0.0003 |

## Jev per persona (finished runs; 95% t-CI over runs)

| persona | off session (n) | on session (n) | off turn mean | on turn mean |
|---|---|---|---|---|
| paul | 4.71 [3.89, 5.54] (2) | 4.81 [4.62, 5.01] (2) | 4.12 [3.04, 5.20] | 4.25 [3.16, 5.34] |
| lotta | 4.11 [3.28, 4.93] (2) | 3.94 [3.05, 4.83] (2) | 3.69 [3.52, 3.85] | 3.78 [3.05, 4.52] |
| lars | 3.42 [1.01, 5.83] (2) | 3.36 [-0.20, 6.92] (2) | 3.28 [1.78, 4.78] | 3.35 [1.53, 5.17] |
| ronny | 4.51 [3.94, 5.09] (2) | 3.73 [-8.78, 16.25] (2) | 4.46 [1.48, 7.45] | 4.06 [-3.16, 11.29] |
| hawk | 4.61 [2.13, 7.08] (2) | 4.76 [3.87, 5.65] (2) | 2.44 [1.31, 3.56] | 2.45 [1.72, 3.18] |
| all but ronny | 4.21 [3.74, 4.69] (8) | 4.22 [3.66, 4.78] (8) | 3.38 [2.82, 3.94] | 3.46 [2.86, 4.06] |

## Jev confidence-weighted turn reading (sum(score*conf)/sum(conf)) and unsure share (turn conf < 0.7)

| persona | off weighted | on weighted | off unsure | on unsure |
|---|---|---|---|---|
| paul | 4.18 [2.69, 5.67] | 4.26 [3.45, 5.07] | 75% | 55% |
| lotta | 3.66 [3.22, 4.11] | 3.79 [3.11, 4.47] | 95% | 85% |
| lars | 3.35 [1.62, 5.09] | 3.47 [1.71, 5.24] | 80% | 85% |
| ronny | 4.72 [3.89, 5.54] | 4.27 [-1.69, 10.24] | 40% | 65% |
| hawk | 2.39 [1.36, 3.42] | 2.40 [0.88, 3.92] | 62% | 38% |
| all but ronny | 3.40 [2.81, 3.99] | 3.48 [2.86, 4.10] | 78% | 66% |

On − off, session, persona-centred, no Ronny: +0.01 (bootstrap 95% CI -0.15 to +0.16; n=8/8)

On − off, turn_mean, persona-centred, no Ronny: +0.08 (bootstrap 95% CI -0.01 to +0.17; n=8/8)

On − off, turn_wmean, persona-centred, no Ronny: +0.08 (bootstrap 95% CI -0.02 to +0.18; n=8/8)

## Safety read and GM input (turn.intent meta)

**off**: turns 108; turns with LLM intent call 4; with a safety read 4; GM got quote 4, summary 104, no meta 0
  clarification requests (turn.intent without a decision): 5 over 11 runs
  labels {'benign': 4}; reasons {'no_intent_call_heuristic': 101, 'benign': 4, 'no_intent_call_clarification': 3}
  non-Ronny safety reads 4; not quoted 0 (0.0%, Wilson 95% 0.0–49.0%)
  Ronny safety reads 0; not quoted 0; labels {}
  confidence: min 0.95, p10 0.95, median 0.95; < 0.90: 0
**on**: turns 112; turns with LLM intent call 85; with a safety read 85; GM got quote 85, summary 27, no meta 0
  clarification requests (turn.intent without a decision): 77 over 11 runs
  labels {'benign': 85}; reasons {'benign': 85, 'no_intent_call_clarification': 25, 'no_intent_call_heuristic': 2}
  non-Ronny safety reads 65; not quoted 0 (0.0%, Wilson 95% 0.0–5.6%)
  Ronny safety reads 20; not quoted 0; labels {'benign': 20}
  confidence: min 0.90, p10 0.90, median 0.95; < 0.90: 0

## Latency per turn (intent step start → turn persisted), seconds

| arm | persona | n | median | p90 | intent step median | GM call median |
|---|---|---|---|---|---|---|
| off | paul | 20 | 5.0 | 6.2 | 0.00 | 4.6 |
| off | lotta | 20 | 5.4 | 6.0 | 0.00 | 4.7 |
| off | lars | 24 | 5.5 | 7.0 | 0.00 | 5.0 |
| off | ronny | 20 | 5.8 | 6.7 | 0.00 | 5.4 |
| off | hawk | 24 | 5.9 | 6.6 | 0.00 | 5.5 |
| off | all | 108 | 5.5 | 6.6 | 0.00 | 5.1 |
| on | paul | 20 | 8.9 | 12.8 | 1.81 | 6.6 |
| on | lotta | 20 | 7.1 | 8.4 | 1.73 | 5.2 |
| on | lars | 20 | 6.4 | 8.2 | 1.74 | 4.5 |
| on | ronny | 28 | 6.3 | 21.0 | 1.42 | 4.3 |
| on | hawk | 24 | 4.2 | 5.2 | 1.12 | 3.0 |
| on | all | 112 | 6.3 | 12.6 | 1.41 | 4.5 |

## Clarification loops (intent call asked the player to pick an option)

| arm | persona | turns | clarification requests | per turn | turns with ≥1 | extra persona calls |
|---|---|---|---|---|---|---|
| off | paul | 20 | 0 | 0.00 | 0 (0%) | 0 |
| off | lotta | 20 | 0 | 0.00 | 0 (0%) | 0 |
| off | lars | 24 | 5 | 0.21 | 4 (17%) | 5 |
| off | ronny | 20 | 0 | 0.00 | 0 (0%) | 0 |
| off | hawk | 24 | 0 | 0.00 | 0 (0%) | 0 |
| off | all | 108 | 5 | 0.05 | 4 (4%) | 5 |
| on | paul | 20 | 29 | 1.45 | 13 (65%) | 29 |
| on | lotta | 20 | 4 | 0.20 | 1 (5%) | 4 |
| on | lars | 20 | 18 | 0.90 | 7 (35%) | 18 |
| on | ronny | 28 | 15 | 0.54 | 10 (36%) | 16 |
| on | hawk | 24 | 11 | 0.46 | 8 (33%) | 12 |
| on | all | 112 | 77 | 0.69 | 39 (35%) | 79 |

## Wall time from the player's first submission to the GM reply (includes clarification rounds and the persona's answers), seconds

| arm | persona | n | median | p90 | max |
|---|---|---|---|---|---|
| off | paul | 20 | 5.0 | 6.2 | 6.5 |
| off | lotta | 20 | 5.4 | 6.0 | 8.1 |
| off | lars | 24 | 5.7 | 9.4 | 12.7 |
| off | ronny | 20 | 5.8 | 6.7 | 9.2 |
| off | hawk | 24 | 5.9 | 6.6 | 7.2 |
| off | all | 108 | 5.6 | 6.8 | 12.7 |
| on | paul | 20 | 14.2 | 33.2 | 106.1 |
| on | lotta | 20 | 7.2 | 9.3 | 16.6 |
| on | lars | 20 | 7.6 | 19.4 | 39.2 |
| on | ronny | 28 | 8.5 | 21.7 | 39.0 |
| on | hawk | 24 | 4.9 | 7.3 | 11.9 |
| on | all | 112 | 7.7 | 19.4 | 106.1 |

off: turns without API errors or clarification: n=104, median 5.5 s, p90 6.6 s

on: turns without API errors or clarification: n=70, median 6.6 s, p90 12.7 s

Median latency on − off: +0.79 s (bootstrap 95% CI +0.39 to +1.39); turn-level, ignores clustering by run.

## Cost per finished run (USD)

| arm | n | game mean [95% CI] | of which LLM intent | persona mean | Jev scorer mean | game per turn |
|---|---|---|---|---|---|---|
| off | 10 | 0.1008 [0.0828, 0.1188] | 0.0021 | 0.0256 | 0.00023 | 0.0097 |
| on | 10 | 0.1126 [0.0955, 0.1297] | 0.0332 | 0.0418 | 0.00023 | 0.0108 |

Totals, all runs incl. stopped: game $2.2875, persona $0.7009, Jev scorer $0.0047

## Engagement proxy: share of the player's content words echoed in the GM reply

| arm | persona | turns | mean overlap | quoted turns overlap | summary turns overlap |
|---|---|---|---|---|---|
| off | paul | 20 | 0.15 | – (0) | 0.15 (20) |
| off | lotta | 20 | 0.23 | 0.25 (2) | 0.23 (18) |
| off | lars | 24 | 0.38 | 0.32 (2) | 0.39 (22) |
| off | ronny | 20 | 0.12 | – (0) | 0.12 (20) |
| off | hawk | 24 | 0.26 | – (0) | 0.26 (24) |
| off | all | 108 | 0.24 | 0.29 (4) | 0.23 (104) |
| on | paul | 20 | 0.29 | 0.24 (11) | 0.35 (9) |
| on | lotta | 20 | 0.39 | 0.39 (19) | 0.25 (1) |
| on | lars | 20 | 0.35 | 0.39 (16) | 0.17 (4) |
| on | ronny | 28 | 0.25 | 0.30 (20) | 0.12 (8) |
| on | hawk | 24 | 0.32 | 0.37 (19) | 0.13 (5) |
| on | all | 112 | 0.31 | 0.35 (85) | 0.21 (27) |
