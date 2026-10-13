defmodule TalesForge.WorkLog.AuthorsTest do
  @moduledoc """
  Work log PR 1: a card text edit stores its author and time, and a played
  turn stores the founder who played it.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Board.Edit
  alias TalesForge.Game.{Context, Intent, TurnProcessor}
  alias TalesForge.Game.Schemas.PlayerAction
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.Schemas.Turn
  alias TalesForge.Workflow.Repo, as: WorkflowRepo

  @founder "hawk@example.com"

  describe "card text edits" do
    test "refine/3 writes one edit row with the author and the changed fields" do
      {:ok, idea} = Board.create_idea(@founder, %{"title" => "Edit log card"})
      {:ok, idea} = Board.vote(idea, @founder, 1)
      {:ok, idea} = Board.move(idea, {:founder, @founder}, "refining")

      {:ok, _} = Board.refine(idea, %{"details" => "First text", "rough_cost" => "S"}, @founder)

      assert [%Edit{author: @founder, fields: ["details", "rough_cost"], inserted_at: at}] =
               WorkflowRepo.all(Edit)

      assert %DateTime{} = at
      assert [%Edit{}] = Board.edits_since(DateTime.add(at, -1))
    end

    test "refine/2 records Case as the author" do
      {:ok, idea} = Board.create_idea(@founder, %{"title" => "Case edit card"})
      {:ok, idea} = Board.vote(idea, @founder, 1)
      {:ok, idea} = Board.move(idea, {:founder, @founder}, "refining")
      {:ok, _} = Board.refine(idea, %{"details" => "Case text"})

      assert [%Edit{author: "bot:case", fields: ["details"]}] = WorkflowRepo.all(Edit)
    end

    test "a refused refinement writes no edit row" do
      {:ok, idea} = Board.create_idea(@founder, %{"title" => "Bad edit card"})
      {:ok, idea} = Board.vote(idea, @founder, 1)
      {:ok, idea} = Board.move(idea, {:founder, @founder}, "refining")
      assert {:error, _} = Board.refine(idea, %{"rough_cost" => "XL"}, @founder)
      assert WorkflowRepo.all(Edit) == []
    end
  end

  describe "game turns" do
    setup do
      on_exit(fn ->
        for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
        System.delete_env("LLM_PROVIDER")
        System.delete_env("XAI_API_KEY")
      end)

      System.put_env("LLM_PROVIDER", "xai")
      System.put_env("XAI_API_KEY", "test-key")

      Req.Test.stub(TalesForge.LLM, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{"message" => %{"role" => "assistant", "content" => ~s({"narrative":"Ok."})}}
          ],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 4}
        })
      end)

      {:ok, session} = GameSessions.create_session(%{name: "Founder turn"})
      context = Context.build_intent_context(session)

      action =
        "look around"
        |> Intent.heuristic_intent(context)
        |> Intent.validate_player_action(context)
        |> PlayerAction.encode()

      %{session: session, action: action}
    end

    test "the turn row stores the founder", %{session: session, action: action} do
      assert {:ok, _} = TurnProcessor.run(session.id, "look around", action, founder: @founder)
      assert [%Turn{founder: @founder, id: id}] = Repo.all(Turn)

      assert [%TalesForge.WorkLog.Event{kind: "turn", ref: ^id}] =
               WorkflowRepo.all(TalesForge.WorkLog.Event)
    end

    test "a turn without a founder stores nil", %{session: session, action: action} do
      assert {:ok, _} = TurnProcessor.run(session.id, "look around", action)
      assert [%Turn{founder: nil}] = Repo.all(Turn)
      assert WorkflowRepo.all(TalesForge.WorkLog.Event) == []
    end
  end
end
