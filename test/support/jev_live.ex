defmodule TalesForge.JevLive do
  @moduledoc """
  What live Jev read for one of Gentry's v353 turns (Tin Valley 169f4dcb,
  Crossroads f9467718, 2026-10-19), from
  `test/fixtures/replay/gentry_v353.json` (each turn's `ai_calls`
  `turn.intent` meta: the top two actions with their probabilities, the
  target and the raw confidence). The trade and clarify tests stub Jev with
  these instead of an invented clean read.

  The playtest stores Jev's answer to an open offer, not its probabilities,
  so `offer_answer` is the stored answer and `offer_probabilities` (only on
  Tin Valley turn 2) was inferred from what the turn did.
  """

  @fixture "test/fixtures/replay/gentry_v353.json"
  @external_resource @fixture
  @turns @fixture
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("sessions")
         |> Enum.flat_map(fn s ->
           Enum.map(s["turns"], &{{s["adventure_id"], &1["turn"]}, &1})
         end)
         |> Map.new()

  @typedoc "A recorded read: `{adventure id, turn number}`."
  @type turn :: {String.t(), pos_integer()}

  @doc "The player's words of the recorded turn."
  @spec text(turn()) :: String.t()
  def text(turn), do: Map.fetch!(@turns, turn)["text"]

  @doc """
  The recorded read as `TalesForge.Game.TradeOffersTest`-style stub
  options: `:action` (Jev's top action label), `:target` (a candidate id or
  nil), `:confidence` (the raw confidence as action and target confidence,
  which `TalesForge.Game.JevIntent` turns back into that raw confidence),
  `:probabilities` and, when the turn answered an open offer, `:offer_answer`.
  """
  @spec read(turn()) :: keyword()
  def read(turn) do
    jev = Map.fetch!(@turns, turn)["jev"]
    raw = jev["raw_confidence"]

    [
      action: String.to_existing_atom(jev["action"]),
      target: jev["target"],
      confidence: %{action: raw, target: raw, safety: 0.99},
      probabilities: probabilities(jev)
    ]
    |> put_offer(jev["offer_answer"])
  end

  @doc "The recorded read as a `TalesForge.Game.Clarify` reading (top two, probabilities, confidence)."
  @spec reading(turn()) :: map()
  def reading(turn) do
    jev = Map.fetch!(@turns, turn)["jev"]
    probs = atoms(jev["probabilities"])

    %{
      action: String.to_existing_atom(jev["action"]),
      target: jev["target"],
      confidence: jev["raw_confidence"],
      top2: probs |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.map(&elem(&1, 0)),
      action_probabilities: probs
    }
  end

  defp probabilities(%{"offer_probabilities" => %{} = offer} = jev),
    do: %{action: atoms(jev["probabilities"]), offer_answer: atoms(offer)}

  defp probabilities(jev), do: %{action: atoms(jev["probabilities"])}

  defp put_offer(opts, nil), do: opts

  defp put_offer(opts, answer),
    do: Keyword.put(opts, :offer_answer, String.to_existing_atom(answer))

  defp atoms(map), do: Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
end
