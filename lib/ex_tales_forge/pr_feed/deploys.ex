defmodule TalesForge.PrFeed.Deploys do
  @moduledoc """
  Is a merged pull request running on an app? Its merge commit is compared
  with the commit the app runs (`TalesForge.PrFeed.Versions`) along main's
  history (the newest commits of main, newest first, from GitHub).

  - `:deployed`: the merge commit is the running commit or older than it.
  - `:pending`: the merge commit is newer than the running commit.
  - `:unknown`: the running commit isn't known (no `GIT_SHA`, the other app
    didn't answer) or isn't among main's newest commits, or the merge commit
    isn't known.
  - `:not_merged`: used by `TalesForge.PrFeed` for open and closed pull requests.

  Main only moves forward and both apps deploy commits of main
  (`.github/workflows/playtest.yml`, `deploy-production.yml`), so "older on
  main" means "included". A merge commit older than the whole list is included
  whenever the running commit is in the list.
  """

  @prefix 7

  @typedoc "Where a pull request stands on one app."
  @type status :: :deployed | :pending | :unknown | :not_merged

  @doc """
  The status of `merge_sha` on an app running `running_sha`, given `main`
  (commit shas of main, newest first; nil when they couldn't be fetched).

      iex> main = ["c3", "c2", "c1"]
      iex> TalesForge.PrFeed.Deploys.status("c2", main, "c3")
      :deployed
      iex> TalesForge.PrFeed.Deploys.status("c2", main, "c2")
      :deployed
      iex> TalesForge.PrFeed.Deploys.status("c3", main, "c2")
      :pending
      iex> TalesForge.PrFeed.Deploys.status("c0", main, "c1")
      :deployed
      iex> TalesForge.PrFeed.Deploys.status("c2", main, nil)
      :unknown
      iex> TalesForge.PrFeed.Deploys.status("c2", main, "elsewhere")
      :unknown
      iex> TalesForge.PrFeed.Deploys.status("c2", nil, "c3")
      :unknown
  """
  @spec status(String.t() | nil, [String.t()] | index() | nil, String.t() | nil) :: status()
  def status(merge_sha, main, running_sha) when is_list(main),
    do: status(merge_sha, index(main), running_sha)

  def status(merge_sha, %{} = main, running_sha)
      when is_binary(merge_sha) and is_binary(running_sha) do
    case position(main, running_sha) do
      nil ->
        :unknown

      running ->
        case position(main, merge_sha) do
          nil -> :deployed
          merged when merged >= running -> :deployed
          _newer -> :pending
        end
    end
  end

  def status(_merge_sha, _main, _running_sha), do: :unknown

  @typedoc """
  Main's commits as a lookup: the first #{@prefix} characters of each sha
  (or the whole sha when it is shorter) point to its shas and positions.
  """
  @type index :: %{optional(String.t()) => [{String.t(), non_neg_integer()}]}

  @doc """
  Builds the lookup of `main` (commit shas, newest first) once, so
  `status/3` finds each sha in one map read.

      iex> main = TalesForge.PrFeed.Deploys.index(["c3c3c3c3", "c2c2c2c2"])
      iex> TalesForge.PrFeed.Deploys.status("c3c3c3c", main, "c2c2c2c2aaaa")
      :pending
  """
  @spec index([String.t()]) :: index()
  def index(main) when is_list(main) do
    main
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {sha, at}, acc ->
      sha = String.downcase(sha)
      Map.update(acc, key(sha), [{sha, at}], &[{sha, at} | &1])
    end)
    |> Map.new(fn {key, entries} -> {key, Enum.reverse(entries)} end)
  end

  # Full and abbreviated shas match each other (GIT_SHA may be either).
  defp position(main, sha) do
    sha = String.downcase(sha)

    Enum.find_value(Map.get(main, key(sha), []), fn {candidate, at} ->
      if same_sha?(candidate, sha), do: at
    end)
  end

  defp key(sha) when byte_size(sha) >= @prefix, do: binary_part(sha, 0, @prefix)
  defp key(sha), do: sha

  defp same_sha?(a, b) when byte_size(a) >= @prefix and byte_size(b) >= @prefix,
    do: String.starts_with?(a, b) or String.starts_with?(b, a)

  defp same_sha?(a, b), do: a == b
end
