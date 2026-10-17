defmodule TalesForge.Game.Bargain do
  @moduledoc """
  Bargaining (catalogue v2, `JEV_CATALOGUE_V2`; decision 2026-10-12
  "catalogue v2 rules", item 6, numbers approved):

    * Haggling is a persuasion roll.
    * Appraisal is a separate, optional roll. A success tells the true value
      and the fair local price. Knowing the price gives +2 to persuasion
      (+3 at appraisal 10 or higher), and the haggle then starts from the
      fair price.
    * A success moves the price 10 to 20 % (10 % plus 1 % for each point
      the roll is under the skill, at most 20 %). A partial success moves
      it 10 %.
    * A failure keeps the asking price. No haggle goes past the fair price
      minus 10 % (for a sale: plus 10 %).

  **PROVISIONAL:** the fair local price is the asking price without the
  trader's markup of 10 % (`@markup_percent`). The world has no separate
  fair price yet.

  All functions are pure apart from the dice (`:rolls` injects them).
  """

  alias TalesForge.Game.Mechanics

  @markup_percent 10
  @cap_percent 10

  @haggle ~r/\b(haggl\w*|barter\w*|bargain\w*|lower (?:the|your|his|her) price|better price|cheaper|discount|knock \w+ off|talk (?:him|her|them) down)\b/i
  @appraise ~r/\b(apprais\w*|assess (?:its|the) (?:worth|value)|judge (?:its|the) (?:worth|value)|what (?:is|it's) (?:it )?(?:really )?worth)\b/i

  defmodule Deal do
    @moduledoc """
    What a haggle is over: a `:buy` or a `:sell` at `price` (the asking price
    for a buy, the offer for a sale). `fair` is set by
    `TalesForge.Game.Bargain.haggle/3`.
    """
    defstruct [:kind, :price, :fair]

    @typedoc "A buy or a sale at a price."
    @type t :: %__MODULE__{
            kind: :buy | :sell,
            price: non_neg_integer(),
            fair: non_neg_integer() | nil
          }
  end

  @typedoc "The result of a haggle."
  @type result :: %{
          required(String.t()) => term()
        }

  @doc """
  True when the player's words ask for a haggle.

      iex> TalesForge.Game.Bargain.haggle?("I buy the rope, but I haggle hard")
      true
      iex> TalesForge.Game.Bargain.haggle?("I buy the rope")
      false
  """
  @spec haggle?(String.t()) :: boolean()
  def haggle?(text) when is_binary(text), do: Regex.match?(@haggle, text)
  def haggle?(_text), do: false

  @doc "True when the player's words ask for an appraisal."
  @spec appraise?(String.t()) :: boolean()
  def appraise?(text) when is_binary(text), do: Regex.match?(@appraise, text)
  def appraise?(_text), do: false

  @doc """
  The fair local price for an asking price (PROVISIONAL: the asking price
  without a 10 % markup; for a sale, the offer plus 10 %).

      iex> TalesForge.Game.Bargain.fair_price(:buy, 110)
      100
      iex> TalesForge.Game.Bargain.fair_price(:sell, 100)
      110
  """
  @spec fair_price(:buy | :sell, non_neg_integer()) :: non_neg_integer()
  def fair_price(:buy, asking), do: round(asking * 100 / (100 + @markup_percent))
  def fair_price(:sell, offer), do: round(offer * (100 + @markup_percent) / 100)

  @doc """
  Plays a haggle over the deal's `price` (the asking price for a buy, the
  offer for a sale). Rolls appraisal first when `appraise` is true. Returns the
  character (with the learning points of the rolls) and the result:
  `"price_copper"`, `"fair_copper"`, `"appraised"`, `"outcome"` and
  `"rolls"`.

  `opts`: `:appraise` (default false), `:rolls` (`%{"appraisal" => n,
  "persuasion" => n}`, for tests).

      iex> char = %{"skills" => %{"persuasion" => 25}, "stats" => %{"CHA" => 10}}
      iex> {_char, r} = TalesForge.Game.Bargain.haggle(char, %TalesForge.Game.Bargain.Deal{kind: :buy, price: 110}, rolls: %{"persuasion" => 10})
      iex> {r["outcome"], r["price_copper"]}
      {"success", 96}
      iex> {_char, r} = TalesForge.Game.Bargain.haggle(char, %TalesForge.Game.Bargain.Deal{kind: :buy, price: 110}, rolls: %{"persuasion" => 60})
      iex> {r["outcome"], r["price_copper"]}
      {"failure", 110}
  """
  @spec haggle(map(), Deal.t(), keyword()) :: {map(), result()}
  def haggle(character, %Deal{kind: kind, price: price} = deal, opts \\ []) do
    rolls = Keyword.get(opts, :rolls, %{})
    fair = fair_price(kind, price)

    {appraised, appraisal} = appraise(character, rolls, Keyword.get(opts, :appraise, false))
    known? = known_price?(appraisal)

    start = if known?, do: fair, else: price
    bonus = if known?, do: knowledge_bonus(appraised), else: 0

    {haggled, persuasion} =
      Mechanics.perform_and_apply(appraised, "persuasion",
        roll: rolls["persuasion"],
        modifier: bonus
      )

    deal = %{deal | fair: fair}
    {haggled, result(deal, move(deal, start, percent(persuasion)), {appraisal, persuasion})}
  end

  defp result(%Deal{} = deal, moved, {appraisal, persuasion}) do
    %{
      "price_copper" => moved,
      "asking_copper" => deal.price,
      "fair_copper" => deal.fair,
      "appraised" => known_price?(appraisal),
      "outcome" => persuasion.outcome,
      "rolls" => Enum.reject([appraisal, persuasion], &is_nil/1) |> Enum.map(&roll_map/1)
    }
  end

  defp appraise(character, rolls, true),
    do: Mechanics.perform_and_apply(character, "appraisal", roll: rolls["appraisal"], modifier: 0)

  defp appraise(character, _rolls, false), do: {character, nil}

  defp known_price?(nil), do: false

  defp known_price?(appraisal),
    do: appraisal.outcome in ["critical_success", "success", "partial_success"]

  # +10 to persuasion for a known price, +15 at appraisal 50 or higher.
  defp knowledge_bonus(character) do
    if (get_in(character, ["skills", "appraisal"]) || 0) >= 50, do: 15, else: 10
  end

  # 10 % plus 1 % for each 5 points under the skill, at most 20 %; a critical
  # success moves the full 20 % (better than expected); a partial success
  # moves 10 %; a failure moves nothing.
  defp percent(%{outcome: "critical_success"}), do: 20

  defp percent(%{outcome: "success", roll: roll, effective_skill: skill}),
    do: min(20, 10 + div(max(0, skill - roll), 5))

  defp percent(%{outcome: "partial_success"}), do: 10
  defp percent(_resolution), do: 0

  # A failure keeps the asking price. The cap: never past fair -10 % (+10 %
  # for a sale).
  defp move(%Deal{price: price}, _start, 0), do: price

  defp move(%Deal{kind: :buy, fair: fair, price: price}, start, percent) do
    floor = round(fair * (100 - @cap_percent) / 100)
    start |> Kernel.*(100 - percent) |> Kernel./(100) |> round() |> max(floor) |> min(price)
  end

  defp move(%Deal{kind: :sell, fair: fair, price: price}, start, percent) do
    ceiling = round(fair * (100 + @cap_percent) / 100)
    start |> Kernel.*(100 + percent) |> Kernel./(100) |> round() |> min(ceiling) |> max(price)
  end

  defp roll_map(resolution),
    do: %{
      "skill" => resolution.skill,
      "roll" => resolution.roll,
      "outcome" => resolution.outcome
    }
end
