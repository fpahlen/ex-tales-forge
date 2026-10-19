defmodule TalesForge.Game.Clarify do
  @moduledoc """
  When the player's intent is unclear, nothing moves and the person they
  address asks a short clarifying question in character, echoing the
  player's own words ("A meal? You hungry? Stew or bread and cheese?",
  "Yes to the ale, or the kindling?"). Fredrik's steer via Case on #478;
  `docs/design-trade-offers.md`.

  `decide/1` is pure. It reads Jev's confidence and candidate readings (the
  probabilities of its labels), with the open offer when one is in the
  context, and returns `:act` or `{:clarify, %Clarify{}}` with the
  candidates the question offers:

    1. **An open offer.** Jev answers it `accept`, `decline`, `other_offer`
       (something else offered in the narration) or `other`. Two or more
       plausible answers (each at least #{0.25}) where one is `accept`, or
       an `accept` below the goods threshold, clarify between them. A clear
       `accept` of an offer with options and no pick clarifies between the
       options. A clear `accept` (the buy) or `decline` acts.
    2. **The action read.** The band (`TalesForge.Game.IntentClarification.band/2`)
       clarifies below the threshold for its class (moving goods or coins
       needs more confidence than talk) or when two plausible readings play
       out differently; the candidates are those readings.
    3. **A buy that names nothing for sale.** A buy aimed at the seller
       ("I order a meal" with no kind target) whose words name no item of
       the seller's stock clarifies between the seller's priced stock.

  How hard the person works to understand comes from data she already has
  (`patience/1`, pure: her OCEAN agreeableness and conscientiousness, the
  Maslow level she lives at, and her mood): a patient one is `:helpful`
  (she echoes the player's words and offers the candidates); an impatient
  one is `:brusque` (a short brush-off: "Speak plainly or move on").
  Either way nothing moves. Jev only reports its
  confidence and candidates; it never picks the style.

  The game never reads the player's words for any of this: Jev does
  (`TalesForge.Game.JevIntent`). The words only go to the GM to echo.
  """

  alias TalesForge.Game.{IntentClarification, Inventory, Offer}

  @plausible 0.25
  @max_candidates 4
  # The patience formula (`patience/1`): OCEAN weights, a trait's value when
  # none is authored, the shift for the Maslow level she lives at (a lower,
  # unmet need leaves less patience) and for her mood.
  @agreeableness_weight 0.6
  @conscientiousness_weight 0.4
  @default_trait 5
  @maslow_shift %{
    "physiological" => -4.0,
    "safety" => -2.0,
    "belonging" => 0.0,
    "esteem" => 0.5,
    "self_actualisation" => 1.0
  }
  # Moods are the NPC's state (pack and simulation vocabulary).
  @short_moods ~w(uneasy aggrieved angry annoyed irritated impatient hostile busy grim tired)
  @warm_moods ~w(cheerful friendly content happy pleased warm)
  # At or above this patience she helps; below it she brushes off.
  @helpful_from 5.0

  defstruct words: "", candidates: [], npc_id: nil, npc: nil, style: :helpful

  @typedoc """
  A clarifying question for the GM to voice: the player's `words`, the
  `candidates` it offers (short phrases), the person who asks (`npc_id`,
  `npc`), when known, and how (`style`).
  """
  @type style :: :helpful | :brusque
  @type t :: %__MODULE__{
          words: String.t(),
          candidates: [String.t()],
          npc_id: String.t() | nil,
          npc: String.t() | nil,
          style: style()
        }

  defmodule Input do
    @moduledoc """
    What `TalesForge.Game.Clarify.decide/1` reads: Jev's `reading`, its
    target `candidates`, the intent `context` (with `"open_offer"` while
    one is open), the player's `words`, the action `band`, and the
    confidence a goods or coin move needs (`goods_min`).
    """
    defstruct reading: %{},
              candidates: [],
              context: %{},
              words: "",
              band: :act,
              goods_min: 0.70

    @typedoc "The input of a clarify decision."
    @type t :: %__MODULE__{
            reading: map(),
            candidates: [map()],
            context: map(),
            words: String.t(),
            band: atom(),
            goods_min: float()
          }
  end

  @doc """
  `:act`, or `{:clarify, clarify}` with the candidates to ask between.

      iex> alias TalesForge.Game.Clarify
      iex> offer = %{"giver" => "innkeep", "giver_name" => "Brenna Holt", "price" => 2, "options" => [],
      ...>   "item" => %{"id" => "ale_mug", "name" => "Ale"}}
      iex> reading = %{action: :speak, offer_answer: :accept, offer_pick: nil,
      ...>   probabilities: %{offer_answer: %{accept: 0.55, other_offer: 0.4, decline: 0.03, other: 0.02}}}
      iex> {:clarify, c} = Clarify.decide(%Clarify.Input{reading: reading, words: "Yes.", context: %{"open_offer" => offer}})
      iex> c.candidates
      ["yes to the open offer: Brenna Holt sells Ale for 2c", "something else offered in the last narration"]
      iex> Clarify.decide(%Clarify.Input{reading: %{reading | probabilities: %{offer_answer: %{accept: 0.97}}},
      ...>   words: "Yes.", context: %{"open_offer" => offer}})
      :act
  """
  @spec decide(Input.t()) :: :act | {:clarify, t()}
  def decide(%Input{} = input) do
    case offer_decision(input) do
      :none -> action_decision(input)
      decided -> decided
    end
  end

  @doc "The clarify as the player action carries it (`\"clarify\"`)."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c),
    do: %{
      "words" => c.words,
      "candidates" => c.candidates,
      "npc_id" => c.npc_id,
      "npc" => c.npc,
      "style" => Atom.to_string(c.style)
    }

  @doc """
  How the person asking works to understand: `:helpful` (echo the words,
  offer the candidates) at a patience (`patience/1`) of #{@helpful_from} or
  more, else `:brusque` (a short brush-off). Nobody known (the narrator)
  is helpful.

      iex> alias TalesForge.Game.Clarify
      iex> brenna = %{"ocean" => %{"agreeableness" => 8, "conscientiousness" => 7}, "maslow" => "belonging", "disposition" => "cheerful"}
      iex> Clarify.style(brenna)
      :helpful
      iex> Clarify.style(%{brenna | "maslow" => "physiological"})
      :brusque
      iex> Clarify.style(%{"ocean" => %{"agreeableness" => 4, "conscientiousness" => 8}, "maslow" => "safety", "disposition" => "uneasy"})
      :brusque
      iex> Clarify.style(nil)
      :helpful
  """
  @spec style(map() | nil) :: style()
  def style(%{} = detail),
    do: if(patience(detail) >= @helpful_from, do: :helpful, else: :brusque)

  def style(_detail), do: :helpful

  @doc """
  A person's patience with an unclear player, from data she already has
  (her details in the intent context, `TalesForge.Game.Cast.details/1`):

      #{@agreeableness_weight} × agreeableness + #{@conscientiousness_weight} × conscientiousness
        + Maslow shift (physiological −4, safety −2, belonging 0, esteem +0.5, self-actualisation +1)
        + mood shift (a short mood −1, a warm one +1, else 0)

  OCEAN traits are 0-10 (#{@default_trait} when not authored).

      iex> TalesForge.Game.Clarify.patience(%{"ocean" => %{"agreeableness" => 8, "conscientiousness" => 7}, "maslow" => "belonging", "disposition" => "cheerful"})
      8.6
  """
  @spec patience(map()) :: float()
  def patience(%{} = detail) do
    ocean = detail["ocean"] || %{}

    (@agreeableness_weight * trait(ocean["agreeableness"]) +
       @conscientiousness_weight * trait(ocean["conscientiousness"]) +
       Map.get(@maslow_shift, detail["maslow"], 0.0) + mood_shift(detail["disposition"]))
    |> Float.round(2)
  end

  defp trait(value) when is_number(value), do: value
  defp trait(_value), do: @default_trait

  defp mood_shift(mood) when mood in @short_moods, do: -1
  defp mood_shift(mood) when mood in @warm_moods, do: 1
  defp mood_shift(_mood), do: 0

  # The person `npc_id` of `context`, her style.
  defp style_of(_context, nil), do: :helpful
  defp style_of(context, npc_id), do: style(get_in(context, ["npc_details", npc_id]))

  # --- 1. the open offer ---------------------------------------------------------

  defp offer_decision(%Input{context: %{"open_offer" => %{} = stored}, reading: reading} = input) do
    offer = Offer.from_world(stored)

    case unclear_answer(reading, offer, input.goods_min) || unpicked(reading, offer) do
      nil -> if reading[:offer_answer] in [:accept, :decline], do: :act, else: :none
      candidates -> clarify(input, offer, candidates)
    end
  end

  defp offer_decision(%Input{}), do: :none

  # Two plausible answers, one of them `accept`, or an `accept` below the
  # goods threshold: the answers to ask between, else nil.
  defp unclear_answer(reading, offer, goods_min) do
    answers = plausible(reading, reading[:offer_answer])

    cond do
      :accept in answers and length(answers) > 1 ->
        Enum.map(answers, &answer_text(&1, offer))

      reading[:offer_answer] == :accept and probability(reading, :accept) < goods_min ->
        Enum.map(top_answers(reading), &answer_text(&1, offer))

      true ->
        nil
    end
  end

  # A clear `accept` of an offer with options that picks none: the options.
  defp unpicked(%{offer_answer: :accept, offer_pick: nil}, %Offer{options: [_ | _] = options}),
    do: Enum.map(options, &option_text/1)

  defp unpicked(_reading, _offer), do: nil

  # The offer answers at least plausible, most likely first; with no
  # probabilities, Jev's answer alone.
  defp plausible(reading, answer) do
    case offer_probabilities(reading) do
      probs when map_size(probs) == 0 ->
        List.wrap(answer)

      probs ->
        probs
        |> Enum.filter(fn {_label, p} -> p >= @plausible end)
        |> Enum.sort_by(fn {_label, p} -> -p end)
        |> Enum.map(&elem(&1, 0))
    end
  end

  defp top_answers(reading) do
    reading
    |> offer_probabilities()
    |> Enum.sort_by(fn {_label, p} -> -p end)
    |> Enum.take(2)
    |> Enum.map(&elem(&1, 0))
  end

  defp probability(reading, label) do
    probs = offer_probabilities(reading)
    if map_size(probs) == 0, do: 1.0, else: Map.get(probs, label, 0.0)
  end

  defp offer_probabilities(reading), do: get_in(reading, [:probabilities, :offer_answer]) || %{}

  defp answer_text(:accept, offer), do: "yes to the open offer: #{Offer.text(offer)}"
  defp answer_text(:decline, offer), do: "no to the open offer: #{Offer.text(offer)}"
  defp answer_text(:other_offer, _offer), do: "something else offered in the last narration"
  defp answer_text(_other, _offer), do: "something else"

  defp option_text(%{"item" => item, "price" => price}),
    do: "#{item["name"] || item["id"]} (#{price}c)"

  defp clarify(%Input{words: words, context: context}, %Offer{giver: giver}, candidates),
    do:
      {:clarify,
       %__MODULE__{
         words: words,
         candidates: Enum.uniq(candidates),
         npc_id: giver.slug,
         npc: giver.name,
         style: style_of(context, giver.slug)
       }}

  # --- 2. and 3. the action read ----------------------------------------------------

  defp action_decision(%Input{band: :clarify} = input) do
    candidates = IntentClarification.candidates(input.reading, input.candidates)
    {npc_id, npc} = addressed(input)

    {:clarify,
     %__MODULE__{
       words: input.words,
       candidates: candidates,
       npc_id: npc_id,
       npc: npc,
       style: style_of(input.context, npc_id)
     }}
  end

  defp action_decision(%Input{reading: %{action: :buy}} = input) do
    case unnamed_buy(input) do
      nil -> :act
      {npc_id, stock} -> {:clarify, stock_question(input, npc_id, stock)}
    end
  end

  defp action_decision(%Input{}), do: :act

  # A buy with no item, no options and no item target, whose words name
  # nothing in the seller's stock: `{seller_id, priced_stock}`, else nil.
  defp unnamed_buy(%Input{reading: reading, context: context, words: words} = input) do
    params = primary_params(reading)
    target = reading[:target]
    stock = seller_stock(context, target)

    unless params["item_id"] not in [nil, ""] or params["options"] not in [nil, []] or
             item_target?(input.candidates, target) or stock == [] or
             Inventory.item_named(words, stock) do
      {target, stock}
    end
  end

  defp primary_params(%{extraction: %{actions: [%{parameters: %{} = params} | _]}}), do: params
  defp primary_params(_reading), do: %{}

  defp item_target?(_candidates, nil), do: false

  defp item_target?(candidates, target),
    do: Enum.any?(candidates, &(&1.id == target and &1.kind == :item))

  # The seller's priced stock (every trader's here when the buy names none),
  # cheapest first.
  defp seller_stock(context, target) do
    stocks = Map.get(context, "npc_stock", %{})

    stocks
    |> Map.get(target)
    |> case do
      nil -> stocks |> Map.values() |> Enum.concat()
      list -> list
    end
    |> Inventory.normalize_stock()
    |> Enum.filter(&((&1["price_copper"] || 0) > 0))
    |> Enum.sort_by(& &1["price_copper"])
  end

  defp stock_question(%Input{} = input, npc_id, stock) do
    {_id, name} = addressed(%{input | reading: Map.put(input.reading, :target, npc_id)})

    %__MODULE__{
      words: input.words,
      candidates:
        stock
        |> Enum.take(@max_candidates)
        |> Enum.map(&"#{&1["name"] || &1["id"]} (#{&1["price_copper"]}c)"),
      npc_id: npc_id,
      npc: name,
      style: style_of(input.context, npc_id)
    }
  end

  # The person the read aims at, when it is someone here.
  defp addressed(%Input{reading: reading, context: context}) do
    target = reading[:target]
    name = get_in(context, ["npc_details", target, "name"])

    if target in List.wrap(context["present_npcs"]),
      do: {target, name || target},
      else: {nil, nil}
  end
end
