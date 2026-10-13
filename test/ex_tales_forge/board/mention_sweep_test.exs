defmodule TalesForge.Board.MentionSweepTest do
  @moduledoc "The sweep wakes Case only when a founder's bot mention has no answer."
  use TalesForge.DataCase, async: false
  use Oban.Testing, repo: TalesForge.Repo

  alias TalesForge.Board.Workers.MentionSweep
  alias TalesForge.Board.Workers.MentionSweep.{Mention, Reply}

  doctest MentionSweep

  @now ~U[2026-10-13 08:00:00Z]

  defp mention(attrs) do
    struct!(
      Mention,
      Map.merge(
        %{
          id: "c1",
          place: "card1",
          bot: :bobby,
          author: "ada@x.se",
          at: ~U[2026-10-13 07:00:00Z]
        },
        attrs
      )
    )
  end

  test "a founder's mention with no reply is unanswered" do
    assert [_] = MentionSweep.unanswered([mention(%{})], [], @now)
  end

  test "a reply by the bot in the same place answers it" do
    reply = %Reply{place: "card1", author: "bot:bobby", at: ~U[2026-10-13 07:30:00Z]}
    assert MentionSweep.unanswered([mention(%{})], [reply], @now) == []
  end

  test "a reply in another place, by another bot, or before the mention answers nothing" do
    replies = [
      %Reply{place: "card2", author: "bot:bobby", at: ~U[2026-10-13 07:30:00Z]},
      %Reply{place: "card1", author: "bot:case", at: ~U[2026-10-13 07:30:00Z]},
      %Reply{place: "card1", author: "bot:bobby", at: ~U[2026-10-13 06:30:00Z]}
    ]

    assert [_] = MentionSweep.unanswered([mention(%{})], replies, @now)
  end

  test "a bot's mention and a mention younger than 15 minutes are not counted" do
    assert MentionSweep.unanswered([mention(%{author: "bot:case"})], [], @now) == []
    assert MentionSweep.unanswered([mention(%{at: ~U[2026-10-13 07:50:00Z]})], [], @now) == []
  end

  test "no job when the count is 0; one Case job with the list otherwise" do
    assert MentionSweep.job([]) == nil
    job = MentionSweep.job([mention(%{})])
    assert job.changes.args["bot"] == "case"
    assert job.changes.args["event"] == "mention.unanswered"
    assert job.changes.args["ids"] == ["c1"]
  end

  test "run/1 with no mentions adds no job" do
    assert {:ok, 0} = MentionSweep.run(DateTime.utc_now())
  end
end
