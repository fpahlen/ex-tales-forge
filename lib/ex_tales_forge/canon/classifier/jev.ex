defmodule TalesForge.Canon.Classifier.Jev do
  @moduledoc """
  The Jev adapter of `TalesForge.Canon.Classifier`: one Jev call labels at
  most #{20} leftover items. Each item gets one question with the fixed
  labels as answers, so Jev returns labels and no prose. The call writes one
  `ai_calls` row (purpose `canon_review`, call_type `jev`).
  """

  @behaviour TalesForge.Canon.Classifier.Adapter

  require Logger

  alias TalesForge.AICalls
  alias TalesForge.Canon.Difference

  @model "jev-1.13.0"
  @purpose "canon_review"
  @max_items 20
  @timeout_ms 15_000

  @impl true
  def classify(items, session_id) do
    items = Enum.take(items, @max_items)
    keys = items |> Enum.with_index(1) |> Map.new(fn {item, i} -> {:"item_#{i}", item.key} end)
    started = System.monotonic_time(:millisecond)

    result =
      Jev.HTTP.post(state(items), questions(items),
        model: @model,
        max_retries: 0,
        receive_timeout: @timeout_ms
      )

    elapsed = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, reply} ->
        record(session_id, {"ok", elapsed}, reply)
        {:ok, Map.new(keys, fn {q, key} -> {key, reply[q]} end)}

      {:error, reason} ->
        record(session_id, {"error", elapsed}, %{})
        Logger.warning("canon review jev failed session=#{session_id} reason=#{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e -> {:error, {:crashed, Exception.message(e)}}
  end

  @doc false
  @spec state([TalesForge.Canon.Classifier.Adapter.item()]) :: String.t()
  def state(items) do
    lines =
      items
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {item, i} -> "#{i}. [#{item.entity_id}] #{item.text}" end)

    "Facts from one game session that the world seed does not hold. " <>
      "Each fact is about an entity that the seed does not name.\n\n" <> lines
  end

  @doc false
  @spec questions([TalesForge.Canon.Classifier.Adapter.item()]) :: keyword()
  def questions(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {_item, i} ->
      {:"item_#{i}",
       {"Which label fits fact #{i}? new_npc: a new person. changed_place: a place differs " <>
          "from the seed. conflict: it contradicts the seed. other: none of these.",
        Difference.labels()}}
    end)
  end

  defp record(session_id, {status, latency_ms}, reply) do
    input = get_in(reply, [:usage, :input_tokens]) || 0

    AICalls.record(%{
      purpose: @purpose,
      call_type: "jev",
      model: Map.get(reply, :model) || @model,
      status: status,
      latency_ms: latency_ms,
      game_session_id: session_id,
      usage: %{input_tokens: input, output_tokens: 0, cost_ticks: round(input * 0.042) * 10_000}
    })
  end
end
