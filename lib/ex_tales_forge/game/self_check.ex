defmodule TalesForge.Game.SelfCheck do
  @moduledoc """
  A question about the player's own state ("how many coins do I have?",
  "what does my pack contain?") and its answer from the sheet facts
  (`TalesForge.Game.StateFacts`), so the GM states it as the narrator
  (h-qa13, h-qa16).

  Only coins and the pack for now. `asks/1` is the narrow text fallback: it
  matches a few first-person phrasings and misses rather than misfires, so a
  question about an NPC's stock or a debt is left to the GM.

      iex> TalesForge.Game.SelfCheck.asks("What does my pack contain?")
      [:pack]
      iex> TalesForge.Game.SelfCheck.asks("Marta, what's in your stock?")
      []
      iex> facts = TalesForge.Game.StateFacts.build(%{"coins" => %{"copper" => 12}})
      iex> TalesForge.Game.SelfCheck.resolve(facts, [:coins])
      %TalesForge.Game.SelfCheck.Result{coins: "0g 1s 2c", pack: nil}
  """

  alias TalesForge.Game.StateFacts

  defmodule Result do
    @moduledoc "The answer to a self-check: the text of each fact asked, `nil` when not asked."
    defstruct coins: nil, pack: nil

    @type t :: %__MODULE__{coins: String.t() | nil, pack: String.t() | nil}
  end

  @typedoc "What a self-check asks about."
  @type ask :: :coins | :pack

  @money "(?:coins?|money|gold|silver|copper)"
  @purse "(?:coins?|money|purse|coin ?purse|coin pouch|gold|silver)"
  @bag "(?:pack|backpack|bag|satchel|knapsack|rucksack|inventory|pockets?)"
  @look "(?:check|search|look (?:in|into|through|at)|go through|rummage (?:in|through)|open|empty)"

  @patterns [
    coins: [
      ~r/\bhow (?:much|many) #{@money}(?: pieces)? (?:do|did) i (?:have|got|carry|hold)\b/u,
      ~r/\bhow (?:much|many) #{@money} (?:have i got|am i carrying)\b/u,
      ~r/\b(?:count|recount|tally|#{@look}) my #{@purse}\b/u,
      ~r/\bhur (?:mycket|många) (?:pengar|mynt|guld|silver|koppar) har jag\b/u,
      ~r/\b(?:räknar|kollar) (?:mina pengar|mina mynt|min börs|min pung)\b/u
    ],
    pack: [
      ~r/\bwhat(?:'s| is| do i have| have i got| am i carrying| do i carry)? in my #{@bag}\b/u,
      ~r/\bwhat does my #{@bag} (?:contain|hold)\b/u,
      ~r/\bwhat am i carrying\b/u,
      ~r/\b#{@look} my #{@bag}\b/u,
      ~r/\b(?:list|show me) my (?:inventory|pack|belongings)\b/u,
      ~r/\bvad (?:har jag|finns) i (?:packningen|ryggsäcken|väskan|min packning|min ryggsäck|min väska)\b/u,
      ~r/\bvad bär jag på\b/u
    ]
  ]

  @labels %{[] => "none", [:coins] => "coins", [:pack] => "pack", [:coins, :pack] => "both"}

  @doc "What the text asks about the player's own state, in `[:coins, :pack]` order."
  @spec asks(String.t() | nil) :: [ask()]
  def asks(text) when is_binary(text) do
    text = text |> String.downcase() |> String.replace("’", "'")

    for {ask, patterns} <- @patterns, Enum.any?(patterns, &Regex.match?(&1, text)), do: ask
  end

  def asks(_text), do: []

  @doc "The answer to `asks` from the sheet `facts`."
  @spec resolve(StateFacts.t(), [ask()]) :: Result.t()
  def resolve(%StateFacts{} = facts, asks) do
    Enum.reduce(asks, %Result{}, fn ask, result ->
      Map.put(result, ask, StateFacts.fact(facts, ask))
    end)
  end

  @doc "Whether nothing was asked."
  @spec empty?(Result.t()) :: boolean()
  def empty?(%Result{} = result), do: result == %Result{}

  @doc "The eval label of `asks`: `none`, `coins`, `pack` or `both`."
  @spec label([ask()]) :: String.t()
  def label(asks), do: Map.fetch!(@labels, asks)

  @doc "Every eval label."
  @spec labels() :: [String.t()]
  def labels, do: ~w(none coins pack both)
end
