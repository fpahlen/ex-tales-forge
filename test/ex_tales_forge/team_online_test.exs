defmodule TalesForge.TeamOnlineTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  alias TalesForge.TeamOnline

  doctest TalesForge.TeamOnline

  test "the bots' board actions show as their latest activity" do
    {:ok, idea} =
      Board.create_idea("ada@example.com", %{"title" => "Brenna", "body" => "A sentence."})

    {:ok, _} = Board.add_comment(idea, "bot:gentry", "Checked on a phone.")

    %{bots: bots} = TeamOnline.snapshot()
    gentry = Enum.find(bots, &(&1.id == "gentry"))

    assert gentry.doing == "Commented on a card"
    assert gentry.online
    # The most recently active bot comes first. The order of the other bots
    # depends on their activity outside this test (other tests and caches),
    # so the test checks them as a set.
    assert [%{name: "Gentry"} | others] = bots
    assert others |> Enum.map(& &1.name) |> Enum.sort() == ["Bobby", "Case"]
  end
end
