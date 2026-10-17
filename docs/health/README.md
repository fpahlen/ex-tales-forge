# Code health ratchet

The ratchet measures only code we write, which is `lib/`. It never
measures `deps/` or generated framework code, and framework-dictated shapes
are exempt: `@impl` callbacks are not counted for parameters, and the `~p`
edges into the router are not counted as cycles (#338).

`baseline.json` holds the code health debt as of the day it was written:

- `cycles`: every `mix xref graph --format cycles` cycle (`all`, without
  `lib/ex_tales_forge_web/router.ex`) and every `--label compile-connected`
  cycle (with the router), with its size and member files. Every LiveView
  links to the router with `~p` and the router names every LiveView, so
  with the router every page would be in a cycle with every other.
- `web_references`: each `lib/ex_tales_forge/` file that references a
  `lib/ex_tales_forge_web/` file in the xref graph, and the files it references.
- `complex_functions`: each function over the Credo limits (cyclomatic
  complexity 9, ABC size 30) with its scores. A score is that function's
  ceiling; a missing score means the limit is its ceiling.
- `live_view_references`: each LiveView (`use TalesForgeWeb, :live_view` or
  `:public_live_view`) that references another LiveView in the xref graph,
  and the LiveViews it references (none on 2026-10-17). The router no
  longer shows pages that render each other; this list does.
- `counting`: the version of how the numbers are counted (2 since the
  router left the `all` cycles).
- `wide_functions`: each `def`/`defp` head with 4 or more parameters
  (counted from the AST, `@impl` callbacks skipped), with its file and count.

`mix health.check` (CI, and `mix precommit`) fails when the code is worse
than the baseline: more cycles, a cycle that is new or bigger than every
baseline cycle, a new domain -> web reference, a new LiveView -> LiveView reference, a new
function over a limit,
a score above its ceiling, a new function with 4+ parameters, or a baseline
one that gained parameters. In CI it also runs with `--base` (the PR's base
branch; on a push to main, the merge's first parent): the baseline may only shrink. Removing entries and lowering
ceilings pass; adding an entry or raising a ceiling fails.

After paying debt down, run `mix health.check --write` and commit the
smaller baseline. Refactoring the existing debt is separate work.

## History

![Code health per merge to main](trend.svg)

`history.csv` has one row per merge to main since #324 (the ratchet): date,
PR, xref cycles, largest cycle, compile-connected cycles (count and largest),
domain -> web references, functions over the complexity limits,
functions with 4+ parameters and `counting` (blank is 1). A bar where
`counting` changes is marked "counting changed": the router left the `all`
cycles at that merge (65 → 30 on the same code), not a refactor. Lower is
better. `mix health.snapshot` measures HEAD, puts its row in the CSV and
redraws `trend.svg`: one stacked bar per merge (xref cycles + complex
functions + domain -> web refs + functions with 4+ parameters, total on
top). After each merge to main,
`.github/workflows/health-snapshot.yml` runs it and pushes the row to the
branch `health-history`, with one open PR for it; merging that PR adds the
rows to main. GitHub holds every pull_request run on a PR that
github-actions[bot] opened until a human approves it, so CI skips that PR's
pull_request runs (it changes only the two history files) and the snapshot
workflow dispatches CI on the branch instead. GitHub does not count a
dispatched run's own checks on a PR, so that run sets commit statuses
named Test and Dialyzer on the branch head with its results (job "Report
dispatched checks"): the required checks pass with no approval. The first rows are the merges that changed `baseline.json`
(#324, #325, #326), measured again at each merge commit. The 4+ parameter
counts up to #334 were measured on each merge commit's `lib/` too. When
main changes the history files, the snapshot workflow merges main with
main's side (`-X theirs`) and passes the branch's old file to
`mix health.snapshot --keep`, so no row is lost.

`lib/ex_tales_forge -> ExTalesForgeWeb` is measured with xref (real compile, export and
runtime references), not grep: module names in docs and strings do not count.
