defmodule TalesForge.Board.ArchiveTest do
  use TalesForge.DataCase, async: false

  import ExUnit.CaptureLog

  require Logger

  alias TalesForge.Board
  alias TalesForge.Board.{Api, History, Ping}
  alias TalesForge.Repo

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0::64>>

  setup do
    {:ok, idea} =
      Board.create_idea("ada@example.com", %{"title" => "Spam card", "body" => "buy now"})

    {:ok, idea} = Board.vote(idea, "ada@example.com", 1)
    {:ok, idea} = Board.add_comment(idea, "ada@example.com", "A comment")
    %{idea: idea}
  end

  test "archive keeps votes, comments and history; restore goes back to Ideas", %{idea: idea} do
    assert {:error, "Write a short reason for the archive."} =
             Board.archive(idea, "ada@example.com", "  ")

    {:ok, a} = Board.archive(idea, "ada@example.com", "Duplicate of chat")
    assert a.column == "archived"
    assert length(a.votes) == 1 and length(a.comments) == 1

    info = Board.archived_info(a)
    assert info.by == "ada@example.com" and info.reason == "Duplicate of chat"

    # Not on the board, not in the ranking, not in stats columns.
    refute Enum.any?(Board.board() |> Map.values() |> List.flatten(), &(&1.id == idea.id))
    refute Enum.any?(Board.ranked_ideas(), &(&1.id == idea.id))
    assert [%{id: id}] = Board.archived()
    assert id == idea.id
    assert Board.archived_count() == 1
    assert Board.stats().totals.cards == 0

    {:ok, r} = Board.restore(a, "ada@example.com")
    assert r.column == "ideas"
    kinds = r |> then(&History.entries(Workflow.Team.Source.team(), &1)) |> Enum.map(& &1.kind)
    assert :archived in kinds and :restored in kinds
    texts = r |> then(&History.entries(Workflow.Team.Source.team(), &1)) |> Enum.map(& &1.text)
    assert "archived this card from Ideas" in texts
    assert "restored this card to Ideas" in texts
  end

  test "only Ideas and Parked cards archive; bots and QA cannot", %{idea: idea} do
    {:ok, idea} = Board.move(idea, {:founder, "ada@example.com"}, "refining")
    assert {:error, _} = Board.archive(idea, "ada@example.com", "x")
    {:ok, idea} = Board.move(idea, {:founder, "ada@example.com"}, "ideas")
    assert {:error, "A founder moves this card."} = Board.archive(idea, "bot:gentry", "x")

    assert {:error, msg} = Board.archive(idea, TalesForge.QaLogin.email(), "x")
    assert msg == TalesForge.QaLogin.refused_message()

    assert {422, %{"error" => "A founder moves this card."}} =
             Api.handle(:move, :case, %{"id" => idea.id, "to" => "archived", "note" => "x"})

    {:ok, p} = Board.move(idea, {:founder, "ada@example.com"}, "parked")
    assert {:ok, %{column: "archived"}} = Board.archive(p, "ada@example.com", "Spam")
  end

  test "a comment on an archived card adds no ping", %{idea: idea} do
    {:ok, a} = Board.archive(idea, "ada@example.com", "Old")
    before = Repo.aggregate(Ping, :count)
    {:ok, a} = Board.add_comment(a, "bo@example.com", "@fredrik @case still here?")
    assert Repo.aggregate(Ping, :count) == before
    assert length(a.comments) == 2
  end

  test "the bot API shows the state; the pull skips archived cards", %{idea: idea} do
    {:ok, _} = Board.archive(idea, "ada@example.com", "Spam")
    assert {200, %{"ideas" => []}} = Api.handle(:index, :case, %{})
    assert {200, %{"ideas" => []}} = Api.handle(:index, :case, %{"column" => "ideas"})
    assert {200, %{"ideas" => [card]}} = Api.handle(:index, :case, %{"column" => "archived"})
    assert card["state"] == "archived"
    assert card["archived"]["reason"] == "Spam"
    assert {200, %{"state" => "archived"}} = Api.handle(:show, :bobby, %{"id" => idea.id})
  end

  describe "delete" do
    test "a founder deletes an archived card with its images and an audit row", %{idea: idea} do
      {:ok, idea} = Board.add_images(idea, "ada@example.com", [@png], nil)
      assert length(idea.images) == 1

      assert {:error, "Archive the card first. Then you can delete it."} =
               Board.delete_archived(idea, "ada@example.com", "Spam card")

      {:ok, a} = Board.archive(idea, "ada@example.com", "Spam")

      assert {:error, "Type the title of the card to confirm the delete."} =
               Board.delete_archived(a, "ada@example.com", "Spam")

      level = Logger.level()
      Logger.configure(level: :notice)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        capture_log([level: :notice], fn ->
          assert :ok = Board.delete_archived(a, "ada@example.com", " spam CARD ")
        end)

      assert log =~ "deleted from the archive by ada@example.com with 1 image(s)"
      assert Board.get_idea(idea.id) == nil
      assert TalesForge.Images.for_idea(idea.id) == []

      assert [
               %{
                 title: "Spam card",
                 deleted_by: "ada@example.com",
                 image_count: 1,
                 archive_reason: "Spam"
               }
             ] =
               Board.deletions()
    end

    test "bots and the QA session cannot delete", %{idea: idea} do
      {:ok, a} = Board.archive(idea, "ada@example.com", "Spam")

      assert {:error, "Only a founder can delete a card."} =
               Board.delete_archived(a, "bot:bobby", "Spam card")

      assert {:error, _} = Board.delete_archived(a, TalesForge.QaLogin.email(), "Spam card")
      assert Board.get_idea(a.id)
      assert Board.deletions() == []
    end
  end
end
