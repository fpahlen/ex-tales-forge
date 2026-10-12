defmodule TalesForge.WorkLog.SessionsTest do
  use ExUnit.Case, async: true

  alias TalesForge.WorkLog.Sessions

  doctest Sessions

  @t ~U[2026-10-12 10:00:00Z]

  defp ev(founder, minutes, kind \\ "chat"),
    do: %{founder: founder, kind: kind, at: DateTime.add(@t, round(minutes * 60))}

  test "the session ends at the last action; the idle gap does not count" do
    [s1, s2] = Sessions.build([ev("a@x", 0), ev("a@x", 14), ev("a@x", 28), ev("a@x", 43)])
    assert {s1.seconds, s1.actions} == {28 * 60, 3}
    assert s1.ended_at == DateTime.add(@t, 28 * 60)
    assert {s2.seconds, s2.actions} == {0, 1}
  end

  test "a gap of exactly 15 minutes closes the session" do
    assert length(Sessions.build([ev("a@x", 0), ev("a@x", 15)])) == 2
    assert length(Sessions.build([ev("a@x", 0), ev("a@x", 14.9)])) == 1
  end

  test "each founder gets separate sessions and the action types" do
    sessions =
      Sessions.build([
        ev("a@x", 0, "turn"),
        ev("b@x", 1, "move"),
        ev("a@x", 5, "comment"),
        ev("a@x", 6, "turn")
      ])

    assert [%{founder: "a@x", kinds: ["comment", "turn"], seconds: 360}, %{founder: "b@x"}] =
             sessions
  end

  test "the input order does not matter" do
    assert Sessions.build([ev("a@x", 10), ev("a@x", 0)]) ==
             Sessions.build([ev("a@x", 0), ev("a@x", 10)])
  end
end
