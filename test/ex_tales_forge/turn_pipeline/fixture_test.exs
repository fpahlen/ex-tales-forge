defmodule TalesForge.TurnPipeline.FixtureTest do
  # This test checks the shape of the turn pipeline fixtures. It runs on main
  # now. The replay itself is in replay_test.exs and has the :pending tag.
  use ExUnit.Case, async: true

  alias TalesForge.Game.Mechanics

  @path "test/fixtures/turn_pipeline/items.jsonl"
  @items @path
         |> File.read!()
         |> String.split("\n", trim: true)
         |> Enum.map(&Jason.decode!/1)

  @categories ~w(gentry_regression issue_180 catalogue_v2 rules)
  # One key for each migration PR in design-turn-pipeline.md section 8, plus
  # the replay harness itself.
  @pending_keys ~w(replay_harness outcome_record premise_first state_from_mechanics
                   npc_memory catalogue_v2 clarification_v2 history_strip)
  @actions ~w(move observe interact speak combat use_item pickup drop buy sell trade
              spend train wait other freeform rest work equip give none_fits)

  test "ids are unique and use the tp- prefix" do
    ids = Enum.map(@items, & &1["id"])
    assert length(ids) == length(Enum.uniq(ids))
    assert Enum.all?(ids, &String.starts_with?(&1, "tp-"))
  end

  test "every item has the required keys and a known category" do
    for item <- @items do
      for key <-
            ~w(id category subsource split status pending_on description context turns labeller reviewed) do
        assert Map.has_key?(item, key), "#{item["id"]} has no #{key}"
      end

      assert item["category"] in @categories
      assert item["split"] == "tune"
      assert is_boolean(item["reviewed"])
    end
  end

  test "each category has at least 5 items" do
    counts = Enum.frequencies_by(@items, & &1["category"])
    assert Enum.all?(@categories, &(Map.get(counts, &1, 0) >= 5))
  end

  test "every item is pending and names the PRs that it waits for" do
    for item <- @items do
      assert item["status"] == "pending"
      assert "replay_harness" in item["pending_on"]
      assert Enum.all?(item["pending_on"], &(&1 in @pending_keys)), item["id"]
    end
  end

  test "a reused item gives credit" do
    for item <- Enum.filter(@items, &Map.has_key?(&1, "reused_from")) do
      assert item["credit"] =~ "Gentry", item["id"]
    end
  end

  test "every turn has text, 0 to 3 actions and an outcome" do
    for item <- @items, turn <- item["turns"] do
      assert is_binary(turn["text"]) and turn["text"] != ""
      actions = get_in(turn, ["expect", "intent", "actions"])
      assert length(actions) <= 3, item["id"]
      assert Enum.all?(actions, &(&1["action"] in @actions)), item["id"]
      assert is_map(get_in(turn, ["expect", "outcome"])), item["id"]
      assert is_integer(get_in(turn, ["expect", "post_check", "mismatches"])), item["id"]
    end
  end

  test "a rejected-only turn does not move the clock" do
    for item <- @items, turn <- item["turns"] do
      outcome = turn["expect"]["outcome"]

      if outcome["accepted"] == [] and outcome["rejected"] != [] do
        assert outcome["clock"] == "none", item["id"]
      end
    end
  end

  test "multi-turn subsources have more than 1 turn" do
    for item <- @items,
        item["subsource"] =~ "multi_turn" or item["subsource"] == "h_fa06_history_strip" do
      assert length(item["turns"]) > 1, item["id"]
    end
  end

  test "skill changes use the game's skill names" do
    valid = Mechanics.skill_stat_map() |> Map.keys()

    for item <- @items, turn <- item["turns"] do
      skills = turn["expect"]["outcome"]["skill_changes"] |> Map.keys()
      assert Enum.all?(skills, &(&1 in valid)), item["id"]
    end
  end
end
