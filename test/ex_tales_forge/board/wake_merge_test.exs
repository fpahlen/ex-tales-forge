defmodule TalesForge.Board.WakeMergeTest do
  use ExUnit.Case, async: true

  alias TalesForge.Board.WakeMerge

  doctest WakeMerge

  @now ~U[2026-10-13 08:00:00Z]

  test "the first wake goes out" do
    assert WakeMerge.wake?(nil, @now)
  end

  test "a second wake within 2 minutes merges into the first" do
    refute WakeMerge.wake?(DateTime.add(@now, -1), @now)
    refute WakeMerge.wake?(DateTime.add(@now, -119), @now)
  end

  test "a wake 2 minutes or more after the last one goes out" do
    assert WakeMerge.wake?(DateTime.add(@now, -120), @now)
    assert WakeMerge.wake?(DateTime.add(@now, -3600), @now)
  end
end
