# Decides the auto merge lane (docs/design-auto-merge.md). Plain `elixir`, no
# deps or compile needed; security-lane.yml runs it from main's checkout:
#
#   elixir .github/scripts/auto_lane.exs pr --base <sha> --head <sha> --pr pr.json --checks checks.json
#   elixir .github/scripts/auto_lane.exs history --prs prs.json   (dry run, prints a table)
#
# The rules are in TalesForge.DeployLanes.Auto and TalesForge.DeployLanes.AutoCLI
# (lib/), where Credo, Dialyzer and the tests cover them.
root = Path.expand("../..", __DIR__)

for file <- ~w(deploy_lanes.ex deploy_lanes/security.ex deploy_lanes/security_cli.ex
               deploy_lanes/auto.ex deploy_lanes/auto_cli.ex) do
  Code.require_file("lib/ex_tales_forge/#{file}", root)
end

File.cd!(root)
TalesForge.DeployLanes.AutoCLI.main(System.argv())
