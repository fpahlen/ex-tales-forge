defmodule TalesForge.Game.ProgressionTest do
  use ExUnit.Case, async: true

  alias TalesForge.Game.Progression

  doctest Progression

  # Levels on the d100 scale. Rolls are injected; `{roll, gain}` fixes the 1d6+1 gain.
  @character %{
    "skills" => %{"climbing" => 15, "stealth" => 35},
    "learning_points" => %{},
    "learning_failures" => %{}
  }

  describe "resolve_rest/3" do
    test "rolls until the first success: one gain at most, then every LP of the skill is gone" do
      character = put_in(@character, ["learning_points", "climbing"], 3.0)

      {rested, attempts, []} =
        Progression.resolve_rest(character, %{"climbing" => [20, {51, 5}, 100]})

      assert Enum.map(attempts, &{&1["roll"], &1["improved"]}) == [{20, false}, {51, true}]
      assert List.last(attempts)["gain"] == 5
      assert List.last(attempts)["lp_cleared"] == 1
      assert rested["skills"]["climbing"] == 20
      assert rested["learning_points"]["climbing"] == 0.0
    end

    test "the gain is 1d6+1 (2 to 7) when no gain is injected" do
      character = put_in(@character, ["learning_points", "climbing"], 1.0)
      {rested, [attempt], []} = Progression.resolve_rest(character, %{"climbing" => 90})

      assert attempt["improved"]
      assert attempt["gain"] in 2..7
      assert rested["skills"]["climbing"] == 15 + attempt["gain"]
    end

    test "the gain never takes a skill past 100" do
      character = %{"skills" => %{"stealth" => 97}, "learning_points" => %{}}
      {trained, entry} = Progression.train(character, "stealth", %{"stealth" => {80, 7}})
      assert trained["skills"]["stealth"] == 100
      assert entry["gain"] == 3
    end

    test "when every roll fails the LP are gone too: nothing carries over" do
      character = put_in(@character, ["learning_points", "climbing"], 2.0)

      {rested, attempts, []} = Progression.resolve_rest(character, %{"climbing" => [1, 50]})

      assert Enum.map(attempts, & &1["improved"]) == [false, false]
      assert List.last(attempts)["lp_cleared"] == 0
      assert rested["skills"]["climbing"] == 15
      assert rested["learning_points"]["climbing"] == 0.0
    end

    test "higher levels need more LP per roll; too few for one roll are dropped" do
      # stealth 35 costs ceil(35 / 15) = 3 LP per roll: 7 LP buy two rolls, 2 LP buy none
      seven = put_in(@character, ["learning_points", "stealth"], 7.0)
      {_r, attempts, []} = Progression.resolve_rest(seven, %{"stealth" => [1, 2]})
      assert Enum.map(attempts, & &1["lp_spent"]) == [3, 3]
      assert List.last(attempts)["lp_cleared"] == 1

      two = put_in(@character, ["learning_points", "stealth"], 2.0)
      {rested, [], []} = Progression.resolve_rest(two, %{"stealth" => 100})
      assert rested["learning_points"]["stealth"] == 0.0
      assert rested["skills"]["stealth"] == 35
    end

    test "from level 50 the LP stay banked unless the character reflected on the skill" do
      character =
        @character
        |> put_in(["skills", "stealth"], 50)
        |> put_in(["learning_points", "stealth"], 4.0)

      {kept, [], ["stealth"]} = Progression.resolve_rest(character, %{"stealth" => {90, 2}})
      assert kept["learning_points"]["stealth"] == 4.0
      assert kept["skills"]["stealth"] == 50

      {rested, [attempt], []} =
        Progression.resolve_rest(character, %{"stealth" => {90, 2}}, reflected: ["stealth"])

      assert {attempt["improved"], attempt["lp_spent"]} == {true, 4}
      assert {rested["skills"]["stealth"], rested["learning_points"]["stealth"]} == {52, 0.0}
    end

    test "skills are resolved independently, in alphabetical order" do
      character = put_in(@character, ["learning_points"], %{"stealth" => 3, "climbing" => 1})

      {rested, attempts, []} =
        Progression.resolve_rest(character, %{"climbing" => {60, 2}, "stealth" => {60, 3}})

      assert Enum.map(attempts, &{&1["skill"], &1["improved"]}) ==
               [{"climbing", true}, {"stealth", true}]

      assert rested["skills"] == %{"climbing" => 17, "stealth" => 38}
    end

    test "only: resolves just the listed skills; an empty list resolves nothing" do
      character = put_in(@character, ["learning_points"], %{"stealth" => 3, "climbing" => 1})

      {rested, attempts, []} =
        Progression.resolve_rest(character, %{"climbing" => 100}, only: ["climbing"])

      assert Enum.map(attempts, & &1["skill"]) == ["climbing"]
      assert rested["learning_points"]["stealth"] == 3

      assert Progression.resolve_rest(character, %{}, only: []) == {character, [], []}
    end

    test "an untrained skill (level 0) needs a roll of 51 like any other" do
      character = put_in(@character, ["learning_points", "tracking"], 2.0)
      {rested, attempts, []} = Progression.resolve_rest(character, %{"tracking" => [1, 50]})

      assert Enum.map(attempts, &{&1["raw_skill"], &1["improved"]}) == [{0, false}, {0, false}]
      assert Map.get(rested["skills"], "tracking") == nil
    end

    test "LP stored as strings or integers count; a sheet without LP resolves nothing" do
      character = put_in(@character, ["learning_points"], %{"climbing" => "1.0", "stealth" => 3})

      {_r, attempts, []} =
        Progression.resolve_rest(character, %{"climbing" => 100, "stealth" => 100})

      assert length(attempts) == 2

      assert Progression.resolve_rest(%{"skills" => %{}}) == {%{"skills" => %{}}, [], []}
    end

    test "random rolls stay within 1..100 once the injected list runs out" do
      character = put_in(@character, ["learning_points", "climbing"], 3.0)
      {_r, attempts, []} = Progression.resolve_rest(character, %{"climbing" => [1]})

      assert length(attempts) in 1..3
      assert Enum.all?(attempts, &(&1["roll"] in 1..100))
    end
  end

  describe "train/3" do
    test "a free attempt: no LP spent, +25 on the roll" do
      character =
        @character
        |> put_in(["skills", "stealth"], 80)
        |> put_in(["learning_points", "stealth"], 0.5)

      {hit, hit_entry} = Progression.train(character, "stealth", %{"stealth" => {55, 4}})
      {miss, miss_entry} = Progression.train(character, "stealth", %{"stealth" => 54})

      assert {hit_entry["improved"], hit["skills"]["stealth"]} == {true, 84}
      assert {miss_entry["improved"], miss["skills"]["stealth"]} == {false, 80}
      assert hit["learning_points"]["stealth"] == 0.5
      assert hit_entry["bonus"] == 25
    end

    test "the trainer's +25 counts toward the floor of 51 too" do
      character = put_in(@character, ["skills", "stealth"], 10)
      {hit, _} = Progression.train(character, "stealth", %{"stealth" => {26, 2}})
      {miss, _} = Progression.train(character, "stealth", %{"stealth" => 25})

      assert {hit["skills"]["stealth"], miss["skills"]["stealth"]} == {12, 10}
    end
  end

  test "success chance is (101 - max(level, 51)) / 100: at most a coin flip" do
    assert Enum.map([0, 15, 51, 56, 76, 96, 100], &Progression.success_chance/1) ==
             [0.5, 0.5, 0.5, 0.45, 0.25, 0.05, 0.01]
  end

  test "LP per roll is ceil(level / 15), at least 1" do
    assert Enum.map([0, 5, 15, 16, 45, 46, 60, 61, 100], &Progression.lp_per_roll/1) ==
             [1, 1, 1, 2, 3, 4, 4, 5, 7]
  end

  test "a long rest is six hours or more" do
    assert Progression.long_rest?(24)
    refute Progression.long_rest?(23)
  end
end
