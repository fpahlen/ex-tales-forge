# The advisories in `mix hex.audit` output as a `mix deps.audit --format json`
# report, for .github/workflows/security-audit.yml. Plain `elixir`, no deps:
#
#   elixir .github/scripts/hex_audit.exs hex-audit.out hex-audit.err
#
# The parsing is in TalesForge.DeployLanes.HexAudit (lib/), where Credo,
# Dialyzer and the tests cover it.
root = Path.expand("../..", __DIR__)
Code.require_file("lib/ex_tales_forge/deploy_lanes/hex_audit.ex", root)
TalesForge.DeployLanes.HexAudit.main(System.argv())
