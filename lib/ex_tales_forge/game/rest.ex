defmodule TalesForge.Game.Rest do
  @moduledoc """
  Where a character can sleep, and what a sleep request does elsewhere.

  A long sleep (eight hours, `TalesForge.Game.WorldClock.parse_duration/1`)
  happens only at a rest place. A rest place is a location whose world data
  says that it gives beds: an inn, a tavern or a lodging house (by its id,
  name, aliases or the first words of its blurb), or a place with a bed, cot,
  bunk or bedroll in its fixtures.

  At other places a sleep request is a short wait of one hour, and the GM
  gets the note that there is no bed here. Gentry's session 0caf18f5 on
  2026-10-12: "I pay for a room and go to sleep" in Crossroads Square moved
  the clock from dusk to the witching hour, with no inn and no payment.

  A wait with a number ("I wait eight hours") is not a sleep request and
  stays as it is.
  """

  alias TalesForge.Game.Schemas.HandlerResult
  alias TalesForge.Game.World
  alias TalesForge.Game.WorldClock

  @lodging_word ~r/\b(inn|tavern|alehouse|lodge|lodging|lodging house|hostel|hostelry|guesthouse|guest house|boarding house|bunkhouse|barracks|dormitory|bedroom|inn room)\b/iu
  @blurb_lodging ~r/^\s*(?:an?|the)\s+(?:[\w'-]+[\s,]+){0,4}(?:inn|tavern|alehouse|lodge|lodging house|hostel|hostelry|guesthouse|boarding house|bunkhouse)\b/iu
  @bed_fixture ~r/\b(bed|beds|cot|cots|bunk|bunks|bedroll|bedrolls|pallet|hammock|straw mattress|cot room)\b/iu
  @pay_words ~r/\b(pay|pays|paid|paying|rent|rents|renting|book|books|booking|hire|hires|take|takes|get|gets|buy|buys|purchase)\b/iu
  @room_words ~r/\b(room|rooms|bed|beds|lodging|lodgings|night's stay|cot|bunk)\b/iu
  @sleep_words ~r/\b(sleep|sleeps|sleeping|asleep|nap|naps|napping|turn in|turns in|go to bed|goes to bed|retire for the night|bed down|beds down)\b/iu

  @doc """
  True when the location `location_id` in `world` is a rest place.

  ## Examples

      iex> world = %{"locations" => %{
      ...>   "weary_pilgrim" => %{"name" => "The Weary Pilgrim",
      ...>     "blurb" => "A low-ceilinged tavern smelling of woodsmoke."},
      ...>   "crossroads_square" => %{"name" => "Crossroads Square",
      ...>     "blurb" => "Mud and cobbles. The inn is nearby.", "fixtures" => ["signpost"]}}}
      iex> TalesForge.Game.Rest.rest_place?(world, "weary_pilgrim")
      true
      iex> TalesForge.Game.Rest.rest_place?(world, "crossroads_square")
      false
      iex> TalesForge.Game.Rest.rest_place?(%{"locations" => %{"camp" => %{"fixtures" => ["bedroll"]}}}, "camp")
      true
  """
  @spec rest_place?(map(), String.t() | nil) :: boolean()
  def rest_place?(world, location_id) when is_map(world) and is_binary(location_id) do
    location = get_in(world, ["locations", location_id]) || World.location(location_id) || %{}

    names =
      [location_id, location["name"] | List.wrap(location["aliases"])]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.replace(&1, "_", " "))

    Enum.any?(names, &Regex.match?(@lodging_word, &1)) or
      Regex.match?(@blurb_lodging, to_string(location["blurb"] || "")) or
      location |> Map.get("fixtures", []) |> List.wrap() |> Enum.any?(&bed_fixture?/1)
  end

  def rest_place?(_world, _location_id), do: false

  @doc """
  True when `text` asks to sleep without a number of hours or days.

  ## Examples

      iex> TalesForge.Game.Rest.sleep_request?("I go to sleep")
      true
      iex> TalesForge.Game.Rest.sleep_request?("I wait eight hours")
      false
      iex> TalesForge.Game.Rest.sleep_request?("I sleep for eight hours")
      true
  """
  @spec sleep_request?(String.t() | nil) :: boolean()
  def sleep_request?(text) when is_binary(text), do: Regex.match?(@sleep_words, text)
  def sleep_request?(_text), do: false

  @doc """
  True when `text` books a bed and then sleeps: a pay or rent word, a room or
  bed word, and a sleep word ("I pay for a room and go to sleep"). The intent
  step reads such a message as the payment now and the sleep as the deferred
  action.

  ## Examples

      iex> TalesForge.Game.Rest.lodging_then_sleep?("I pay for a room and go to sleep.")
      true
      iex> TalesForge.Game.Rest.lodging_then_sleep?("I rent a bed for the night and turn in")
      true
      iex> TalesForge.Game.Rest.lodging_then_sleep?("I go to sleep")
      false
      iex> TalesForge.Game.Rest.lodging_then_sleep?("I pay for an ale")
      false
  """
  @spec lodging_then_sleep?(String.t() | nil) :: boolean()
  def lodging_then_sleep?(text) when is_binary(text) do
    Regex.match?(@pay_words, text) and Regex.match?(@room_words, text) and sleep_request?(text)
  end

  def lodging_then_sleep?(_text), do: false

  @doc """
  Makes a wait handler result obey the rest place rule.

  A sleep request of more than one hour (also "I sleep for eight hours") at a place that is not a rest place becomes a wait of one
  hour, and the notes tell the GM that there is no bed here. Other results do
  not change.

  ## Examples

      iex> alias TalesForge.Game.Schemas.HandlerResult
      iex> world = %{"location_id" => "crossroads_square",
      ...>   "locations" => %{"crossroads_square" => %{"name" => "Crossroads Square"}}}
      iex> result = %HandlerResult{handler: "wait", notes: "Wait 32 ticks.", state_hints: %{"ticks" => 32}}
      iex> short = TalesForge.Game.Rest.apply(result, world, "I go to sleep")
      iex> short.state_hints["ticks"]
      4
      iex> short.notes =~ "no bed"
      true
      iex> TalesForge.Game.Rest.apply(result, world, "I wait eight hours").state_hints["ticks"]
      32
  """
  @spec apply(HandlerResult.t(), map(), String.t() | nil) :: HandlerResult.t()
  def apply(
        %HandlerResult{handler: "wait", state_hints: %{"ticks" => ticks}} = result,
        world,
        text
      )
      when is_integer(ticks) and is_map(world) do
    location_id = world["location_id"]

    if ticks > WorldClock.ticks_per_hour() and sleep_request?(text) and
         not rest_place?(world, location_id) do
      short = WorldClock.ticks_per_hour()

      %HandlerResult{
        result
        | notes:
            "Wait #{short} ticks. The character asked to sleep, but there is no bed here " <>
              "(#{place_name(world, location_id)} is not an inn or another rest place). " <>
              "Narrate a short rest of about one hour; a long sleep needs a bed, such as a paid inn room.",
          state_hints: Map.put(result.state_hints, "ticks", short)
      }
    else
      result
    end
  end

  def apply(result, _world, _text), do: result

  defp bed_fixture?(fixture) when is_binary(fixture), do: Regex.match?(@bed_fixture, fixture)
  defp bed_fixture?(_fixture), do: false

  defp place_name(world, location_id) do
    get_in(world, ["locations", location_id || "", "name"]) ||
      get_in(World.location(location_id || "") || %{}, ["name"]) || location_id || "this place"
  end
end
