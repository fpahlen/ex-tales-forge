defmodule TalesForge.Game.OutcomeRecord do
  @moduledoc """
  The outcome record of one turn: what the mechanics booked (stage 3 of the
  turn pipeline, tales-forge-docs `docs/design-turn-pipeline.md`).

  The record holds the played action with its result (`accepted` or
  `rejected`, and the reason for a rejection), the coin delta, the items the
  character got and lost, the clock and the location. The server builds it
  from the world before and after the board step. It writes one record for
  each turn.

  With `TURN_OUTCOME_RECORD=on` (`TalesForge.Config.turn_outcome_record?/0`),
  the record goes to the per-turn GM prompt (`prompt_section/1`) and to the
  turn as a `turn.outcome` session event. A rejected action then costs no
  game time (design §11, decision 1). The GM then narrates a rejected sale
  as rejected. With the flag off, the GM prompt is byte-identical to before.
  """

  alias TalesForge.Game.Inventory
  alias TalesForge.Game.Schemas.SingleAction

  # The fixed rejection phrasing of the GM prompt (design §4, #180 "premise
  # phrasing"). Every prompt with a record carries this exact sentence.
  @rejection_template "Narrate each accepted action and each rejected action. Give the reason for a rejection in one in-world sentence."

  # Reason codes for a rejected action, from the reason text of stage 3. The
  # first pattern that matches gives the code.
  @reason_codes [
    {~r/^Premise check:/, "premise_rejected"},
    {~r/nobody here rents rooms/, "no_seller"},
    {~r/is not sold here|in stock/, "not_in_stock"},
    {~r/not in inventory/, "not_owned"},
    {~r/not on the ground/, "not_here"},
    {~r/Insufficient funds/, "insufficient_funds"},
    {~r/requires/, "missing_parameter"},
    {~r/refuses/, "npc_refused"}
  ]

  @typedoc "A string-keyed map, so that the record is stored as JSON as it is."
  @type t :: %{required(String.t()) => term()}

  @typedoc "The inventory step result: `{:ok, details}`, `{:error, reason}` or nil (no inventory action)."
  @type inventory_result :: {:ok, term()} | {:error, String.t()} | nil

  @doc """
  Builds the record from the world before the turn, the world after the board
  step, the played action, the resolved handler and the inventory step result.

      iex> before = %{"world_tick" => 40, "location_id" => "smithy",
      ...>   "character" => %{"location_id" => "smithy", "coins" => %{"copper" => 300},
      ...>   "inventory" => [%{"id" => "hunting_knife", "name" => "hunting knife", "quantity" => 1}]}}
      iex> action = %TalesForge.Game.Schemas.SingleAction{action_type: :sell, target: "smith",
      ...>   parameters: %{"item_id" => "enchanted_armor"}}
      iex> record = TalesForge.Game.OutcomeRecord.build(before, before, action, %{handler: "inventory"},
      ...>   {:error, "Cannot sell 'enchanted_armor' — not in inventory."})
      iex> {hd(record["actions"])["status"], record["coins"]["delta_copper"], record["items"]}
      {"rejected", 0, %{"gained" => [], "lost" => []}}
  """
  @spec build(map(), map(), SingleAction.t(), map(), inventory_result()) :: t()
  def build(world_before, world_after, %SingleAction{} = action, handler, inventory_result) do
    before_char = character(world_before)
    after_char = character(world_after)
    before_copper = Inventory.coin_total_copper(Map.get(before_char, "coins", %{}))
    after_copper = Inventory.coin_total_copper(Map.get(after_char, "coins", %{}))
    {gained, lost} = item_deltas(before_char, after_char)

    %{
      "actions" => actions(action, handler, inventory_result),
      "coins" => %{
        "before_copper" => before_copper,
        "after_copper" => after_copper,
        "delta_copper" => after_copper - before_copper
      },
      "items" => %{"gained" => gained, "lost" => lost},
      "clock" => %{
        "tick_before" => Map.get(world_before, "world_tick"),
        "tick_after" => Map.get(world_after, "world_tick"),
        "time" => Map.get(world_after, "world_clock")
      },
      "location" => %{
        "from" => location(world_before),
        "to" => location(world_after)
      }
    }
  end

  @doc "The fixed sentence that tells the GM how to narrate a rejection."
  @spec rejection_template() :: String.t()
  def rejection_template, do: @rejection_template

  @doc """
  The code for the reason text of a rejected action.

      iex> TalesForge.Game.OutcomeRecord.reason_code("'short_sword' is not sold here.")
      "not_in_stock"
      iex> TalesForge.Game.OutcomeRecord.reason_code("Something else.")
      "rejected"
  """
  @spec reason_code(String.t()) :: String.t()
  def reason_code(reason) when is_binary(reason) do
    Enum.find_value(@reason_codes, "rejected", fn {pattern, code} ->
      if Regex.match?(pattern, reason), do: code
    end)
  end

  @doc """
  The rejected actions of the record, each with its reason.

      iex> TalesForge.Game.OutcomeRecord.rejected(%{"actions" => [
      ...>   %{"type" => "sell", "status" => "rejected", "reason" => "not in inventory"}]})
      [%{"type" => "sell", "status" => "rejected", "reason" => "not in inventory"}]
  """
  @spec rejected(t() | nil) :: [map()]
  def rejected(%{"actions" => actions}), do: Enum.filter(actions, &(&1["status"] == "rejected"))
  def rejected(_record), do: []

  @doc """
  The lines of the record for the GM prompt (`TalesForge.Prompt.Sections.OutcomeRecord`):
  one line per action, then the coins, items, clock and location lines.
  """
  @spec prompt_lines(t()) :: [String.t()]
  def prompt_lines(%{} = record) do
    Enum.map(record["actions"], &action_line/1) ++
      [
        coins_line(record["coins"]),
        items_line(record["items"]),
        clock_line(record["clock"]),
        location_line(record["location"])
      ]
  end

  @doc """
  The session event that stores the record on the turn (kind `turn.outcome`,
  not shown to the player).
  """
  @spec event(t()) :: map()
  def event(%{} = record) do
    %{
      "kind" => "turn.outcome",
      "actor" => "server",
      "player_aware" => false,
      "tick" => get_in(record, ["clock", "tick_after"]) || 0,
      "location_id" => get_in(record, ["location", "to"]),
      "payload" => record
    }
  end

  # HISTORY_STRIP_INJECTION=on: an injection turn plays no action.
  defp actions(_action, %{state_hints: %{"no_action" => true}}, _result), do: []
  defp actions(action, handler, result), do: [action_entry(action, handler, result)]

  defp action_entry(action, handler, inventory_result) do
    base = %{
      "type" => to_string(action.action_type),
      "target" => action.target,
      "handler" => Map.get(handler || %{}, :handler)
    }

    case inventory_result do
      {:error, reason} ->
        reason = to_string(reason)

        Map.merge(base, %{
          "status" => "rejected",
          "reason" => reason,
          "code" => reason_code(reason)
        })

      _ ->
        Map.merge(base, %{"status" => "accepted", "reason" => nil, "code" => nil})
    end
  end

  defp action_line(%{"status" => "rejected"} = a),
    do: "Rejected: #{a["type"]}#{target_words(a)}. Reason: #{a["reason"]}"

  defp action_line(a), do: "Accepted: #{a["type"]}#{target_words(a)}."

  defp target_words(%{"target" => t}) when is_binary(t) and t != "", do: " (#{t})"
  defp target_words(_action), do: ""

  defp coins_line(%{"delta_copper" => 0, "after_copper" => after_copper}),
    do: "Coins: no change (#{after_copper} copper in total)."

  defp coins_line(%{"delta_copper" => delta, "after_copper" => after_copper}) when delta > 0,
    do: "Coins: +#{delta} copper (#{after_copper} copper in total)."

  defp coins_line(%{"delta_copper" => delta, "after_copper" => after_copper}),
    do: "Coins: #{delta} copper (#{after_copper} copper in total)."

  defp items_line(%{"gained" => [], "lost" => []}), do: "Items: no change."

  defp items_line(%{"gained" => gained, "lost" => lost}) do
    [{"gained", gained}, {"lost", lost}]
    |> Enum.reject(fn {_label, items} -> items == [] end)
    |> Enum.map_join("; ", fn {label, items} -> "#{label} " <> item_words(items) end)
    |> then(&"Items: #{&1}.")
  end

  defp item_words(items),
    do: Enum.map_join(items, ", ", &"#{&1["quantity"]}x #{&1["name"] || &1["id"]}")

  defp clock_line(%{"time" => time}) when is_binary(time), do: "Time: #{time}."
  defp clock_line(_clock), do: "Time: no change."

  defp location_line(%{"from" => same, "to" => same}),
    do: "Location: #{same || "unknown"} (no move)."

  defp location_line(%{"from" => from, "to" => to}), do: "Location: #{to} (moved from #{from})."

  defp character(world), do: Map.get(world, "character") || %{}

  defp location(world),
    do: get_in(world, ["character", "location_id"]) || Map.get(world, "location_id")

  defp item_deltas(before_char, after_char) do
    before_q = quantities(before_char)
    after_q = quantities(after_char)
    names = Map.merge(names(before_char), names(after_char))
    ids = (Map.keys(before_q) ++ Map.keys(after_q)) |> Enum.uniq() |> Enum.sort()

    Enum.reduce(ids, {[], []}, fn id, {gained, lost} ->
      delta = Map.get(after_q, id, 0) - Map.get(before_q, id, 0)
      entry = &%{"id" => id, "name" => Map.get(names, id, id), "quantity" => &1}

      cond do
        delta > 0 -> {gained ++ [entry.(delta)], lost}
        delta < 0 -> {gained, lost ++ [entry.(-delta)]}
        true -> {gained, lost}
      end
    end)
  end

  defp quantities(character) do
    character
    |> Map.get("inventory", [])
    |> Inventory.normalize_items()
    |> Enum.reduce(%{}, fn item, acc ->
      Map.update(acc, item["id"], item["quantity"] || 1, &(&1 + (item["quantity"] || 1)))
    end)
  end

  defp names(character) do
    character
    |> Map.get("inventory", [])
    |> Inventory.normalize_items()
    |> Map.new(&{&1["id"], &1["name"]})
  end
end
