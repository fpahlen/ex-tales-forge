defmodule TalesForge.CharacterDraftsTest do
  use TalesForge.DataCase, async: true

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.CharacterDrafts

  test "put, get and delete one draft for each player and adventure" do
    {:ok, draft} =
      CC.new("tin_valley", seed_key: "s1") |> CC.choose_model("stat_roll", fn 6 -> 5 end)

    assert CharacterDrafts.get("wren", "tin_valley") == nil
    assert :ok = CharacterDrafts.put("wren", draft)
    assert CharacterDrafts.get("wren", "tin_valley") == draft
    assert CharacterDrafts.get("other", "tin_valley") == nil
    assert CharacterDrafts.get("wren", "crossroads_ledger") == nil

    {:ok, rerolled} = CC.reroll_stats(draft, fn 6 -> 2 end)
    assert :ok = CharacterDrafts.put("wren", rerolled)
    assert CharacterDrafts.get("wren", "tin_valley") == rerolled

    assert :ok = CharacterDrafts.delete("wren", "tin_valley")
    assert CharacterDrafts.get("wren", "tin_valley") == nil
  end
end
