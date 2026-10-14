defmodule TalesForge.PrFeed.Versions do
  @moduledoc """
  The commit each app runs, for "on playtest" / "on prod" in the live PR feed.
  The product app gives it (`Workflow.ProductApp.running_commits/0`).
  """

  @typedoc "The commit each app runs; nil when unknown."
  @type running :: %{production: String.t() | nil, playtest: String.t() | nil}

  @doc "The commit each app runs."
  @spec running() :: running()
  def running do
    running = Workflow.ProductApp.running_commits()
    %{production: running.production, playtest: running.playtest}
  end

  @doc """
  `sha` when it looks like a git commit sha (7 to 40 hex characters), else nil.

      iex> TalesForge.PrFeed.Versions.valid_sha("702CF6F")
      "702cf6f"
      iex> TalesForge.PrFeed.Versions.valid_sha("unknown")
      nil
  """
  @spec valid_sha(term()) :: String.t() | nil
  def valid_sha(sha) when is_binary(sha) do
    sha = sha |> String.trim() |> String.downcase()
    if Regex.match?(~r/\A[0-9a-f]{7,40}\z/, sha), do: sha
  end

  def valid_sha(_sha), do: nil
end
