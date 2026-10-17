# Code health ratchet

`baseline.json` holds the code health debt as of the day it was written:

- `cycles`: every `mix xref graph --format cycles` cycle (`all`) and every
  `--label compile-connected` cycle, with its size and member files.
- `web_references`: each `lib/ex_tales_forge/` file that references a
  `lib/ex_tales_forge_web/` file in the xref graph, and the files it references.
- `complex_functions`: each function over the Credo limits (cyclomatic
  complexity 9, ABC size 30) with its scores. A score is that function's
  ceiling; a missing score means the limit is its ceiling.

`mix health.check` (CI, and `mix precommit`) fails when the code is worse
than the baseline: more cycles, a cycle that is new or bigger than every
baseline cycle, a new domain -> web reference, a new function over a limit,
or a score above its ceiling. In CI it also runs with `--base` (the PR's base
branch; on a push to main, the merge's first parent): the baseline may only shrink. Removing entries and lowering
ceilings pass; adding an entry or raising a ceiling fails.

After paying debt down, run `mix health.check --write` and commit the
smaller baseline. Refactoring the existing debt is separate work.

## History

![Code health per merge to main](trend.svg)

`history.csv` has one row per merge to main since #324 (the ratchet): date,
PR, xref cycles, largest cycle, compile-connected cycles (count and largest),
domain -> web references and functions over the complexity limits. Lower is
better. `mix health.snapshot` measures HEAD, puts its row in the CSV and
redraws `trend.svg`: one stacked bar per merge (xref cycles + complex
functions + domain -> web refs, total on top). After each merge to main,
`.github/workflows/health-snapshot.yml` runs it and pushes the row to the
branch `health-history`, with one open PR for it; merging that PR adds the
rows to main. GitHub holds every pull_request run on a PR that
github-actions[bot] opened until a human approves it, so CI skips that PR's
pull_request runs (it changes only the two history files) and the snapshot
workflow dispatches CI on the branch instead. GitHub does not count a
dispatched run's own checks on a PR, so that run sets commit statuses
named Test and Dialyzer on the branch head with its results (job "Report
dispatched checks"): the required checks pass with no approval. The first rows are the merges that changed `baseline.json`
(#324, #325, #326), measured again at each merge commit.

`lib/ex_tales_forge -> ExTalesForgeWeb` is measured with xref (real compile, export and
runtime references), not grep: module names in docs and strings do not count.
