defmodule TalesForge.Game.FirstMeetingTest do
  use TalesForge.DataCase, async: false
  alias TalesForge.NPC.Rows

  alias TalesForge.Game.FirstMeeting
  alias TalesForge.GameSessions
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  doctest TalesForge.Game.FirstMeeting

  @fixture "test/fixtures/first_meeting/ezzor_turn_19.json" |> File.read!() |> Jason.decode!()

  describe "status/2 and mark/2" do
    test "empty memory and a zero score is a first meeting" do
      assert FirstMeeting.status(%{"memories" => [], "relationship_score" => 0.0}, [], "Ezzor") ==
               :first_meeting

      assert FirstMeeting.status(nil, nil, nil) == :first_meeting
    end

    test "a memory, a dialogue line or a relationship score means has met" do
      assert FirstMeeting.status(%{"memories" => [%{"summary" => "Paid Ezzor."}]}, [], "Ezzor") ==
               :has_met

      assert FirstMeeting.status(%{"relationship_score" => -0.2}, [], "Ezzor") == :has_met
      assert FirstMeeting.status(%{}, ["Back on the road."], "Ezzor") == :has_met
    end

    test "the rule names only the first-meeting NPCs and says hooks are offers made now" do
      rule =
        FirstMeeting.rule([
          {"Mags Ferrow", :first_meeting, true},
          {"Brenna Holt", :has_met, false}
        ])

      assert rule =~ "Mags Ferrow has never met the character"
      refute rule =~ "Brenna Holt"
      assert rule =~ ~s(No "back again", no "as I said")
      assert rule =~ "rumour or reputation"
      assert rule =~ "Hooks are things an NPC can offer or say now"
    end
  end

  # In the real session the NPCs had only "Overheard player: ..." memories
  # (OnOverheard), which do not name Ezzor.
  describe "Ezzor turn 19 (fixture)" do
    setup do
      previous = System.get_env("INN_WORLD")

      on_exit(fn ->
        if previous,
          do: System.put_env("INN_WORLD", previous),
          else: System.delete_env("INN_WORLD")
      end)

      System.put_env("INN_WORLD", "on")
      {:ok, session} = GameSessions.create_session(%{adventure_id: @fixture["adventure_id"]})
      {:ok, _} = GameSessions.submit_message(session.id, @fixture["action"])
      {:ok, session: Repo.get!(GameSession, session.id)}
    end

    test "Mags is a first meeting and the GM prompt forbids 'back again'", %{session: session} do
      world = session.world_state
      present = Enum.sort(world["present_npcs"])
      assert present == @fixture["present_npcs"]

      marks =
        present
        |> Enum.map(&{&1, Rows.get(session.id, &1).runtime_state})
        |> FirstMeeting.mark(@fixture["npc_memory"], @fixture["character"])

      for {id, want} <- @fixture["expect"], do: assert(to_string(marks[id]) == want)

      gm =
        NPC.format_gm_sections(session.id, present,
          dialogue_memory: @fixture["npc_memory"],
          character: @fixture["character"],
          first_meeting: true
        )

      assert gm =~ ~s("meeting": "first_meeting")
      assert gm =~ "Mags Ferrow"
      assert gm =~ "has never met the character"
      assert gm =~ ~s(No "back again")
      assert gm =~ "Hooks are things an NPC can offer or say now"

      off = NPC.format_gm_sections(session.id, present, character: @fixture["character"])
      refute off =~ "meeting"
    end

    test "after Mags has a memory of Ezzor, she has met him", %{session: session} do
      :ok =
        NPC.record_memory(%NPC.Note{
          session_id: session.id,
          npc_id: "drover",
          summary: "Ezzor asked about the stolen salt.",
          tick: 19
        })

      gm = NPC.format_gm_sections(session.id, ["drover"], character: "Ezzor", first_meeting: true)
      assert gm =~ ~s("meeting": "has_met")
      refute gm =~ "has never met the character"
    end
  end
end
