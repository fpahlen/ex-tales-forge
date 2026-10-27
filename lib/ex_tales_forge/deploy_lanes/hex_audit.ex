defmodule TalesForge.DeployLanes.HexAudit do
  @moduledoc """
  Reads the advisories out of `mix hex.audit` output, for
  `.github/workflows/security-audit.yml` (through
  `.github/scripts/hex_audit.exs`, plain `elixir`, no deps).

  `mix hex.audit` knows the Hex advisories (EEF CNA, osv.dev) before
  `mix deps.audit` does: on 2026-10-26 CI's hex.audit failed on jose
  (run 40395854829) while the audit's deps.audit reported nothing, so the
  jose and bandit bumps (#582, #585) were opened by hand. The report has
  the `mix deps.audit --format json` shape, so these advisories go into the
  same bump loop.

      elixir .github/scripts/hex_audit.exs hex-audit.out hex-audit.err

  prints `{"vulnerabilities": [...]}` (an empty list when there is none).
  """

  defmodule Advisory do
    @moduledoc "One advisory line of `mix hex.audit`, with its title and link."
    defstruct package: "", version: "", id: "", severity: "", title: "", url: ""

    @typedoc "One advisory on one package version."
    @type t :: %__MODULE__{
            package: String.t(),
            version: String.t(),
            id: String.t(),
            severity: String.t(),
            title: String.t(),
            url: String.t()
          }
  end

  # "  jose 1.11.12 - EEF-CVE-2026-65625 (MEDIUM)"
  @header ~r/^(\S+) (\S+) - (\S+) \((\w+)\)$/
  # Lines between a header and its title that are not the title. Hex prints
  # "Found packages …" to stderr, so it can land anywhere in the report.
  @not_title ["", "Advisories:", "Found packages with security advisories"]

  @doc """
  The advisories in `mix hex.audit` output (stdout and stderr together), in
  report order.

      iex> TalesForge.DeployLanes.HexAudit.advisories("  plug 1.14.0 - GHSA-aaaa-bbbb-cccc (HIGH)\\n    Bad\\n")
      [%TalesForge.DeployLanes.HexAudit.Advisory{package: "plug", version: "1.14.0",
        id: "GHSA-aaaa-bbbb-cccc", severity: "high", title: "Bad"}]
  """
  @spec advisories(String.t()) :: [Advisory.t()]
  def advisories(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reduce([], &add_line/2)
    |> Enum.reverse()
  end

  defp add_line(line, acc) do
    case Regex.run(@header, line, capture: :all_but_first) do
      [package, version, id, severity] ->
        advisory = %Advisory{package: package, version: version, id: id}
        [%{advisory | severity: String.downcase(severity)} | acc]

      nil ->
        detail(line, acc)
    end
  end

  defp detail(_line, []), do: []
  defp detail("http" <> _ = url, [advisory | rest]), do: [%{advisory | url: url} | rest]
  defp detail("aka:" <> _, acc), do: acc
  defp detail(line, acc) when line in @not_title, do: acc

  defp detail(line, [%Advisory{title: ""} = advisory | rest]),
    do: [%{advisory | title: line} | rest]

  defp detail(_line, acc), do: acc

  @doc "The advisories as a `mix deps.audit --format json` report."
  @spec report([Advisory.t()]) :: map()
  def report(advisories), do: %{"vulnerabilities" => Enum.map(advisories, &vulnerability/1)}

  defp vulnerability(%Advisory{} = a) do
    %{
      "dependency" => %{"package" => a.package, "version" => a.version},
      "advisory" => %{
        "id" => a.id,
        "severity" => a.severity,
        "title" => a.title,
        "url" => a.url,
        "first_patched_versions" => []
      }
    }
  end

  @doc "Entry point for the script: reads the output files, prints the JSON report."
  @spec main([Path.t()]) :: :ok
  def main(paths) do
    paths
    |> Enum.map_join("\n", &File.read!/1)
    |> advisories()
    |> report()
    |> JSON.encode!()
    |> IO.puts()
  end
end
