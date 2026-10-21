defmodule TalesForge.WorldCollectLinesTest do
  @moduledoc """
  Characterization of `TalesForge.World.collect/2` and
  `TalesForge.World.prompt_lines/1` before round 2 PR 6: which agents a
  turn collects, in budget order, and the exact prompt lines within the fact
  and character budget. No LLM calls.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.GameSessions
  alias TalesForge.World

  describe "collect/2" do
    setup do
      {:ok, session} = GameSessions.create_session(%{name: "Collect", adventure_id: "tin_valley"})
      %{session: session, world: session.world_state}
    end

    defp collected(session, world) do
      session.id
      |> World.collect(world)
      |> Enum.map(&{&1.id, &1.role, &1.kind, &1.name, &1.parent, length(&1.facts), &1.mood})
    end

    test "here, present, then the parents around", %{session: session, world: world} do
      assert collected(session, world) == [
               {"valley_inn", :here, :location, "Valley Inn", "tin_valley_village", 5, nil},
               {"innkeep", :present, :person, "Brenna Holt", nil, 1, nil},
               {"tin_valley_village", :around, :location, "Tin Valley village",
                "tin_valley_region", 1, nil},
               {"tin_valley_region", :around, :location, "Tin Valley", nil, 3, nil}
             ]
    end

    test "a repeated person comes once", %{session: session, world: world} do
      world =
        world
        |> put_in(["character", "location_id"], "market_square")
        |> Map.put("present_npcs", ["innkeep", "guild_steward", "innkeep"])

      assert collected(session, world) == [
               {"market_square", :here, :location, "Market Square", "tin_valley_village", 0, nil},
               {"innkeep", :present, :person, "Brenna Holt", nil, 1, nil},
               {"guild_steward", :present, :person, "Osric Vane", nil, 0, nil},
               {"tin_valley_village", :around, :location, "Tin Valley village",
                "tin_valley_region", 1, nil},
               {"tin_valley_region", :around, :location, "Tin Valley", nil, 3, nil}
             ]
    end

    test "no location: only the people", %{session: session, world: world} do
      world =
        world |> put_in(["character", "location_id"], nil) |> Map.put("present_npcs", ["innkeep"])

      assert collected(session, world) == [
               {"innkeep", :present, :person, "Brenna Holt", nil, 1, nil}
             ]
    end

    test "an unknown place, and carried things the pack has no agent for", %{
      session: session,
      world: world
    } do
      world =
        world
        |> put_in(["character", "location_id"], "nowhere")
        |> Map.put("present_npcs", [])
        |> put_in(["character", "inventory"], [%{"id" => "hunting_knife"}, "rope", 7])

      assert collected(session, world) == [{"nowhere", :here, :location, "nowhere", nil, 0, nil}]
    end
  end

  describe "prompt_lines/1" do
    defp agent(id, role, facts),
      do: %{id: id, name: String.capitalize(id), role: role, facts: facts}

    defp facts(n, source),
      do: Enum.map(1..n, &%{"text" => "#{source} fact #{&1}", "source" => source})

    defp fact(text), do: [%{"text" => text, "source" => "pack"}]

    test "role words and the kinds of fact text; an agent with no facts gives no line" do
      agents = [
        agent("inn", :here, [
          %{"text" => "warm", "source" => "pack"},
          %{"text" => "a bell", "source" => "narration", "turn" => 3},
          %{"text" => "no turn", "source" => "narration"}
        ]),
        agent("brenna", :present, [
          %{"kind" => "promise", "text" => "a room", "source" => "narration", "turn" => 2},
          %{"kind" => "promise", "text" => "soup", "source" => "gm"}
        ]),
        agent("knife", :held, [%{"text" => "sharp", "source" => "gm"}]),
        agent("vale", :around, fact("hills")),
        agent("empty", :present, [])
      ]

      assert World.prompt_lines(agents) == [
               "- Inn [inn] (here): warm; a bell (turn 3); no turn",
               "- Brenna [brenna] (present): promised: a room (turn 2); promised: soup",
               "- Knife [knife] (carried): sharp",
               "- Vale [vale] (around): hills"
             ]
    end

    test "pack facts first, then the last four others" do
      agents = [agent("inn", :here, facts(6, "gm") ++ facts(2, "pack"))]

      assert World.prompt_lines(agents) == [
               "- Inn [inn] (here): pack fact 1; pack fact 2; gm fact 3; gm fact 4; gm fact 5; gm fact 6"
             ]
    end

    test "at most 12 facts across the agents" do
      agents = [
        agent("a", :here, facts(5, "pack")),
        agent("b", :present, facts(5, "pack")),
        agent("c", :around, facts(5, "pack")),
        agent("d", :around, facts(1, "pack"))
      ]

      assert World.prompt_lines(agents) == [
               "- A [a] (here): pack fact 1; pack fact 2; pack fact 3; pack fact 4; pack fact 5",
               "- B [b] (present): pack fact 1; pack fact 2; pack fact 3; pack fact 4; pack fact 5",
               "- C [c] (around): pack fact 1; pack fact 2"
             ]
    end

    test "over 1200 characters an agent is skipped and a later smaller one still fits" do
      x = String.duplicate("x", 1000)
      z = String.duplicate("z", 200)

      agents = [
        agent("a", :here, fact(x)),
        agent("b", :present, fact(String.duplicate("y", 300))),
        agent("c", :around, fact(z)),
        agent("d", :around, fact("w"))
      ]

      assert World.prompt_lines(agents) == ["- A [a] (here): " <> x, "- C [c] (around): " <> z]
    end

    test "no agents, no lines" do
      assert World.prompt_lines([]) == []
    end
  end
end
