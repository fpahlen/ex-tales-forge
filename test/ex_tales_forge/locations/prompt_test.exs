defmodule TalesForge.Locations.PromptTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions
  alias TalesForge.Locations
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Positions
  alias TalesForge.Prompt.Sections.Surroundings

  doctest TalesForge.Prompt.Sections.Surroundings

  @door %Position{grid_id: "valley_inn", cell: {9, 0, 0}, facing: :s}

  test "in the Valley Inn the character sees the room from its stored position" do
    lines = Locations.Prompt.surroundings(world(@door))

    assert lines =~ ~r/^ahead: .*open hearth 6 m/m
    assert lines =~ ~r/^left: .*stairs up/m
    refute lines =~ "kitchen hearth"
  end

  test "the view turns with the stored facing" do
    lines = Locations.Prompt.surroundings(world(%Position{@door | cell: {9, 8, 0}, facing: :n}))
    assert lines =~ ~r/^ahead: .*main door/m
  end

  test "a character with no position has no surroundings" do
    assert Locations.Prompt.surroundings(world(nil)) == nil
  end

  defp world(pos) do
    %{"adventure_id" => "tin_valley", "character" => %{"id" => "pc"}}
    |> Positions.put("pc", pos)
  end

  test "the section renders only with LOCATION_GRID on" do
    on = %TalesForge.Prompt.Ctx{
      flags: %{location_grid: true},
      data: %{surroundings: "ahead: open hearth 6 m"}
    }

    off = %{on | flags: %{}}

    assert :surroundings in TalesForge.Prompt.Profile.ids(%{on | call: :gm})
    refute :surroundings in TalesForge.Prompt.Profile.ids(%{off | call: :gm})
    assert Surroundings.render(on) =~ "## Around the character (from the map)\n"
    assert Surroundings.render(%{on | data: %{surroundings: false}}) == nil
  end

  test "the GM prompt of a Tin Valley turn has the view with the flag, and not without" do
    {:ok, session} = GameSessions.create_session(%{name: "Grid", adventure_id: "tin_valley"})
    assert gm_prompt(session, true) =~ "## Around the character (from the map)"
    assert gm_prompt(session, true) =~ "open hearth 6 m"
    refute gm_prompt(session, false) =~ "Around the character"
  end

  defp gm_prompt(session, on?) do
    me = self()

    adapters = %Turn.Adapters{
      gm: fn %TalesForge.LLM.GmTurn{messages: messages} ->
        send(me, {:gm, Enum.map_join(messages, "\n", & &1.content)})
        {:ok, %TalesForge.Game.Schemas.GMStructuredResponse{narrative: "The fire crackles."}}
      end,
      stream: fn _id, _chunk -> :ok end
    }

    action = %TalesForge.Game.Schemas.PlayerAction{
      overall_intent: "look around",
      action: %TalesForge.Game.Schemas.SingleAction{action_type: :observe, target: nil}
    }

    flags = Map.put(Turn.read_flags(), :location_grid, on?)

    {session, 1}
    |> Turn.new({"look around", action}, flags: flags, role: :playtest, adapters: adapters)
    |> Turn.Premise.check()
    |> Turn.Mechanics.apply()
    |> Turn.Npcs.react()
    |> Turn.Place.settle()
    |> Turn.Prompt.build()
    |> Turn.Gm.narrate()

    assert_received {:gm, text}
    text
  end
end
