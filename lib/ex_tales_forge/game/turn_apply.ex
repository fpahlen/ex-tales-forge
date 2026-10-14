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
    * `item_buy/3` — a purchase whose target is an item ("ale_mug") gets
      that item, and the seller is the person here who has it in stock.
    * `service_buy/3` — a purchase of a service ("I buy an ale", "I order
      a meal") with no item becomes a payment at the service price.
    * `named_move/3` — a move goes to the place that the text names. A move
      to the place where the character is plays no walk. A move
      to a named place that the world does not have is rejected.
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
  Makes the target of a purchase its item when the target is not a person.
  Jev gives a purchase the item as its target ("ale_mug"), and the inventory
  step reads the target as the seller. The seller is then the person here
  who has the item in stock. Other actions do not change.

  Gentry's playtest sessions 141e1b85 and 1c82f268 on 2026-10-13: "I buy an
  ale" was a purchase with target `ale_mug`, and it cost 0c.

  ## Examples

      iex> alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction, SingleAction}
      iex> pa = %PlayerAction{overall_intent: "I buy an ale",
      ...>   action: %SingleAction{action_type: :buy, target: "ale_mug", parameters: %{}}}
      iex> h = %HandlerResult{handler: "inventory", target: "ale_mug", state_hints: %{}}
      iex> {listed, _h} = TalesForge.Game.TurnApply.item_buy(pa, h, %{"present_npcs" => ["marta_kellen"]})
      iex> {listed.action.target, listed.action.parameters["item_id"]}
      {nil, "ale_mug"}
  """
  @spec item_buy(PlayerAction.t(), HandlerResult.t(), map()) ::
          {PlayerAction.t(), HandlerResult.t()}
  def item_buy(
        %PlayerAction{action: %{action_type: :buy, target: target} = action} = player_action,
        %HandlerResult{handler: "inventory"} = handler,
        world
      )
      when is_binary(target) and target != "" do
    params = action.parameters || %{}
    price = spend_copper(player_action.overall_intent)

    cond do
      params["item_id"] in [nil, ""] and not person_or_nil?(world, target) and
        drink_here?(player_action.overall_intent) and price > 0 ->
        spend_here(player_action, handler, price)

      params["item_id"] in [nil, ""] and not person_or_nil?(world, target) ->
        listed(player_action, handler, params, target)

      true ->
        {player_action, handler}
    end
  end

  def item_buy(player_action, handler, _world), do: {player_action, handler}

  # "I order an ale", "I drink an ale": the character drinks or eats it at
  # the counter, so it is a payment at the service price and no item.
  # Gentry's playtest session ead76238 on 2026-10-14: the Mug of Ale stayed
  # in the inventory after the character drank it.
  @drink_here ~r/\b(?:order|orders|ordering|drink|drinks|drinking|have a|grab a|down a)\b/iu

  defp drink_here?(text) when is_binary(text), do: Regex.match?(@drink_here, text)
  defp drink_here?(_text), do: false

  defp spend_here(%PlayerAction{action: action} = player_action, handler, price) do
    params = Map.put(action.parameters || %{}, "amount_copper", price)
    spend = %{action | action_type: :spend, target: nil, parameters: params}

    hints =
      (handler.state_hints || %{})
      |> Map.put("parameters", params)
      |> Map.put("action_type", "spend")

    {%{player_action | action: spend}, %{handler | state_hints: hints}}
  end

  defp listed(%PlayerAction{action: action} = player_action, handler, params, target) do
    params = Map.put(params, "item_id", target)
    hints = Map.put(handler.state_hints || %{}, "parameters", params)

    {%{player_action | action: %{action | target: nil, parameters: params}},
     %{handler | state_hints: hints}}
  end

  @doc """
  Makes a purchase of a service with no item a payment at the service price.
  The purchase has no item when it has no `"item_id"` and its target is
  empty or a person. Other actions do not change.

  Gentry's playtest session f3a7bac0 on 2026-10-13: Jev read "I order a
  meal" as a purchase from Marta Kellen, and the purchase cost 0c.

  ## Examples

      iex> alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction, SingleAction}
      iex> world = %{"npc_state" => %{"marta_kellen" => %{"name" => "Marta Kellen"}}}
      iex> pa = %PlayerAction{overall_intent: "I order a meal.",
      ...>   action: %SingleAction{action_type: :buy, target: "marta_kellen", parameters: %{}}}
      iex> h = %HandlerResult{handler: "inventory", state_hints: %{}}
      iex> {paid, _h} = TalesForge.Game.TurnApply.service_buy(pa, h, world)
      iex> {paid.action.action_type, paid.action.parameters["amount_copper"]}
      {:spend, 5}
  """
  @spec service_buy(PlayerAction.t(), HandlerResult.t(), map()) ::
          {PlayerAction.t(), HandlerResult.t()}
  def service_buy(
        %PlayerAction{action: %{action_type: :buy} = action} = player_action,
        %HandlerResult{handler: "inventory"} = handler,
        world
      ) do
    params = action.parameters || %{}
    price = spend_copper(player_action.overall_intent)

    if params["item_id"] in [nil, ""] and person_or_nil?(world, action.target) and price > 0 do
      spend = %{action | action_type: :spend, parameters: Map.put(params, "amount_copper", price)}

      hints =
        (handler.state_hints || %{})
        |> Map.put("parameters", spend.parameters)
        |> Map.put("action_type", "spend")

      {%{player_action | action: spend}, %{handler | state_hints: hints}}
    else
      {player_action, handler}
    end
  end

  def service_buy(player_action, handler, _world), do: {player_action, handler}

  defp person_or_nil?(_world, nil), do: true
  defp person_or_nil?(_world, ""), do: true

  defp person_or_nil?(world, target) do
    Map.has_key?(world["npc_state"] || %{}, target) or target in List.wrap(world["present_npcs"])
  end

  @doc """
  Adds the sleep of "I pay for a room and go to sleep" to the handler as
  `"sleep_ticks"`: until the next morning at a rest place
  (`WorldClock.ticks_to_morning/1`), one hour elsewhere. A
  rejected payment also gets one hour, because the character sleeps without
  a bed. Other actions do not change.

  ## Examples

      iex> alias TalesForge.Game.Schemas.HandlerResult
      iex> world = %{"location_id" => "inn", "world_tick" => 41, "locations" => %{"inn" => %{"name" => "The Inn"}}}
      iex> h = %HandlerResult{handler: "inventory", state_hints: %{}}
      iex> TalesForge.Game.TurnApply.sleep_after_lodging(h, world, "I pay for a room and go to sleep").state_hints["sleep_ticks"]
      63
      iex> TalesForge.Game.TurnApply.sleep_after_lodging(h, world, "I pay for an ale").state_hints
      %{}
  """
  @spec sleep_after_lodging(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def sleep_after_lodging(%HandlerResult{} = handler, world, text) do
    if Rest.lodging_then_sleep?(text) do
      now = world["world_tick"] || WorldClock.default_start_tick()

      ticks =
        if Rest.rest_place?(world, world["location_id"]) and
             handler.state_hints["rejected"] != true,
           do: WorldClock.ticks_to_morning(now),
           else: WorldClock.ticks_per_hour()

      %{
        handler
        | notes: handler.notes <> " " <> sleep_note(ticks) <> wake_note(now + ticks),
          state_hints: Map.put(handler.state_hints || %{}, "sleep_ticks", ticks)
      }
    else
      handler
    end
  end

  # The GM narrates the time of day at which the character wakes: the clock
  # of the sheet. Gentry's playtest session 11f60fb5 on 2026-10-13: the prose
  # said dawn and the clock said witching hour.
  defp wake_note(tick),
    do:
      " The character wakes at #{WorldClock.format(tick)}. Narrate this time of day, not another."

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
      do: "Then the character sleeps in the paid bed until the morning.",
      else: "The character has no paid bed. Narrate a short rest of about one hour."
  end

  @doc """
  Makes a move go to the place that `text` names. The place with the most
  words in common with the text wins (name, id and fixtures). When the text
  names a place ("to the old mill") that has no word in common with any
  place or person of the world, the move is rejected. Other handlers do not
  change.

  Gentry's playtest session f3a7bac0 on 2026-10-13: Jev always gives a move
  a known place, so "I walk to the old mill" moved the character into the
  Weary Pilgrim, and "I go into the Weary Pilgrim inn" moved the character
  into the Pilgrim Cellar.

  ## Examples

      iex> alias TalesForge.Game.Schemas.HandlerResult
      iex> world = %{"location_id" => "square", "locations" => %{
      ...>   "square" => %{"name" => "Crossroads Square", "exits" => ["inn"]},
      ...>   "inn" => %{"name" => "The Weary Pilgrim", "exits" => ["square", "cellar"]},
      ...>   "cellar" => %{"name" => "Pilgrim Cellar"}}}
      iex> h = %HandlerResult{handler: "move", target: "cellar", state_hints: %{"location_id" => "cellar"}}
      iex> TalesForge.Game.TurnApply.named_move(h, world, "I go into the Weary Pilgrim inn.").state_hints["location_id"]
      "inn"
      iex> h = %HandlerResult{handler: "move", target: "inn", state_hints: %{"location_id" => "inn"}}
      iex> TalesForge.Game.TurnApply.named_move(h, world, "I walk to the old mill by the creek.").state_hints["reason"]
      "There is no place called old mill near here. The exits from Crossroads Square are: The Weary Pilgrim."
  """
  @spec named_move(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def named_move(%HandlerResult{handler: "move"} = handler, world, text) when is_binary(text) do
    target = handler.state_hints["location_id"] || handler.target
    words = words(text)

    scores =
      world
      |> Map.get("locations", %{})
      |> Enum.map(fn {id, loc} -> {id, overlap(words, place_words(id, loc))} end)
      |> Enum.sort()

    target_score = Enum.find_value(scores, 0, fn {id, s} -> if id == target, do: s end)
    {best, best_score} = Enum.max_by(scores, fn {_id, s} -> s end, fn -> {nil, 0} end)
    phrase = place_phrase(text)

    cond do
      generic_here?(text, world) ->
        stay(world, world["location_id"])

      best_score > target_score and best == world["location_id"] ->
        stay(world, best)

      best_score > target_score ->
        %{
          handler
          | target: best,
            notes: "Move to #{best}.",
            state_hints: Map.put(handler.state_hints || %{}, "location_id", best)
        }

      target_score == 0 and unknown_phrase?(phrase, world) ->
        reject_move(phrase, world)

      true ->
        handler
    end
  end

  def named_move(handler, _world, _text), do: handler

  # The text names the place where the character is ("I go into the Weary
  # Pilgrim inn" in the inn). The character stays, and the GM narrates no
  # walk. Gentry's playtest session 141e1b85 on 2026-10-13.
  defp stay(world, here_id) do
    name = World.runtime_location(world, here_id)["name"] || String.replace(here_id, "_", " ")

    %HandlerResult{
      handler: "narrate",
      target: here_id,
      notes: "The character is already in #{name}. The character stays here. Narrate no walk.",
      state_hints: %{"same_place" => true}
    }
  end

  # A general word for a lodging place ("inside the inn", "into the tavern")
  # names the place where the character is when that place is a rest place.
  # Gentry's playtest session ead76238 on 2026-10-14: "I go inside the inn"
  # in the Weary Pilgrim moved the character to the Pilgrim Cellar.
  @generic_inn ~r/\b(?:inn|tavern|taproom|alehouse|pub|common room)\b/iu
  @leave_words ~r/\b(?:out of|leave|leaves|exit|exits|outside)\b/iu

  defp generic_here?(text, world) do
    here = world["location_id"]

    is_binary(here) and Regex.match?(@generic_inn, text) and
      not Regex.match?(@leave_words, text) and Rest.rest_place?(world, here)
  end

  @place_phrase ~r/\b(?:to|into|towards?)\s+the\s+([\p{L}' -]+?)(?=\s+(?:by|near|on|in|at|with|and|beside|of)\b|[,.!?;]|$)/iu
  @stop ~w(the and inn)

  # A phrase names an unknown place when it has words and none of them is a
  # word of a person ("to the barkeep"). A general word ("the inn") is no name.
  defp unknown_phrase?(nil, _world), do: false

  defp unknown_phrase?(phrase, world) do
    named = words(phrase)
    named != [] and overlap(named, people_words(world)) == 0
  end

  defp place_phrase(text) do
    case Regex.run(@place_phrase, text) do
      [_, phrase] -> String.trim(phrase)
      nil -> nil
    end
  end

  defp words(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 3 and &1 not in @stop))
    |> Enum.uniq()
  end

  defp place_words(id, loc) do
    [id, loc["name"] | List.wrap(loc["fixtures"])]
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&words/1)
  end

  defp people_words(world) do
    world
    |> Map.get("npc_state", %{})
    |> Enum.flat_map(fn {id, npc} -> words("#{id} #{npc["name"]} #{npc["role"]}") end)
  end

  defp overlap(words, other), do: Enum.count(words, &(&1 in other))

  defp reject_move(name, world) do
    %HandlerResult{
      handler: "narrate",
      target: name,
      notes:
        "Move rejected: the place does not exist. The character stays here. " <>
          "Give the exits as a plain list, in the words of the reason.",
      state_hints: %{
        "move_rejected" => true,
        "rejected" => true,
        "reason" => "There is no place called #{name} near here. " <> exits(world)
      }
    }
  end

  @set_out ~r/\b(?:head|heads|heading|go|goes|going|walk|walks|walking|set out|setting out|leave|leaving|travel|travelling|traveling|ride|riding|on my way)\b/iu
  @any_place_phrase ~r/\b(?:to|into|towards?|about|for|at)\s+the\s+([\p{L}' -]+?)(?=\s+(?:by|near|on|in|at|with|and|beside|of)\b|[,.!?;]|$)/iu

  @doc """
  Keeps the character here when the turn is not a move but the text sets out
  for a place that the world does not have ("I ask Marta about the old mill
  and say I'm heading out there now"). The handler stays (the character
  still talks), and it gets the reason with the exits and a note: the
  character stays here, and the GM narrates no walk. Other handlers do not
  change.

  Gentry's playtest session ead76238 on 2026-10-14: Jev read the turn as
  speech with a deferred move, so the move check did not run, and the prose
  walked the character to the square.

  ## Examples

      iex> alias TalesForge.Game.Schemas.HandlerResult
      iex> world = %{"location_id" => "inn", "locations" => %{
      ...>   "inn" => %{"name" => "The Inn", "exits" => ["square"]},
      ...>   "square" => %{"name" => "Crossroads Square"}}}
      iex> h = %HandlerResult{handler: "narrate", target: "marta_kellen", notes: "Talk.", state_hints: %{}}
      iex> TalesForge.Game.TurnApply.deferred_move(h, world, "I ask Marta about the old mill and say I'm heading out there now.").state_hints["reason"]
      "There is no place called old mill near here. The exits from The Inn are: Crossroads Square."
      iex> TalesForge.Game.TurnApply.deferred_move(h, world, "I ask Marta about the weather.") == h
      true
  """
  @spec deferred_move(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def deferred_move(%HandlerResult{handler: handler_name} = handler, world, text)
      when is_binary(text) and handler_name != "move" do
    hints = handler.state_hints || %{}
    phrase = any_place_phrase(text)

    if Regex.match?(@set_out, text) and hints["rejected"] != true and is_binary(phrase) and
         unknown_place?(phrase, world) do
      %{
        handler
        | notes:
            String.trim(
              (handler.notes || "") <>
                " The character stays here this turn. Narrate no walk. Give the exits as a plain list, in the words of the reason."
            ),
          state_hints:
            hints
            |> Map.put("move_rejected", true)
            |> Map.put("reason", "There is no place called #{phrase} near here. " <> exits(world))
      }
    else
      handler
    end
  end

  def deferred_move(handler, _world, _text), do: handler

  defp any_place_phrase(text) do
    case Regex.run(@any_place_phrase, text) do
      [_, phrase] -> String.trim(phrase)
      nil -> nil
    end
  end

  # The phrase names no place of the world and no person.
  defp unknown_place?(phrase, world) do
    named = words(phrase)

    places =
      world
      |> Map.get("locations", %{})
      |> Enum.flat_map(fn {id, loc} -> place_words(id, loc) end)

    unknown_phrase?(phrase, world) and overlap(named, places) == 0
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
      target |> String.replace("_", " ") |> reject_move(world)
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

  @doc """
  QA 2026-10-14 08:57: "I wait until dusk" waits to the named time of day
  (`TalesForge.Game.WorldClock.ticks_until/2`), not the default hour. The
  wait handler gets those ticks and a note with the new clock.

      iex> h = %TalesForge.Game.Schemas.HandlerResult{handler: "wait", state_hints: %{"ticks" => 4}}
      iex> TalesForge.Game.TurnApply.wait_until(h, %{"world_tick" => 104}, "I wait until dusk.").state_hints
      %{"ticks" => 32}
  """
  @spec wait_until(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def wait_until(%HandlerResult{handler: "wait"} = handler, world, text) when is_binary(text) do
    tick = Map.get(world, "world_tick", WorldClock.default_start_tick())

    case WorldClock.ticks_until(text, tick) do
      nil ->
        handler

      ticks ->
        ticks = WorldClock.clamp_wait(ticks)

        %{
          handler
          | notes:
              "Wait #{ticks} ticks, until #{WorldClock.format(tick + ticks)}. Narrate that time of day.",
            state_hints: Map.put(handler.state_hints || %{}, "ticks", ticks)
        }
    end
  end

  def wait_until(handler, _world, _text), do: handler

  @service_names [
    {~r/\b(room|rooms|bed|beds|lodging|lodgings|night's stay)\b/iu, "a room for the night", 30},
    {~r/\b(meal|supper|dinner|stew|breakfast)\b/iu, "a meal", 5},
    {~r/\b(ale|beer|mug)\b/iu, "a mug of ale", 2}
  ]

  @doc """
  QA 2026-10-14 08:57: the GM quoted a room at "eight silver", the server
  charged 30c, and later the GM said "three silver". The server prices of the
  services (`spend_copper/1`) were not in the turn data. At a rest place
  (`TalesForge.Game.Rest.rest_place?/2`), a text that names a service adds
  the server price to the handler notes, so the GM quotes that price.

      iex> h = %TalesForge.Game.Schemas.HandlerResult{handler: "narrate", notes: "No check."}
      iex> world = %{"location_id" => "inn", "locations" => %{"inn" => %{"tags" => ["inn"]}}}
      iex> TalesForge.Game.TurnApply.service_prices(h, world, "How much is a room?").notes
      "No check. Server price: a room for the night costs 3 silver (30c). Quote only this price."
  """
  @spec service_prices(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def service_prices(%HandlerResult{state_hints: %{"rejected" => true}} = handler, _world, _text),
    do: handler

  def service_prices(%HandlerResult{} = handler, world, text) when is_binary(text) do
    lines =
      for {words, name, copper} <- @service_names, Regex.match?(words, text) do
        "Server price: #{name} costs #{coin_words(copper)}."
      end

    if lines == [] or not Rest.rest_place?(world, world["location_id"]) do
      handler
    else
      note = Enum.join(lines, " ") <> " Quote only this price."
      %{handler | notes: Enum.join(Enum.reject([handler.notes, note], &(&1 in [nil, ""])), " ")}
    end
  end

  def service_prices(handler, _world, _text), do: handler

  defp coin_words(copper) when rem(copper, 10) == 0, do: "#{div(copper, 10)} silver (#{copper}c)"
  defp coin_words(copper), do: "#{copper} copper"
end
