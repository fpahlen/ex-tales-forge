# Lists dependency compile warnings in the job summary (CI "Dependency
# warnings"). Plain `elixir`, no deps or compile needed:
#
#   elixir .github/scripts/dep_warnings.exs deps-compile.log .github/dep-warnings-known.txt
#
# The logic is in TalesForge.DepWarnings (lib/), where Credo, Dialyzer and the
# tests cover it.
root = Path.expand("../..", __DIR__)
Code.require_file("lib/ex_tales_forge/dep_warnings.ex", root)
TalesForge.DepWarnings.main(System.argv())
