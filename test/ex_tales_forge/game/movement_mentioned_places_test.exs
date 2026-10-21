defmodule TalesForge.Game.MovementMentionedPlacesTest do
  @moduledoc """
  Characterization of `Movement.mentioned_places/3` before round 2 PR 3.
  The turn cases play the text through the public turn path with no LLM
  calls (`Intent.heuristic_intent/2`, `Intent.validate_player_action/2`,
  `Turn.new/3`, `Turn.Premise.check/1`, `Turn.Mechanics.apply/1`) from the
  Valley Inn in tin_valley.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Context
  alias TalesForge.Game.Intent
  alias TalesForge.Game.Movement
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

  defp play(session, text) do
    context = Context.build_intent_context(session)
    extraction = Intent.heuristic_intent(text, context)
    action = Intent.validate_player_action(extraction, context)

    turn =
      {session, 1}
      |> Turn.new({text, action}, flags: Turn.read_flags(), role: :playtest)
      |> Turn.Premise.check()
      |> Turn.Mechanics.apply()

    [raw | _] = extraction.actions
    {raw, turn.outcome.handler}
  end

  describe "through the turn" do
    setup do
      {:ok, session} = GameSessions.create_session(%{name: "Places", adventure_id: "tin_valley"})
      %{session: session}
    end

    # {text, action type, target, handler, state hints}, from main
    for {text, type, target, handler, hints} <- [
          {"I head up to the cut", :move, "orc_approach", "move",
           %{"location_id" => "orc_approach"}},
          {"I throw a log on the fire to cut off the chill", :other, nil, "narrate", %{}},
          {"I step out into the square", :move, "market_square", "move",
           %{"location_id" => "market_square"}},
          {"I head out toward the market square to claim the orc nest job", :move,
           "market_square", "move", %{"location_id" => "market_square"}},
          {"I go to the square and then up to the cut", :move, "market_square", "move",
           %{"location_id" => "market_square"}}
        ] do
      @case {text, type, target, handler, hints}
      test text, %{session: session} do
        {text, type, target, handler, hints} = @case
        {raw, h} = play(session, text)
        assert {raw.action_type, raw.target} == {type, target}
        assert {h.handler, h.state_hints} == {handler, hints}
      end
    end
  end

  # A pure world: "hall" is one hop from "inn" and "far_hall" is two, and both
  # are called "the hall".
  @world %{
    "locations" => %{
      "inn" => %{"exits" => ["hall", "yard"]},
      "hall" => %{"name" => "Hall", "aliases" => ["the hall"], "exits" => ["inn", "far_hall"]},
      "far_hall" => %{"name" => "Far hall", "aliases" => ["the hall"], "exits" => ["hall"]},
      "yard" => %{
        "name" => "Yard",
        "aliases" => ["the yard", "the yard gate"],
        "exits" => ["inn"]
      }
    }
  }

  test "at the same position the nearer place comes first (hops break the tie)" do
    assert Movement.mentioned_places(@world, "inn", "I go to the hall") ==
             [{"hall", 8}, {"far_hall", 8}, {"hall", 12}]

    assert Movement.mentioned_places(@world, "inn", "I go to the far hall") == [{"far_hall", 12}]
  end

  test "earliest first, the longer term first at one position" do
    assert Movement.mentioned_places(@world, "inn", "I walk out to the yard gate") ==
             [{"yard", 14}, {"yard", 14}, {"yard", 18}]

    assert Movement.mentioned_places(@world, "inn", "I head to the yard, then to the hall") ==
             [{"yard", 10}, {"yard", 14}, {"hall", 28}, {"far_hall", 28}, {"hall", 32}]
  end

  test "no lead-in word or no text: no place" do
    assert Movement.mentioned_places(@world, "inn", "Tell me about the hall") == []
    assert Movement.mentioned_places(@world, "inn", nil) == []
  end
end
