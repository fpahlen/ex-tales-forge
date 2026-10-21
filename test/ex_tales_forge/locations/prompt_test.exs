defmodule TalesForge.Locations.PromptTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions
  alias TalesForge.Locations
  alias TalesForge.Prompt.Sections.Surroundings

  doctest TalesForge.Prompt.Sections.Surroundings

  test "in the Valley Inn the character sees the room from the main door" do
    lines =
      Locations.Prompt.surroundings(%{
        "adventure_id" => "tin_valley",
        "location_id" => "valley_inn"
      })

    assert lines =~ ~r/^ahead: .*open hearth 6 m/m
    assert lines =~ ~r/^left: .*stairs up/m
    refute lines =~ "kitchen hearth"
  end

  test "a place with no grid has no surroundings" do
    assert Locations.Prompt.surroundings(%{
             "adventure_id" => "tin_valley",
             "location_id" => "market_square"
           }) == nil
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
    |> Turn.Prompt.build()
    |> Turn.Gm.narrate()

    assert_received {:gm, text}
    text
  end
end
