defmodule TalesForge.Board.StuckCardsTest do
  @moduledoc "Building cards with no PR after 1 hour get one fixed reminder comment."
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.Board.Workers.StuckCards

  doctest StuckCards

  @ada "ada@example.com"

  defp building!(title, pr) do
    {:ok, idea} = Board.create_idea(@ada, %{"title" => title})
    {:ok, idea} = Board.vote(idea, @ada, 1)
    {:ok, idea} = Board.move(idea, {:founder, @ada}, "refining")

    {:ok, idea} =
      Board.refine(idea, %{"open_questions" => [], "rough_cost" => "S", "verdict" => "feasible"})

    {:ok, idea} = Board.move(idea, {:bot, :case}, "check")
    {:ok, idea} = Board.move(idea, {:founder, @ada}, "building")

    if pr do
      {:ok, idea} =
        Board.add_link(idea, "bot:bobby", %{
          "kind" => "pr",
          "url" => "https://github.com/whyse-ab/ex-tales-forge/pull/#{pr}"
        })

      idea
    else
      idea
    end
  end

  defp reminders(id) do
    Board.get_idea!(id).comments
    |> Enum.filter(&(&1.author == "bot:board" and &1.body == StuckCards.text()))
    |> length()
  end

  test "reminds a Building card with no PR after 1 hour, once" do
    stuck = building!("No PR", nil)
    linked = building!("Has a PR", 7)
    later = DateTime.add(DateTime.utc_now(), 3601)

    assert {:ok, [id]} = StuckCards.run(later)
    assert id == stuck.id
    assert {:ok, []} = StuckCards.run(DateTime.add(later, 3600))
    assert reminders(stuck.id) == 1
    assert reminders(linked.id) == 0
  end

  test "a card in Building for less than 1 hour gets no reminder" do
    building!("Fresh", nil)
    assert {:ok, []} = StuckCards.run(DateTime.utc_now())
  end

  test "the text names no bot and no person" do
    refute StuckCards.text() =~ "@"
  end
end
