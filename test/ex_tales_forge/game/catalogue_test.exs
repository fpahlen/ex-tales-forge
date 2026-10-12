defmodule TalesForge.Game.CatalogueTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.Catalogue

  test "manner changes time and roll; speak has no modifier" do
    assert %{time: 0.5, roll: -2} = Catalogue.manner("quickly", "wait")
    assert %{time: 1.5, roll: 2} = Catalogue.manner("carefully", "skill_check")
    assert %{time: 1.0, roll: 0} = Catalogue.manner("quickly", "speak")
  end

  test "scale_ticks keeps at least one tick" do
    assert Catalogue.scale_ticks(4, %{time: 0.5}) == 2
    assert Catalogue.scale_ticks(1, %{time: 0.5}) == 1
  end

  test "refuses_gift? needs low agreeableness and no relationship" do
    assert Catalogue.refuses_gift?(%{
             "personality_traits" => %{"agreeableness" => 2},
             "relationship_score" => 0
           })

    refute Catalogue.refuses_gift?(%{"personality_traits" => %{"agreeableness" => 5}})
  end
end
