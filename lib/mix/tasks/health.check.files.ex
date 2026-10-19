defmodule Mix.Tasks.Health.Check.Files do
  @moduledoc """
  The per-PR part of the ratchet (the Kaizen rule in `docs/principles.md`)
  over the `lib/` files the PR touches. A file's score is the sum of the
  Credo ABC sizes of its functions (every clause counts).

    * Net: the touched files that exist at the base must score at least 1
      lower in total on the PR than at the base. A deleted file scores 0
      on the PR, so it helps. A new file is left out of the net: it only has
      to keep to the per-function limits that `Mix.Tasks.Health.Check`
      checks for all code (complexity, ABC size, 4+ parameters).
    * Cap: no file that exists at the base may score more than 10% above
      its base score, or 3 above it when that is more (so a file at 0 can
      still grow). Split it instead.

  A file may get worse inside those bounds when the PR description says
  why. The gate cannot read the PR description, so it only lists those
  files.
  """

  @why "A file that got worse needs a line in the PR description saying why (docs/principles.md)."

  @doc """
  Runs `mix credo` with only `checks` enabled, on `paths` (all of `lib/`
  when empty), and returns its issues.
  """
  @spec credo([{module(), keyword()}], [String.t()]) :: [map()]
  def credo(checks, paths \\ []) do
    config = Path.join(System.tmp_dir!(), "health_credo.exs")
    files = %{included: ["lib/"]}

    configs = %{
      configs: [%{name: "default", files: files, strict: true, checks: %{enabled: checks}}]
    }

    File.write!(config, inspect(configs, limit: :infinity))
    args = ["credo", "--config-file", config, "--strict", "--format", "json"]
    {out, _status} = System.cmd("mix", args ++ paths)
    out |> Jason.decode!() |> Map.fetch!("issues")
  end

  @doc ~S"""
  The score in a Credo complexity issue.

      iex> Mix.Tasks.Health.Check.Files.score(%{"message" => "ABC size is 12, max is 0"})
      12
  """
  @spec score(map()) :: non_neg_integer()
  def score(issue) do
    [_, score] = Regex.run(~r/is (\d+), max/, issue["message"])
    String.to_integer(score)
  end

  @doc """
  Measures the touched files (`scores/1`), prints the files that got worse
  and returns the problems (`errors/2`).
  """
  @spec check(String.t()) :: [String.t()]
  def check(ref) do
    {base, pr} = scores(ref)
    Enum.each(worse(base, pr), &Mix.shell().info/1)
    errors(base, pr)
  end

  @doc """
  `{base, pr}`: the ABC score of each `lib/` file that changed since the
  merge base with `ref`, at the merge base and in the working tree. A file
  is missing from a side where it does not exist.
  """
  @spec scores(String.t()) :: {map(), map()}
  def scores(ref) do
    base = merge_base(ref)
    paths = touched(base)
    dir = Path.join(System.tmp_dir!(), "health-files-#{System.unique_integer([:positive])}")

    try do
      files = write(dir, "base", base_sources(base, paths)) ++ write(dir, "pr", sources(paths))
      sums = abc_sums(files)
      {side(sums, dir, "base"), side(sums, dir, "pr")}
    after
      File.rm_rf(dir)
    end
  end

  defp merge_base(ref) do
    {out, 0} = git(["merge-base", ref, "HEAD"])
    String.trim(out)
  end

  defp touched(base) do
    {names, 0} = git(["diff", "--name-only", "--no-renames", base, "--", "lib/"])
    names |> String.split("\n", trim: true) |> Enum.filter(&String.ends_with?(&1, ".ex"))
  end

  defp base_sources(base, paths),
    do: for(path <- paths, {src, 0} <- [git(["show", "#{base}:#{path}"])], do: {path, src})

  defp sources(paths), do: for(path <- paths, {:ok, src} <- [File.read(path)], do: {path, src})

  # Writes each `{path, source}` under `dir/side` and returns the files.
  defp write(dir, side, sources) do
    for {path, src} <- sources do
      file = Path.join([dir, side, path])
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, src)
      file
    end
  end

  # file => the sum of its functions' ABC sizes.
  defp abc_sums([]), do: %{}

  defp abc_sums(files) do
    [{Credo.Check.Refactor.ABCSize, [max_size: 0]}]
    |> credo(files)
    |> Enum.reduce(Map.new(files, &{&1, 0}), fn issue, sums ->
      Map.update!(sums, issue["filename"], &(&1 + score(issue)))
    end)
  end

  # The sums of the files under `dir/side`, by their path in the repo.
  defp side(sums, dir, side) do
    root = Path.join(dir, side)

    for {file, sum} <- sums, String.starts_with?(file, root <> "/"), into: %{} do
      {Path.relative_to(file, root), sum}
    end
  end

  defp git(args), do: System.cmd("git", args, stderr_to_stdout: true)

  @doc """
  Problems with the touched files' scores, `base` and `pr` being file =>
  ABC sum (a file missing from `base` is new, one missing from `pr` is
  deleted): an existing file more than 10% (and more than 3) above its base
  score, or the existing files not at least 1 lower in total.
  """
  @spec errors(map(), map()) :: [String.t()]
  def errors(base, pr), do: cap_errors(base, pr) ++ net_errors(base, pr)

  defp cap_errors(base, pr) do
    for {file, old} <- base, new = pr[file], new - old > max(old / 10, 3) do
      "#{file}: ABC #{new}, base #{old} (#{change(old, new)}), over the cap for one file " <>
        "(+10%, at least +3): split it. #{@why}"
    end
  end

  defp net_errors(base, _pr) when map_size(base) == 0, do: []

  defp net_errors(base, pr) do
    old = base |> Map.values() |> Enum.sum()
    new = base |> Map.keys() |> Enum.map(&Map.get(pr, &1, 0)) |> Enum.sum()

    if new < old,
      do: [],
      else: [
        "net: the touched lib/ files that exist on the base score ABC #{new}, base #{old} " <>
          "(#{signed(new - old)}); the PR must lower them by at least 1 in total. " <>
          "Per file: #{deltas(base, pr)}. #{@why}"
      ]
  end

  @doc "A line for each existing file that scores higher than at the base."
  @spec worse(map(), map()) :: [String.t()]
  def worse(base, pr) do
    for {file, old} <- base, new = pr[file], new > old do
      "#{file} got worse: ABC #{new}, base #{old} (#{change(old, new)}). #{@why}"
    end
  end

  defp deltas(base, pr) do
    Enum.map_join(base, ", ", fn {file, old} ->
      "#{file} #{old} -> #{Map.get(pr, file, 0)}"
    end)
  end

  defp change(0, new), do: signed(new)
  defp change(old, new), do: "#{signed(new - old)}, #{signed(round((new - old) * 100 / old))}%"

  defp signed(n) when n > 0, do: "+#{n}"
  defp signed(n), do: "#{n}"
end
