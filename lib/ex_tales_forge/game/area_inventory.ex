defmodule TalesForge.Game.AreaInventory do
  @moduledoc """
  Area inventories (catalogue v2, `JEV_CATALOGUE_V2`; decision 2026-10-12
  "catalogue v2 rules", item 3): forests and other areas hold a limited
  stock of things to find, forage or hunt. Finding one needs a roll.

    * The stock of each area is in `priv/rules/area_inventories.json`
      (PROVISIONAL counts). The session keeps what is left in
      `world_state["area_inventories"]`.
    * `handler/3` turns a search, forage or hunt in an area with stock into
      a `find` handler with the skill of the best entry.
    * `apply/4` books the find after the roll: a success or a partial
      success takes one unit from the area into the inventory. A failure
      finds nothing. An area with nothing left rejects the action.

  All functions are pure.
  """

  alias TalesForge.Game.Inventory
  alias TalesForge.Game.Schemas.HandlerResult

  @path Path.expand("../../../priv/rules/area_inventories.json", __DIR__)
  @external_resource @path
  @areas @path |> File.read!() |> Jason.decode!() |> Map.fetch!("areas")

  @find ~r/\b(search\w* for|look\w* for|hunt\w*|forag\w*|gather\w*|collect\w*|dig\w* for|snar\w*|set (?:a|some) (?:trap|snare)s?|trap(?:s|ping)? (?:a|some))\b/i
  @shoot ~r/\b(shoot\w*|bow|arrow|sling)\b/i

  @doc "The area stock as the rules file has it, by location id."
  @spec areas() :: %{String.t() => [map()]}
  def areas, do: @areas

  @doc """
  What is left to find at `location_id`: the session's counts, or the rules
  file for an area the session has not touched.
  """
  @spec stock(map(), String.t() | nil) :: [map()]
  def stock(world, location_id) do
    base = Map.get(@areas, location_id || "", [])
    left = get_in(world, ["area_inventories", location_id || ""]) || %{}

    Enum.map(base, fn entry ->
      Map.put(entry, "quantity", Map.get(left, entry["id"], entry["quantity"]))
    end)
  end

  @doc """
  True when the words ask to find, forage or hunt something.

      iex> TalesForge.Game.AreaInventory.find?("I forage for herbs under the pines")
      true
      iex> TalesForge.Game.AreaInventory.find?("I walk down the road")
      false
  """
  @spec find?(String.t()) :: boolean()
  def find?(text) when is_binary(text), do: Regex.match?(@find, text)
  def find?(_text), do: false

  @doc """
  A `find` handler for a search, forage or hunt in an area that has a
  stock, or the `handler` as it is. A rejected handler stays as it is.
  """
  @spec handler(HandlerResult.t(), map(), String.t()) :: HandlerResult.t()
  def handler(%HandlerResult{state_hints: %{"rejected" => true}} = handler, _world, _text),
    do: handler

  def handler(%HandlerResult{handler: h} = handler, world, text)
      when h in ["narrate", "skill_check", "freeform", "inventory"] do
    stock = stock(world, world["location_id"])

    if stock != [] and find?(text) do
      entry = best(stock, text)

      %HandlerResult{
        handler: "find",
        skill: find_skill(entry, text),
        target: entry["id"],
        notes: "Find in the area: roll #{find_skill(entry, text)}.",
        state_hints: %{"area_item" => entry["id"]}
      }
    else
      handler
    end
  end

  def handler(handler, _world, _text), do: handler

  @doc """
  Books a find after the roll. Returns `{world, result}`, where `result` is
  `{:ok, %{applied: [...]}}` or `{:error, reason}`, or nil for another
  handler.
  """
  @spec apply(map(), HandlerResult.t() | map(), String.t() | nil) ::
          {map(), {:ok, map()} | {:error, String.t()} | nil}
  def apply(world, %{handler: "find", state_hints: %{"area_item" => item_id}}, outcome) do
    location_id = world["location_id"]
    entry = world |> stock(location_id) |> Enum.find(&(&1["id"] == item_id))

    cond do
      entry == nil or entry["quantity"] <= 0 ->
        {world, {:error, "There is nothing left to find here."}}

      outcome in ["success", "partial_success"] ->
        {take(world, location_id, entry), {:ok, %{applied: ["found 1x #{item_id}"]}}}

      true ->
        {world, {:ok, %{applied: ["found nothing"]}}}
    end
  end

  def apply(world, _handler, _outcome), do: {world, nil}

  # The entry the words name, else the first one with stock left.
  defp best(stock, text) do
    down = String.downcase(text)
    left = Enum.filter(stock, &(&1["quantity"] > 0))
    candidates = if left == [], do: stock, else: left

    words = Regex.scan(~r/[a-z]+/, down) |> List.flatten() |> MapSet.new()

    Enum.find(candidates, fn e -> Enum.any?(e["words"] || [], &MapSet.member?(words, &1)) end) ||
      List.first(candidates)
  end

  # Game shot with a bow or sling rolls ranged combat; the rest rolls the
  # skill of the entry.
  defp find_skill(%{"game" => true}, text) do
    if Regex.match?(@shoot, text), do: "ranged_combat", else: "survival"
  end

  defp find_skill(entry, _text), do: entry["skill"]

  defp take(world, location_id, entry) do
    left =
      world
      |> get_in(["area_inventories", location_id])
      |> Kernel.||(%{})
      |> Map.put(entry["id"], entry["quantity"] - 1)

    items = Inventory.normalize_items(get_in(world, ["character", "inventory"]) || [])

    item = %{
      "id" => entry["id"],
      "name" => entry["name"],
      "copper_value" => entry["copper_value"],
      "quantity" => 1
    }

    world
    |> Map.update("area_inventories", %{location_id => left}, &Map.put(&1, location_id, left))
    |> put_in(["character", "inventory"], Inventory.add_item(items, item))
  end
end
