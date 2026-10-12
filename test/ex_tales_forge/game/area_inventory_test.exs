defmodule TalesForge.Game.AreaInventoryTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{ActionHandler, AreaInventory, TurnProcessor}
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction, SingleAction}
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  doctest AreaInventory

  @world %{
    "location_id" => "west_road",
    "character" => %{"inventory" => []}
  }

  defp find_handler(text),
    do: AreaInventory.handler(%HandlerResult{handler: "narrate", state_hints: %{}}, @world, text)

  test "a forage in an area with stock rolls survival for the named entry" do
    h = find_handler("I forage for herbs under the pines")
    assert %HandlerResult{handler: "find", skill: "survival", target: "wild_herbs"} = h
  end

  test "game shot with a bow rolls ranged combat" do
    assert %HandlerResult{skill: "ranged_combat", target: "rabbit"} =
             find_handler("I hunt a rabbit with my bow")
  end

  test "no stock or no find words: the handler stays" do
    assert %HandlerResult{handler: "narrate"} = find_handler("I walk down the road")

    assert %HandlerResult{handler: "narrate"} =
             AreaInventory.handler(
               %HandlerResult{handler: "narrate", state_hints: %{}},
               %{"location_id" => "valley_inn"},
               "I search for coins"
             )
  end

  test "a success takes one unit; a failure finds nothing; an empty area rejects" do
    h = find_handler("I gather some pine resin")

    {world, {:ok, %{applied: ["found 1x pine_resin"]}}} =
      AreaInventory.apply(@world, h, "success")

    assert [%{"id" => "pine_resin", "quantity" => 1}] = world["character"]["inventory"]
    assert world["area_inventories"]["west_road"]["pine_resin"] == 2

    assert {^world, {:ok, %{applied: ["found nothing"]}}} =
             AreaInventory.apply(world, h, "failure")

    empty = put_in(world, ["area_inventories", "west_road", "pine_resin"], 0)

    assert {_, {:error, "There is nothing left to find here."}} =
             AreaInventory.apply(empty, h, "success")
  end

  test "the board books a find into the inventory and the outcome record" do
    {:ok, session} = GameSessions.create_session(%{name: "Area", adventure_id: "tin_valley"})
    session = Repo.get!(GameSession, session.id)

    world =
      session.world_state
      |> Map.put("location_id", "west_road")
      |> put_in(["character", "location_id"], "west_road")

    session = %{session | world_state: world}
    text = "I gather some pine resin"

    action = %PlayerAction{
      overall_intent: text,
      action: %SingleAction{action_type: :observe, parameters: %{}}
    }

    handler = action |> ActionHandler.resolve() |> AreaInventory.handler(world, text)

    board =
      TurnProcessor.apply_board(
        session,
        world["character"],
        handler,
        action,
        %TalesForge.Game.Schemas.MechanicalResolution{skill: "survival", outcome: "success"}
      )

    assert Enum.any?(board.world["character"]["inventory"], &(&1["id"] == "pine_resin"))
    assert [%{"id" => "pine_resin"}] = board.outcome["items"]["gained"]
  end
end
