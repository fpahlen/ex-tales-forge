defmodule TalesForge.DeployLanes.HexAuditTest do
  use ExUnit.Case, async: true

  alias TalesForge.DeployLanes.HexAudit
  alias TalesForge.DeployLanes.HexAudit.Advisory

  doctest TalesForge.DeployLanes.HexAudit

  @dir Path.expand("../fixtures/security_lane", __DIR__)

  # The `mix hex.audit` output of CI run 40395854829 (main, 2026-10-26), with
  # "Found packages with security advisories" (stderr) mixed into the report.
  defp jose_output, do: File.read!(Path.join(@dir, "hex_audit_advisories.out"))

  test "advisories/1 reads every advisory of the jose report (#585), stderr line and all" do
    advisories = HexAudit.advisories(jose_output())

    assert length(advisories) == 8
    assert Enum.map(advisories, & &1.id) == for(n <- 65_625..65_632, do: "EEF-CVE-2026-#{n}")

    assert hd(advisories) == %Advisory{
             package: "jose",
             version: "1.11.12",
             id: "EEF-CVE-2026-65625",
             severity: "medium",
             title:
               "Attacker-controlled AES-GCM authentication tag length allows tag forgery in jose",
             url: "https://osv.dev/vulnerability/EEF-CVE-2026-65625"
           }

    assert Enum.find(advisories, &(&1.id == "EEF-CVE-2026-65629")).severity == "high"
  end

  test "advisories/1: a clean audit or a retired-packages report has no advisories" do
    assert HexAudit.advisories("No retired packages found\n") == []

    retired = """
    Dependency  Version  Retirement reason
    plug        1.14.0   (security) Use 1.14.1
    Found retired packages
    """

    assert HexAudit.advisories(retired) == []
  end

  test "report/1 has the `mix deps.audit --format json` shape the workflow reads" do
    [first | _] = jose_output() |> HexAudit.advisories() |> Enum.take(1)

    assert HexAudit.report([first]) == %{
             "vulnerabilities" => [
               %{
                 "dependency" => %{"package" => "jose", "version" => "1.11.12"},
                 "advisory" => %{
                   "id" => "EEF-CVE-2026-65625",
                   "severity" => "medium",
                   "title" =>
                     "Attacker-controlled AES-GCM authentication tag length allows tag forgery in jose",
                   "url" => "https://osv.dev/vulnerability/EEF-CVE-2026-65625",
                   "first_patched_versions" => []
                 }
               }
             ]
           }

    assert HexAudit.report([]) == %{"vulnerabilities" => []}
  end

  test "the script prints the report as JSON for the workflow" do
    path = Path.join(System.tmp_dir!(), "hex-audit-#{System.unique_integer([:positive])}.out")
    File.write!(path, jose_output())
    on_exit(fn -> File.rm(path) end)

    script = Path.expand("../../.github/scripts/hex_audit.exs", __DIR__)
    {out, 0} = System.cmd("elixir", [script, path])

    assert %{"vulnerabilities" => list} = JSON.decode!(out)
    assert length(list) == 8
    assert hd(list)["dependency"]["package"] == "jose"
  end
end
