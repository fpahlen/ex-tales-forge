defmodule TalesForge.CharacterCreation.PackClassesTest do
  @moduledoc """
  A pack may add a class when it also gives the class a default past
  occupation (`class_defaults` in its `character_defaults.json`), and may
  override a base class's default.
  """
  # Writes a pack into priv/adventures for the test, so not async.
  use ExUnit.Case, async: false

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.Characters.{Defaults, PackRules}

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

  test "a pack may override a base class's default; the pack's default wins" do
    id = install("ranger_guard_default")

    assert %{occupation: "guard"} = Enum.find(CC.options(id).classes, &(&1.id == "ranger"))
    assert %{occupation: "hunter"} = Enum.find(CC.options(id).classes, &(&1.id == "druid"))

    {:ok, draft} = CC.choose_class(CC.new(id, seed_key: "ranger-1"), "ranger")
    assert draft.occupation == "guard"
  end

  test "a pack default must still be an offered occupation" do
    assert_raise ArgumentError, "creation.json: bad class default ranger => prospector", fn ->
      labels =
        Defaults.extend_rules!(
          Defaults.rules("tin_valley"),
          %{"class_defaults" => %{"ranger" => "prospector"}},
          "p"
        )

      creation = Path.join([:code.priv_dir(:ex_tales_forge), "characters", "creation.json"])

      creation
      |> File.read!()
      |> Jason.decode!()
      |> PackRules.with_class_defaults(labels)
      |> then(&TalesForge.Characters.RulesCheck.creation!(labels, &1))
    end
  end

  test "the shipped adventures are unchanged" do
    refute Map.has_key?(Defaults.rules("tin_valley"), "class_defaults")

    assert CC.rules("tin_valley")["creation"]["occupation"]["class_defaults"]["ranger"] ==
             "hunter"
  end
end
