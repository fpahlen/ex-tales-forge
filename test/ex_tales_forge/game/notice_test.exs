defmodule TalesForge.Game.NoticeTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.Notice

  doctest Notice

  test "a front fact with a notice field needs the skill and the level" do
    world = %{
      "front_facts" => [
        %{
          "text" => "One pin is stuck.",
          "notice" => %{"skill" => "lockpicking", "min_level" => "high"}
        }
      ]
    }

    assert Notice.details(world, "lockpicking", :high) == ["One pin is stuck."]
    assert Notice.details(world, "lockpicking", :medium) == []
    assert Notice.details(world, "insight", :high) == []
  end

  test "only present NPCs give details, and no detail is made up" do
    world = %{
      "present_npcs" => [],
      "npc_profiles" => [%{"id" => "innkeep", "name" => "Brenna", "concern_focus" => "x"}]
    }

    assert Notice.details(world, "insight", :high) == []
    assert Notice.details(%{}, "insight", :high) == []
  end
end
