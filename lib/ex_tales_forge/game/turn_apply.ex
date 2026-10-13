defmodule TalesForge.Game.TurnApply do
  @moduledoc """
  Stage 3 rules that apply the outcome of sleep, pay and move to the state
  (`TURN_APPLY_OUTCOMES=on`, `TalesForge.Config.turn_apply_outcomes?/0`).
  All functions are pure.

    * `spend_copper/1` — the amount of a payment with no
      `amount_copper`: a coin amount in the text ("two silver", "3c"),
      else the price of a known service (room, ale, meal).
    * `put_spend_amount/2` — writes that amount into the played action.
    * `sleep_after_lodging/3` — "I pay for a room and go to sleep" also
      plays the sleep: eight hours with a paid bed, one hour without one.
    * `unpaid_sleep/1` — the payment failed, so the sleep is one hour.
    * `unknown_move/2` — a move to a place that the world does not have is
      rejected, and the reason names the exits.

  The service prices come from `priv/rules/economy.md` ("Ale 2c", "Common
  meal 5c", "Private room 3s/night"). They are provisional values.
  """

  alias TalesForge.Game.Rest
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Game.World
  alias TalesForge.Game.WorldClock

  @copper_per %{"c" => 1, "copper" => 1, "s" => 10, "silver" => 10, "g" => 500, "gold" => 500}
  @numbers %{
    "a" => 1,
    "an" => 1,
    "one" => 1,
    "two" => 2,
    "three" => 3,
    "four" => 4,
    "five" => 5,
    "six" => 6,
    "seven" => 7,
    "eight" => 8,
    "nine" => 9,
    "ten" => 10
  }
  @coin_amount ~r/\b(\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten)[\s-]*(c|copper|s|silver|g|gold)\b/iu
  @services [
    {~r/\b(room|bed|lodging|lodgings|night's stay)\b/iu, 30},
    {~r/\b(meal|supper|dinner|stew|breakfast)\b/iu, 5},
    {~r/\b(ale|beer|mug)\b/iu, 2}
  ]

  @doc """
  The copper of a payment, read from `text`. A coin amount wins; else the
  price of a known service; else 0.

  ## Examples

      iex> TalesForge.Game.TurnApply.spend_copper("I pay Marta two silver")
      20
      iex> TalesForge.Game.TurnApply.spend_copper("I pay 3c for bread")
      3
      iex> TalesForge.Game.TurnApply.spend_copper("I pay for a room and go to sleep")
      30
      iex> TalesForge.Game.TurnApply.spend_copper("I pay for an ale")
      2
      iex> TalesForge.Game.TurnApply.spend_copper("I pay my respects")
      0
  """
  @spec spend_copper(String.t() | nil) :: non_neg_integer()
  def spend_copper(text) when is_binary(text) do
    case Regex.run(@coin_amount, text) do
      [_, count, unit] -> count_value(count) * Map.fetch!(@copper_per, String.downcase(unit))
      nil -> service_price(text)
    end
  end

  def spend_copper(_text), do: 0

  defp count_value(count) do
    case Integer.parse(count) do
      {n, ""} -> n
      _ -> Map.fetch!(@numbers, String.downcase(count))
    end
  end

  defp service_price(text) do
    Enum.find_value(@services, 0, fn {words, price} ->
      if Regex.match?(words, text), do: price
    end)
  end

  @doc """
  Writes the amount of `spend_copper/1` into a spend action with no positive
  `amount_copper`. Other actions do not change.
  """
  @spec put_spend_amount(PlayerAction.t(), HandlerResult.t()) ::
          {PlayerAction.t(), HandlerResult.t()}
  def put_spend_amount(
        %PlayerAction{action: %{action_type: :spend} = action} = player_action,
        %HandlerResult{handler: "inventory"} = handler
      ) do
    params = action.parameters || %{}

    case params["amount_copper"] do
      amount when is_integer(amount) and amount > 0 ->
        {player_action, handler}

      _ ->
        params = Map.put(params, "amount_copper", spend_copper(player_action.overall_intent))
        hints = Map.put(handler.state_hints || %{}, "parameters", params)

        {%{player_action | action: %{action | parameters: params}},
         %{handler | state_hints: hints}}
    end
  end

  def put_spend_amount(player_action, handler), do: {player_action, handler}

  @doc """
  Adds the sleep of "I pay for a room and go to sleep" to the handler as
  `"sleep_ticks"`: eight hours at a rest place, one hour elsewhere. A
  rejected payment also gets one hour, because the character sleeps without
  a bed. Other actions do not change.

  ## Examples

      iex> alias TalesForge.Game.Schemas.HandlerResult
      iex> world = %{"location_id" => "inn", "locations" => %{"inn" => %{"name" => "The Inn"}}}
      iex> h = %HandlerResult{handler: "inventory", state_hints: %{}}
      iex> TalesForge.Game.TurnApply.sleep_after_lodging(h, world, "I pay for a room and go to sleep").state_hints["sleep_ticks"]
      32
      iex> TalesForge.Game.TurnApply.sleep_after_lodging(h, world, "I pay for an ale").state_hints
      %{}
  """
  @spec sleep_after_lodging(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def sleep_after_lodging(%HandlerResult{} = handler, world, text) do
    if Rest.lodging_then_sleep?(text) do
      ticks =
        if Rest.rest_place?(world, world["location_id"]) and
             handler.state_hints["rejected"] != true,
           do: WorldClock.parse_duration("sleep"),
           else: WorldClock.ticks_per_hour()

      %{
        handler
        | notes: handler.notes <> " " <> sleep_note(ticks),
          state_hints: Map.put(handler.state_hints || %{}, "sleep_ticks", ticks)
      }
    else
      handler
    end
  end

  @doc """
  The sleep after a failed payment: one hour, with no paid bed. A handler
  with no `"sleep_ticks"` does not change.
  """
  @spec unpaid_sleep(HandlerResult.t()) :: HandlerResult.t()
  def unpaid_sleep(%HandlerResult{state_hints: %{"sleep_ticks" => _} = hints} = handler) do
    short = WorldClock.ticks_per_hour()

    %{
      handler
      | notes: handler.notes <> " The payment failed. " <> sleep_note(short),
        state_hints: Map.put(hints, "sleep_ticks", short)
    }
  end

  def unpaid_sleep(handler), do: handler

  defp sleep_note(ticks) do
    if ticks > WorldClock.ticks_per_hour(),
      do: "Then the character sleeps for eight hours in the paid bed.",
      else: "The character has no paid bed. Narrate a short rest of about one hour."
  end

  @doc """
  Rejects a move to a place that the world does not have. The reason names
  the exits of the current place. Other handlers do not change.

  ## Examples

      iex> alias TalesForge.Game.Schemas.HandlerResult
      iex> world = %{"location_id" => "square", "locations" => %{
      ...>   "square" => %{"name" => "Square", "exits" => ["inn"]},
      ...>   "inn" => %{"name" => "The Inn"}}}
      iex> h = %HandlerResult{handler: "move", target: "fields", state_hints: %{"location_id" => "fields"}}
      iex> TalesForge.Game.TurnApply.unknown_move(h, world).state_hints["reason"]
      "There is no place called fields near here. The exits from Square are: The Inn."
      iex> ok = %HandlerResult{handler: "move", target: "inn", state_hints: %{"location_id" => "inn"}}
      iex> TalesForge.Game.TurnApply.unknown_move(ok, world) == ok
      true
  """
  @spec unknown_move(HandlerResult.t(), map()) :: HandlerResult.t()
  def unknown_move(%HandlerResult{handler: "move"} = handler, world) do
    target = handler.state_hints["location_id"] || handler.target

    if is_binary(target) and World.runtime_location(world, target) == %{} do
      reason =
        "There is no place called #{String.replace(target, "_", " ")} near here. " <> exits(world)

      %HandlerResult{
        handler: "narrate",
        target: target,
        notes: "Move rejected: the place does not exist. The character stays here.",
        state_hints: %{"move_rejected" => true, "rejected" => true, "reason" => reason}
      }
    else
      handler
    end
  end

  def unknown_move(handler, _world), do: handler

  defp exits(%{"location_id" => here_id} = world) when is_binary(here_id) do
    here = World.runtime_location(world, here_id)

    names =
      here
      |> Map.get("exits", [])
      |> List.wrap()
      |> Enum.map(&(World.runtime_location(world, &1)["name"] || String.replace(&1, "_", " ")))

    case names do
      [] -> "The character stays here."
      _ -> "The exits from #{here["name"] || "here"} are: #{Enum.join(names, ", ")}."
    end
  end

  defp exits(_world), do: "The character stays here."
end
