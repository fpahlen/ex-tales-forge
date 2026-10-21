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
    * `deferred_move/3` — a talk that sets out for a place the world does
      not have keeps the character here. Moves themselves are settled by
      the intent step (`TalesForge.Locations.Destination`).

  The rules that tell a person's words from a place's take the scene as
  `{world, cast}`: the world state and the session's GM characters
  (`TalesForge.Game.Cast`).

  The service prices come from `priv/rules/economy.md` ("Ale 2c", "Common
  meal 5c", "Private room 3s/night"). They are provisional values.
  """

  alias TalesForge.Game.Cast
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

  @service_names [
    {~r/\b(room|rooms|bed|beds|lodging|lodgings|night's stay)\b/iu, "a room for the night", 30},
    {~r/\b(meal|supper|dinner|stew|breakfast)\b/iu, "a meal", 5},
    {~r/\b(ale|beer|mug)\b/iu, "a mug of ale", 2}
  ]

  @doc """
  The copper of a payment, read from `text`. A coin amount wins; else the
  price of a room; else 0.

  ## Examples

      iex> TalesForge.Game.TurnApply.spend_copper("I pay Marta two silver")
      20
      iex> TalesForge.Game.TurnApply.spend_copper("I pay 3c for bread")
      3
      iex> TalesForge.Game.TurnApply.spend_copper("I pay for a room and go to sleep")
      30
      iex> TalesForge.Game.TurnApply.spend_copper("I pay for an ale")
      0
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

  # Only a room has a price with no seller's stock (`@service_names`); an
  # ale or a meal is bought from the seller's stock (`TalesForge.Game.Trade`).
  defp service_price(text) do
    {words, _name, price} = hd(@service_names)
    if Regex.match?(words, text), do: price, else: 0
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
      iex> cast = %{"marta_kellen" => %TalesForge.GameCharacter{slug: "marta_kellen"}}
      iex> {listed, _h} = TalesForge.Game.TurnApply.item_buy(pa, h, cast)
      iex> {listed.action.target, listed.action.parameters["item_id"]}
      {nil, "ale_mug"}
      iex> from_marta = %{pa | action: %{pa.action | target: "marta_kellen"}}
      iex> TalesForge.Game.TurnApply.item_buy(from_marta, h, cast) == {from_marta, h}
      true
  """
  @spec item_buy(PlayerAction.t(), HandlerResult.t(), Cast.t()) ::
          {PlayerAction.t(), HandlerResult.t()}
  def item_buy(
        %PlayerAction{action: %{action_type: :buy, target: target} = action} = player_action,
        %HandlerResult{handler: "inventory"} = handler,
        cast
      )
      when is_binary(target) and target != "" do
    params = action.parameters || %{}
    item? = params["item_id"] in [nil, ""] and not person?(cast, target)

    if item?,
      do: listed({player_action, handler}, params, target),
      else: {player_action, handler}
  end

  def item_buy(player_action, handler, _cast), do: {player_action, handler}

  defp listed({%PlayerAction{action: action} = player_action, handler}, params, target) do
    params = Map.put(params, "item_id", target)
    hints = Map.put(handler.state_hints || %{}, "parameters", params)

    {%{player_action | action: %{action | target: nil, parameters: params}},
     %{handler | state_hints: hints}}
  end

  defp person?(cast, target), do: Map.has_key?(cast, target)

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
  A move to the place where the character is plays no walk, with or without
  `TURN_APPLY_OUTCOMES` (QA 2026-10-15 retest, session 9a1ff8c2: "I go
  inside the inn" in the Weary Pilgrim told a walk down to the cellar, and
  the location stayed the inn). The move is a move to here when its target
  is the current place, or when the text names the inn and the character
  is in a rest place. The GM gets the reason, so the prose stays here too.

      iex> alias TalesForge.Game.Schemas.HandlerResult
      iex> world = %{"location_id" => "inn", "locations" => %{"inn" => %{"name" => "The Weary Pilgrim"}}}
      iex> h = %HandlerResult{handler: "move", target: "inn", state_hints: %{"location_id" => "inn"}}
      iex> TalesForge.Game.TurnApply.same_place(h, world, "I walk over to the bar.").state_hints["reason"]
      "The character is already in The Weary Pilgrim. There is no walk and no other room."
  """
  @spec same_place(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def same_place(%HandlerResult{handler: "move"} = handler, world, text) do
    here = world["location_id"]
    target = (handler.state_hints || %{})["location_id"] || handler.target

    if is_binary(here) and
         (target == here or
            (is_binary(text) and generic_here?(text, world) and
               not names_target?(text, world, {here, target}))),
       do: stay(world, here),
       else: handler
  end

  def same_place(handler, _world, _text), do: handler

  # "Down to the cellar of the inn": the text names a word of the target
  # place that the current place does not have, so the move stays a move.
  defp names_target?(_text, _world, {_here, target}) when not is_binary(target), do: false

  defp names_target?(text, world, {here, target}) do
    own = place_words(here, World.runtime_location(world, here))
    other = place_words(target, World.runtime_location(world, target)) -- own
    overlap(words(text), other) > 0
  end

  # The text names the place where the character is ("I go into the Weary
  # Pilgrim inn" in the inn). The character stays, and the GM narrates no
  # walk. Gentry's playtest session 141e1b85 on 2026-10-13.
  defp stay(world, here_id) do
    name = World.runtime_location(world, here_id)["name"] || String.replace(here_id, "_", " ")

    %HandlerResult{
      handler: "narrate",
      target: here_id,
      notes:
        "The character is already in #{name}. The character stays here. " <>
          "Narrate no walk. Tell no other room.",
      state_hints: %{
        "same_place" => true,
        "rejected" => true,
        "reason" => "The character is already in #{name}. There is no walk and no other room."
      }
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

  @stop ~w(the and inn)

  # A phrase names an unknown place when it has words and none of them is a
  # word of a person ("to the barkeep"). A general word ("the inn") is no name.
  defp unknown_phrase?(nil, _cast), do: false

  defp unknown_phrase?(phrase, cast) do
    named = words(phrase)
    named != [] and overlap(named, people_words(cast)) == 0
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

  defp people_words(cast) do
    cast
    |> Cast.sorted()
    |> Enum.flat_map(fn gc -> words("#{gc.slug} #{gc.name} #{gc.role}") end)
  end

  defp overlap(words, other), do: Enum.count(words, &(&1 in other))

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
      iex> TalesForge.Game.TurnApply.deferred_move(h, {world, %{}}, "I ask Marta about the old mill and say I'm heading out there now.").state_hints["reason"]
      "There is no place called old mill near here. The exits from The Inn are: Crossroads Square."
      iex> TalesForge.Game.TurnApply.deferred_move(h, {world, %{}}, "I ask Marta about the weather.") == h
      true
  """
  @spec deferred_move(HandlerResult.t(), {map(), Cast.t()}, String.t() | nil) ::
          HandlerResult.t()
  def deferred_move(%HandlerResult{handler: handler_name} = handler, {world, _cast} = scene, text)
      when is_binary(text) and handler_name != "move" do
    hints = handler.state_hints || %{}
    phrase = any_place_phrase(text)

    if Regex.match?(@set_out, text) and hints["rejected"] != true and is_binary(phrase) and
         unknown_place?(phrase, scene) do
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

  def deferred_move(handler, _scene, _text), do: handler

  defp any_place_phrase(text) do
    case Regex.run(@any_place_phrase, text) do
      [_, phrase] -> String.trim(phrase)
      nil -> nil
    end
  end

  # The phrase names no place of the world and no person.
  defp unknown_place?(phrase, {world, cast}) do
    named = words(phrase)

    places =
      world
      |> Map.get("locations", %{})
      |> Enum.flat_map(fn {id, loc} -> place_words(id, loc) end)

    unknown_phrase?(phrase, cast) and overlap(named, places) == 0
  end

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
