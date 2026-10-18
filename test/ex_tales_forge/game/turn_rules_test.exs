defmodule TalesForge.Game.TurnRulesTest do
  @moduledoc """
  The provisional turn rules (`TalesForge.Game.TurnRules`) and the prose
  post-check (`TalesForge.Game.ProseCheck`). With
  `TURN_STATE_FROM_MECHANICS=on`, "pay for a room" in Crossroads Square
  (Gentry's session 0caf, turn 10 as it happened) is rejected with the reason
  "nobody here rents rooms".
  """
  use TalesForge.DataCase, async: false

  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, SessionEvent}

  import Ecto.Query

  doctest TalesForge.Game.TurnRules
  doctest TalesForge.Game.ProseCheck

  @env ~w(TURN_OUTCOME_RECORD TURN_STATE_FROM_MECHANICS)

  setup do
    saved = Map.new(@env, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("XAI_API_KEY")
    end)

    stub_llm(fn
      :gm, _user, _system -> %{"narrative" => "The square is quiet."}
      _kind, _user, _system -> :default
    end)

    System.put_env("TURN_OUTCOME_RECORD", "on")
    :ok
  end

  defp play_room_payment do
    {:ok, session} =
      GameSessions.create_session(%{name: "Room", adventure_id: "crossroads_ledger"})

    session = GameSessions.get_session!(session.id)

    world =
      session.world_state
      |> put_in(["character", "location_id"], "crossroads_square")
      |> Map.put("location_id", "crossroads_square")

    session |> GameSession.changeset(%{world_state: world}) |> save_session!()

    action = %{
      "overall_intent" => "I pay for a room and go to sleep.",
      "action" => %{
        "action_type" => "spend",
        "target" => nil,
        "parameters" => %{"amount_copper" => 0}
      },
      "deferred_actions" => [],
      "confidence" => 0.9
    }

    {:ok, _} = TurnProcessor.run(session.id, {"I pay for a room and go to sleep.", action})

    SessionEvent
    |> where([e], e.game_session_id == ^session.id and e.kind == "turn.outcome")
    |> select([e], e.payload)
    |> Repo.one!()
  end

  test "flag on: a room payment with nobody here who rents rooms is rejected" do
    System.put_env("TURN_STATE_FROM_MECHANICS", "on")
    record = play_room_payment()

    assert [
             %{
               "status" => "rejected",
               "reason" => "nobody here rents rooms",
               "code" => "no_seller"
             }
           ] =
             record["actions"]

    assert record["clock"]["tick_after"] == record["clock"]["tick_before"]
  end

  test "flag off: the payment fails as before, on the missing amount" do
    System.put_env("TURN_STATE_FROM_MECHANICS", "off")
    record = play_room_payment()

    assert [%{"status" => "rejected", "code" => "missing_parameter"}] = record["actions"]
  end
end
