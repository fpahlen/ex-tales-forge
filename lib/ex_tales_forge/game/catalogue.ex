defmodule TalesForge.Game.Catalogue do
  @moduledoc """
  The mechanics of the catalogue v2 actions (`JEV_CATALOGUE_V2`, turn
  pipeline design §8 step 5; decision 2026-10-12 "catalogue v2 rules"):

    * `work` — pays the unskilled wage (`TalesForge.Game.Economy.unskilled_wage/1`,
      3c per game hour) for the hours worked. Coins only: no skill roll, no
      item, no growth.
    * `equip` — marks an item the character carries as equipped (or not).
    * `give` — gives an item or coin to a present NPC, with nothing back.
      The NPC can refuse because of their traits (`refuses_gift?/1`).
    * the manner adverbs (`manner/1`) change the time and the roll.

  All functions are pure. The tables are **PROVISIONAL**.
  """

  alias TalesForge.Game.Economy
  alias TalesForge.Game.Inventory
  alias TalesForge.Game.WorldClock

  @manners %{
    "quickly" => %{time: 0.5, roll: -2, stealth: false},
    "carefully" => %{time: 1.5, roll: 2, stealth: false},
    "quietly" => %{time: 1.25, roll: 1, stealth: true}
  }

  @no_manner %{time: 1.0, roll: 0, stealth: false}

  # Speech handlers: "quietly" with ask, say or tell is private speech, with
  # no modifier.
  @speech_handlers ~w(speak)

  @unequip ~r/\b(take off|takes off|remove|removes|unequip|sheathe|sheathes|put away|puts away)\b/i

  @doc """
  The modifiers of a manner adverb (PROVISIONAL table): the time factor, the
  roll modifier and the stealth mode. With speech, a manner has no modifier.

      iex> TalesForge.Game.Catalogue.manner("quickly")
      %{time: 0.5, roll: -2, stealth: false}
      iex> TalesForge.Game.Catalogue.manner("quietly", "speak")
      %{time: 1.0, roll: 0, stealth: false}
      iex> TalesForge.Game.Catalogue.manner(nil)
      %{time: 1.0, roll: 0, stealth: false}
  """
  @spec manner(String.t() | atom() | nil, String.t() | nil) :: %{
          time: float(),
          roll: integer(),
          stealth: boolean()
        }
  def manner(manner, handler \\ nil)
  def manner(_manner, handler) when handler in @speech_handlers, do: @no_manner

  def manner(manner, _handler) when is_atom(manner) and not is_nil(manner),
    do: manner(Atom.to_string(manner))

  def manner(manner, _handler), do: Map.get(@manners, manner, @no_manner)

  @doc """
  The ticks of an action after the manner's time factor (at least 1).

      iex> TalesForge.Game.Catalogue.scale_ticks(4, %{time: 0.5})
      2
      iex> TalesForge.Game.Catalogue.scale_ticks(1, %{time: 0.5})
      1
  """
  @spec scale_ticks(non_neg_integer(), map()) :: non_neg_integer()
  def scale_ticks(0, _manner), do: 0
  def scale_ticks(ticks, %{time: factor}), do: max(1, round(ticks * factor))

  @doc """
  The wage for `ticks` of work in `world`: the unskilled wage per game hour,
  for each whole hour (at least one).

      iex> TalesForge.Game.Catalogue.wage(%{}, 8)
      6
      iex> TalesForge.Game.Catalogue.wage(%{}, 1)
      3
  """
  @spec wage(map(), non_neg_integer()) :: pos_integer()
  def wage(world, ticks) do
    hours = max(1, div(ticks, WorldClock.ticks_per_hour()))
    Economy.unskilled_wage(world) * hours
  end

  @doc """
  True when the NPC refuses a gift (PROVISIONAL rule, decision 2026-10-12
  rule 1): a disagreeable NPC (agreeableness 3 or lower) who does not like the
  character yet (relationship 0 or lower).

      iex> TalesForge.Game.Catalogue.refuses_gift?(%{"personality_traits" => %{"agreeableness" => 2}, "relationship_score" => 0.0})
      true
      iex> TalesForge.Game.Catalogue.refuses_gift?(%{"personality_traits" => %{"agreeableness" => 8}})
      false
  """
  @spec refuses_gift?(map() | nil) :: boolean()
  def refuses_gift?(%{} = npc) do
    agreeableness = get_in(npc, ["personality_traits", "agreeableness"])
    relationship = npc["relationship_score"] || 0

    is_number(agreeableness) and agreeableness <= 3 and relationship <= 0
  end

  def refuses_gift?(_npc), do: false

  @doc """
  Applies a catalogue v2 handler to `world`. `text` is the player's words,
  `npc` the target NPC's profile (for `give`). Returns `{world, result}`;
  `result` is `{:ok, details}`, `{:error, reason}` (the action is rejected
  and the world does not change) or `nil` for other handlers.
  """
  @spec apply(map(), struct(), String.t(), map() | nil) ::
          {map(), {:ok, map()} | {:error, String.t()} | nil}
  def apply(world, %{handler: "work", state_hints: hints}, _text, _npc) do
    pay = wage(world, hints["ticks"] || WorldClock.ticks_per_hour())
    {update_coins(world, pay), {:ok, %{applied: [%{"kind" => "wage", "copper" => pay}]}}}
  end

  def apply(world, %{handler: "equip", target: target}, text, _npc) do
    items = Inventory.normalize_items(get_in(world, ["character", "inventory"]) || [])

    case Inventory.resolve_item_id(target || "", items) || item_in_text(text, items) do
      nil ->
        {world, {:error, "The character does not carry that item."}}

      item_id ->
        on = not Regex.match?(@unequip, text)

        {put_in(world, ["character", "inventory"], set_equipped(items, item_id, on)),
         {:ok, %{applied: [%{"kind" => "equip", "item_id" => item_id, "equipped" => on}]}}}
    end
  end

  def apply(world, %{handler: "give", target: npc_id}, text, npc) do
    cond do
      npc_id not in List.wrap(world["present_npcs"]) ->
        {world, {:error, "Nobody by that name is here to take it."}}

      refuses_gift?(npc) ->
        {world, {:error, "#{(npc || %{})["name"] || npc_id} refuses the gift."}}

      true ->
        give(world, npc_id, text)
    end
  end

  def apply(world, _handler, _text, _npc), do: {world, nil}

  defp set_equipped(items, item_id, on) do
    Enum.map(items, fn
      %{"id" => ^item_id} = item -> Map.put(item, "equipped", on)
      item -> item
    end)
  end

  defp give(world, npc_id, text) do
    items = Inventory.normalize_items(get_in(world, ["character", "inventory"]) || [])
    coins = get_in(world, ["character", "coins"]) || %{}

    case {item_in_text(text, items), Inventory.parse_copper_hint(text)} do
      {item_id, _} when is_binary(item_id) ->
        {put_in(world, ["character", "inventory"], Inventory.remove_item(items, item_id)),
         {:ok, %{applied: [%{"kind" => "give", "item_id" => item_id, "to" => npc_id}]}}}

      {nil, amount} when is_integer(amount) and amount > 0 ->
        if Inventory.coin_total_copper(coins) >= amount,
          do:
            {update_coins(world, -amount),
             {:ok, %{applied: [%{"kind" => "give", "copper" => amount, "to" => npc_id}]}}},
          else: {world, {:error, "The character does not have #{amount}c."}}

      _ ->
        {world, {:error, "The character does not carry that."}}
    end
  end

  defp item_in_text(text, items) do
    words = text |> String.downcase()

    Enum.find_value(items, fn item ->
      name = String.downcase(item["name"] || item["id"])
      if String.contains?(words, name), do: item["id"]
    end)
  end

  defp update_coins(world, delta) do
    coins = get_in(world, ["character", "coins"]) || %{}

    updated =
      if delta >= 0,
        do: Inventory.add_coins(coins, delta),
        else: Inventory.deduct_coins(coins, -delta)

    put_in(world, ["character", "coins"], updated)
  end
end
