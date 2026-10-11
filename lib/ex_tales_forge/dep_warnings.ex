defmodule TalesForge.DepWarnings do
  @moduledoc """
  Lists the compiler warnings of dependencies for CI's "Dependency warnings"
  job (`.github/scripts/dep_warnings.exs`, plain `elixir`, no deps).

      mix deps.compile --force > deps-compile.log 2>&1
      elixir .github/scripts/dep_warnings.exs deps-compile.log .github/dep-warnings-known.txt

  Each warning is matched against `.github/dep-warnings-known.txt`. A known
  warning is listed with its reason, in a collapsed section. A **new** warning
  is listed at the top of the job summary and gets a GitHub warning
  annotation. The report never fails the job.

  The known file has one entry per line, `package | pattern | reason`, with a
  space on both sides of each separating `|` (so a pattern can use `|` without
  spaces). The pattern is a regular expression, matched against the warning
  text and its location. A `#` at the start of a line or after a space starts a
  comment.

  This module uses only Elixir's standard library.
  """

  @typedoc "One dependency warning from the compile log."
  @type warning :: %{package: String.t(), message: String.t(), location: String.t() | nil}

  @typedoc "One entry of the known list."
  @type known :: %{
          package: String.t(),
          pattern: Regex.t(),
          source: String.t(),
          reason: String.t()
        }

  @typedoc "The warnings, split into new ones and known ones (with their entry)."
  @type report :: %{new: [warning()], known: [{warning(), known()}]}

  @doc "Entry point for the script: prints the report and writes the summary and annotations."
  @spec main([String.t()]) :: :ok
  def main([log, known_path]) do
    known = known_path |> File.read!() |> parse_known()
    report = log |> File.read!() |> parse_log() |> classify(known)

    Enum.each(report.new, fn w ->
      IO.puts("::warning title=New dependency warning (#{w.package})::#{escape(annotation(w))}")
    end)

    markdown = summary(report)
    IO.puts(markdown)

    case System.get_env("GITHUB_STEP_SUMMARY") do
      path when is_binary(path) and path != "" -> File.write!(path, markdown, [:append])
      _ -> :ok
    end
  end

  def main(_argv) do
    IO.puts(:stderr, "usage: dep_warnings.exs <compile log> <known list>")
    System.halt(2)
  end

  @doc """
  The warnings in a `mix deps.compile` log. The package comes from the
  location (`(jido_action 2.3.0) lib/…`), or else from the last `==> package`
  line. Erlang warnings (`file.erl:1:2: Warning: …`) count too.

      iex> log = "==> oban\\n     warning: this clause is never used\\n     │\\n     └─ (oban 2.23.0) lib/oban/repo.ex:253:8: Oban.Repo.f/1\\n"
      iex> TalesForge.DepWarnings.parse_log(log)
      [%{package: "oban", message: "this clause is never used", location: "lib/oban/repo.ex:253:8: Oban.Repo.f/1"}]
  """
  @spec parse_log(String.t()) :: [warning()]
  def parse_log(log) do
    log
    |> String.replace(~r/\e\[[0-9;]*m/, "")
    |> String.split("\n")
    |> Enum.reduce({nil, nil, []}, &parse_line/2)
    |> finish()
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp parse_line(line, {package, open, done}) do
    cond do
      match = Regex.run(~r/^==> (\S+)/, line) ->
        {Enum.at(match, 1), nil, close(open, done)}

      match = Regex.run(~r/^\s*warning: (.*)$/, line) ->
        {package,
         %{package: package || "unknown", message: String.trim(Enum.at(match, 1)), location: nil},
         close(open, done)}

      match = Regex.run(~r/^\s*└─ (?:\((\S+) [^)]*\) )?(.*)$/, line) ->
        {package, nil, close(locate(open, match), done)}

      match = Regex.run(~r/^(\S+\.[eh]rl):(\d+(?::\d+)?): [Ww]arning: (.*)$/, line) ->
        [_, file, at, message] = match

        warning = %{
          package: package || "unknown",
          message: String.trim(message),
          location: "#{file}:#{at}"
        }

        {package, nil, [warning | close(open, done)]}

      true ->
        {package, open, done}
    end
  end

  defp locate(nil, _match), do: nil

  defp locate(open, [_, pkg, location]) do
    %{open | location: String.trim(location), package: if(pkg == "", do: open.package, else: pkg)}
  end

  defp close(nil, done), do: done
  defp close(open, done), do: [open | done]

  defp finish({_package, open, done}), do: close(open, done)

  @doc """
  Parses the known list. Raises `ArgumentError` on a line that is not
  `package | pattern | reason` or has an invalid pattern.
  """
  @spec parse_known(String.t()) :: [known()]
  def parse_known(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, number} ->
      case line |> String.replace(~r/(^|\s)#.*$/, "") |> String.trim() do
        "" -> []
        entry -> [known_entry(entry, number)]
      end
    end)
  end

  defp known_entry(entry, number) do
    with [package, pattern, reason] <-
           entry |> String.split(~r/\s\|\s/, parts: 3) |> Enum.map(&String.trim/1),
         true <- package != "" and pattern != "" and reason != "",
         {:ok, regex} <- Regex.compile(pattern) do
      %{package: package, pattern: regex, source: pattern, reason: reason}
    else
      _ ->
        raise ArgumentError,
              "dep-warnings-known line #{number}: expected `package | pattern | reason`"
    end
  end

  @doc "Splits warnings into new and known ones (the first entry that matches)."
  @spec classify([warning()], [known()]) :: report()
  def classify(warnings, known) do
    {known_hits, new} =
      warnings
      |> Enum.map(fn w -> {w, Enum.find(known, &known?(&1, w))} end)
      |> Enum.split_with(fn {_w, entry} -> entry != nil end)

    %{new: Enum.map(new, &elem(&1, 0)), known: known_hits}
  end

  defp known?(entry, w) do
    entry.package == w.package and
      Regex.match?(entry.pattern, w.message <> " " <> (w.location || ""))
  end

  @doc "The job summary in Markdown: new warnings first, known ones collapsed."
  @spec summary(report()) :: String.t()
  def summary(%{new: new, known: known}) do
    head =
      case new do
        [] ->
          ["### Dependency warnings: no new warnings", ""]

        _ ->
          [
            "### Dependency warnings: #{length(new)} NEW",
            "",
            "Add each one to `.github/dep-warnings-known.txt` with a reason, or fix it (a dep update). This report does not fail the job.",
            ""
          ] ++ Enum.map(new, &"- **#{&1.package}**: #{md(&1.message)}#{where(&1)}") ++ [""]
      end

    known_part =
      case known do
        [] ->
          ["No known warnings."]

        _ ->
          [
            "<details><summary>#{length(known)} known warning(s), with reasons</summary>",
            ""
            | Enum.map(known, fn {w, entry} ->
                "- **#{w.package}**: #{md(w.message)}#{where(w)}. Reason: #{entry.reason}"
              end)
          ] ++ ["", "</details>"]
      end

    Enum.join(head ++ known_part, "\n") <> "\n"
  end

  defp where(%{location: nil}), do: ""
  defp where(%{location: location}), do: " (`#{location}`)"

  defp md(text), do: String.replace(text, ~r/([`*|<>])/, "\\\\\\1")

  defp annotation(w), do: w.message <> if(w.location, do: " (#{w.location})", else: "")

  defp escape(text) do
    text
    |> String.replace("%", "%25")
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
  end
end
