defmodule TalesForge.Game.QaEad76238Test do
  @moduledoc """
  Regression fixtures from Gentry's playtest QA on 2026-10-14 07:13
  (session ead76238, Crossroads Hamlet, `TURN_APPLY_OUTCOMES=on`):
  `test/fixtures/qa/gentry_ead76238.json` has the player text, the Jev read
  and the stored GM prose of each turn.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.{PremiseCheck, ProseCheck}
  alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

  @fixture "test/fixtures/qa/gentry_ead76238.json" |> File.read!() |> Jason.decode!()

  @flags %{
    turn_outcome_record: true,
    turn_apply_outcomes: true,
    npc_dialogue_memory: false,
    npc_reactions: false,
    world_agents: false,
    turn_premise_first: false,
    turn_state_from_mechanics: false,
    history_strip_injection: false,
    skill_detail_level: false
  }

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "QA", adventure_id: "crossroads_ledger"})
    world = session.world_state

    world =
      world
      |> Map.put("location_id", "weary_pilgrim")
      |> put_in(["character", "location_id"], "weary_pilgrim")

    %{session: %{session | world_state: world}}
  end

  defp fixture(n), do: Enum.find(@fixture["turns"], &(&1["turn"] == n))

  defp play(session, n) do
    t = fixture(n)
    jev = t["jev"]
    action = String.to_existing_atom(jev["action"])
    params = if jev["skill"], do: %{"skill" => jev["skill"]}, else: %{}

    deferred =
      case jev["later"] do
        nil ->
          []

        later ->
          [
            %SingleAction{
              action_type: String.to_existing_atom(later),
              target: jev["later_target"]
            }
          ]
      end

    pa = %PlayerAction{
      overall_intent: t["player_action"],
      action: %SingleAction{action_type: action, target: jev["target"], parameters: params},
      deferred_actions: deferred
    }

    {session, n}
    |> Turn.new({t["player_action"], pa}, flags: @flags, role: :playtest)
    |> Turn.Mechanics.apply()
  end

  test "turn 1: heading out to the old mill keeps the character here and names the exits",
       %{session: session} do
    t = play(session, 1)

    assert t.outcome.handler.state_hints["move_rejected"]
    reason = t.outcome.handler.state_hints["reason"]
    assert reason =~ "There is no place called old mill near here."
    assert reason =~ "Crossroads Square"
    assert t.outcome.board.world["location_id"] == "weary_pilgrim"
  end

  test "turn 2: going inside the inn while in the inn plays no walk", %{session: session} do
    t = play(session, 2)

    assert t.outcome.handler.state_hints["same_place"]
    assert t.outcome.board.world["location_id"] == "weary_pilgrim"
  end

  test "turn 5: an ordered ale is paid and drunk, and no mug stays in the inventory",
       %{session: session} do
    t = play(session, 5)
    character = t.outcome.board.world["character"]
    ids = character |> Map.get("inventory", []) |> Enum.map(& &1["id"])

    refute "ale_mug" in ids
    assert t.outcome.board.outcome["coins"]["delta_copper"] == -2
  end

  test "turn 11: the false kill claim gets a correction" do
    [claim] = PremiseCheck.claims(fixture(11)["player_action"])
    assert claim.kind == :kill
    assert claim.target =~ "bandit chief"

    [finding] =
      PremiseCheck.check(fixture(11)["player_action"], %{
        inventory: [],
        coins: %{},
        combat_wins: 0
      })

    assert finding.correction =~ "Invent no bounty, reward, token or story"
  end

  test "turns 11 and 13: items handed over in the prose and not in the record are bugs" do
    record = %{
      "coins" => %{"delta_copper" => 0},
      "items" => %{"gained" => [], "lost" => []},
      "location" => %{"from" => "weary_pilgrim", "to" => "weary_pilgrim"},
      "clock" => %{"tick_before" => 106, "tick_after" => 107}
    }

    for n <- [11, 13] do
      kinds = fixture(n)["gm_prose"] |> ProseCheck.check(record) |> Enum.map(& &1.kind)
      assert :item in kinds, "turn #{n}"
    end
  end
end
