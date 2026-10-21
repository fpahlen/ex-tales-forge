defmodule TalesForge.CharacterCreation.PackClassesTest do
  @moduledoc """
  A pack may add a class when it also gives the class a default past
  occupation (`class_defaults` in its `character_defaults.json`).
  """
  # Writes a pack into priv/adventures for the test, so not async.
  use ExUnit.Case, async: false

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.Characters.Defaults

  @fixtures "test/support/fixtures/packs"

  # Installs fixture `name` as the character_defaults.json of a throwaway adventure.
  defp install(name) do
    id = "zz_test_pack_#{System.unique_integer([:positive])}"
    dir = Path.join([:code.priv_dir(:ex_tales_forge), "adventures", id])
    File.mkdir_p!(dir)
    File.cp!(Path.join(@fixtures, name <> ".json"), Path.join(dir, "character_defaults.json"))
    on_exit(fn -> File.rm_rf!(dir) end)
    id
  end

  test "a pack class with a pack default passes and is offered with that default" do
    id = install("bard_with_default")

    assert CC.rules(id)["creation"]["occupation"]["class_defaults"]["bard"] == "innkeep"

    assert %{id: "bard", occupation: "innkeep"} =
             Enum.find(CC.options(id).classes, &(&1.id == "bard"))

    {:ok, draft} = CC.choose_class(CC.new(id, seed_key: "bard-1"), "bard")
    assert draft.occupation == "innkeep"
  end

  test "a pack class with no default anywhere raises the existing message" do
    id = install("bard_without_default")

    assert_raise ArgumentError, ~s(creation.json: no default occupation for ["bard"]), fn ->
      CC.rules(id)
    end
  end

  test "a pack may not set the default of a base class" do
    assert_raise ArgumentError, ~s(p: cannot redefine base class_defaults ["ranger"]), fn ->
      Defaults.extend_rules!(Defaults.rules(), %{"class_defaults" => %{"ranger" => "guard"}}, "p")
    end
  end

  test "the shipped adventures are unchanged" do
    refute Map.has_key?(Defaults.rules("tin_valley"), "class_defaults")

    assert CC.rules("tin_valley")["creation"]["occupation"]["class_defaults"]["ranger"] ==
             "hunter"
  end
end
