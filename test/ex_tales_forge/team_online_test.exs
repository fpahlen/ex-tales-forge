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
    # The most recently active bot first; bots with no activity last.
    assert Enum.map(bots, & &1.name) == ["Gentry", "Case", "Bobby"]
  end
end
