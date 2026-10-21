defmodule TalesForge.Game.BargainTest do
  use TalesForge.DataCase, async: false
  alias TalesForge.NPC.Rows

  alias TalesForge.Game.{ActionHandler, Inventory}
  alias TalesForge.Game.Turn.Board
  alias TalesForge.Game.Schemas.{MechanicalResolution, PlayerAction, SingleAction}
  alias TalesForge.GameSessions
  alias TalesForge.NPC

  doctest TalesForge.Game.Bargain

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Bargain", adventure_id: "tin_valley"})
    session = GameSessions.get_session!(session.id)

    put_stock(session.id, [
      %{"id" => "rope", "name" => "Rope", "price_copper" => 110, "quantity" => 3}
    ])

    {:ok, session: GameSessions.get_session!(session.id)}
  end

  defp set_runtime(session_id, changes) do
    inst = Rows.get(session_id, "innkeep")

    Rows.update!(inst, Map.merge(inst.runtime_state, changes))
  end

  # Brenna's stock, written the way a trade writes it (only a trade moves goods).
  defp put_stock(session_id, items) do
    %{"innkeep" => brenna} = NPC.traders(session_id, ["innkeep"])
    :ok = NPC.put_inventories(session_id, [%{brenna | inventory: items}])
  end

  defp buy(session, text, opts) do
    action = %PlayerAction{
      overall_intent: text,
      action: %SingleAction{
        action_type: :buy,
        target: "innkeep",
        parameters: %{"item_id" => "rope"}
      }
    }

    Board.resolve(%Board{
      session: session,
      character: session.world_state["character"],
      handler: ActionHandler.resolve(action),
      player_action: action,
      mechanical: %MechanicalResolution{},
      opts: opts
    })
  end

  defp copper(board), do: Inventory.coin_total_copper(board.world["character"]["coins"])

  test "a haggle with a low roll lowers the price", %{session: session} do
    before = Inventory.coin_total_copper(session.world_state["character"]["coins"])

    board =
      buy(session, "I buy the rope, but I haggle",
        catalogue_v2: true,
        haggle_rolls: %{"persuasion" => 1}
      )

    paid = before - copper(board)
    assert paid < 110 and paid >= 90
  end

  test "a failed haggle pays the asking price", %{session: session} do
    before = Inventory.coin_total_copper(session.world_state["character"]["coins"])

    board =
      buy(session, "I buy the rope, but I haggle",
        catalogue_v2: true,
        haggle_rolls: %{"persuasion" => 60}
      )

    assert before - copper(board) == 110
  end

  test "with the flag off there is no haggle", %{session: session} do
    before = Inventory.coin_total_copper(session.world_state["character"]["coins"])
    board = buy(session, "I buy the rope, but I haggle", haggle_rolls: %{"persuasion" => 1})
    assert before - copper(board) == 110
  end

  test "a hostile trader refuses the trade", %{session: session} do
    set_runtime(session.id, %{"relationship_score" => -4.0})
    board = buy(session, "I buy the rope", catalogue_v2: true)
    assert [%{"status" => "rejected", "code" => "npc_refused"}] = board.outcome["actions"]
    assert copper(board) == Inventory.coin_total_copper(session.world_state["character"]["coins"])
    assert %NPC.Person{} = Rows.get(session.id, "innkeep")
  end
end
