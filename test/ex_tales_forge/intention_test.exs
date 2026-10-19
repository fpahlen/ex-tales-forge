defmodule TalesForge.IntentionTest do
  use ExUnit.Case, async: true

  doctest TalesForge.Intention
  doctest TalesForge.Game.Turn.Intentions
  doctest TalesForge.Game.NpcReactions
end
