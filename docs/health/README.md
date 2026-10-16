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
branch): the baseline may only shrink. Removing entries and lowering
ceilings pass; adding an entry or raising a ceiling fails.

After paying debt down, run `mix health.check --write` and commit the
smaller baseline. Refactoring the existing debt is separate work.

`YYYY-MM-DD.md` files are the weekly snapshots (`mix health.snapshot`, opened
as a PR by `.github/workflows/health-snapshot.yml` every Monday 06:00 UTC).

`lib/ex_tales_forge -> ExTalesForgeWeb` is measured with xref (real compile, export and
runtime references), not grep: module names in docs and strings do not count.
