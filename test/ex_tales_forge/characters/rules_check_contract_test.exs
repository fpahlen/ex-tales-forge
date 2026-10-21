defmodule TalesForge.Characters.RulesCheckContractTest do
  @moduledoc """
  Characterization tests: every rule the two rule validators apply today
  (`Defaults` on the label tables, `CharacterCreation` on `creation.json`),
  each with its exact error message. A refactor of the validators must keep
  these passing unchanged.
  """
  use ExUnit.Case, async: true

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.Characters.Defaults

  @labels Defaults.rules()
  @creation Path.join([:code.priv_dir(:ex_tales_forge), "characters", "creation.json"])
            |> File.read!()
            |> Jason.decode!()

  @occ %{
    "core" => ["tracking"],
    "secondary" => [],
    "ocean" => %{},
    "maslow" => "safety",
    "concerns" => []
  }

  defp extend(pack), do: Defaults.extend_rules!(@labels, pack, "p")
  defp occupation(changes), do: extend(%{"occupations" => %{"x" => Map.merge(@occ, changes)}})
  defp creation(path, value), do: CC.check_rules!(@labels, put_in(@creation, path, value))

  describe "label tables (Defaults)" do
    test "the shipped base and pack rules pass" do
      assert is_map(Defaults.rules())
      assert is_map(Defaults.rules("tin_valley"))
      assert occupation(%{})["occupations"]["x"]
    end

    test "occupation core and secondary skills must be known" do
      msg = ~s(character defaults occupation x: unknown skills ["juggling"])
      assert_raise ArgumentError, msg, fn -> occupation(%{"core" => ["juggling"]}) end
      assert_raise ArgumentError, msg, fn -> occupation(%{"secondary" => ["juggling"]}) end
    end

    test "occupation OCEAN traits, Maslow level and concerns must be known" do
      assert_raise ArgumentError,
                   ~s(character defaults occupation x: unknown OCEAN traits ["charm"]),
                   fn -> occupation(%{"ocean" => %{"charm" => 1}}) end

      assert_raise ArgumentError,
                   ~s(character defaults occupation x: unknown Maslow level "wealth"),
                   fn -> occupation(%{"maslow" => "wealth"}) end

      assert_raise ArgumentError,
                   ~s(character defaults occupation x: unknown concern focus "boredom"),
                   fn -> occupation(%{"concerns" => [%{"focus" => "boredom", "text" => "t"}]}) end

      assert_raise ArgumentError,
                   ~s(character defaults occupation x: bad concern %{"focus" => "food"}),
                   fn -> occupation(%{"concerns" => [%{"focus" => "food"}]}) end
    end

    test "class skills and stats must be known" do
      class = %{"skills" => ["tracking"], "stats" => %{}}

      assert_raise ArgumentError,
                   ~s(character defaults class x: unknown skills ["juggling"]),
                   fn ->
                     extend(%{"classes" => %{"x" => %{class | "skills" => ["juggling"]}}})
                   end

      assert_raise ArgumentError, ~s(character defaults class x: unknown stats ["LUCK"]), fn ->
        extend(%{"classes" => %{"x" => %{class | "stats" => %{"LUCK" => 1}}}})
      end
    end

    test "race stats and OCEAN traits must be known" do
      race = %{"stats" => %{}, "ocean" => %{}}

      assert_raise ArgumentError, ~s(character defaults race x: unknown stats ["LUCK"]), fn ->
        extend(%{"races" => %{"x" => %{race | "stats" => %{"LUCK" => 1}}}})
      end

      assert_raise ArgumentError,
                   ~s(character defaults race x: unknown OCEAN traits ["charm"]),
                   fn -> extend(%{"races" => %{"x" => %{race | "ocean" => %{"charm" => 1}}}}) end
    end

    test "a standing's Maslow floor and concern must be known; both are optional" do
      assert extend(%{"standings" => %{"x" => %{}}})["standings"]["x"] == %{}

      assert_raise ArgumentError,
                   ~s(character defaults standing x: unknown Maslow level "wealth"),
                   fn -> extend(%{"standings" => %{"x" => %{"maslow_floor" => "wealth"}}}) end

      assert_raise ArgumentError,
                   ~s(character defaults standing x: unknown concern focus "boredom"),
                   fn ->
                     concern = %{"focus" => "boredom", "text" => "t"}
                     extend(%{"standings" => %{"x" => %{"concern" => concern}}})
                   end
    end
  end

  describe "creation.json against the labels (CharacterCreation)" do
    test "the shipped creation.json passes, also against the Tin Valley labels" do
      assert CC.check_rules!(@labels, @creation) == :ok
      assert CC.check_rules!(Defaults.rules("tin_valley"), @creation) == :ok
    end

    test "race choices must name a known race and known stats (values and replaces keys)" do
      choice = %{"count" => 1, "amount" => 1, "from" => ["INT"], "replaces" => %{}}

      assert_raise ArgumentError, ~s(creation.json: race_choices for unknown race "orc"), fn ->
        creation(["race_choices", "orc"], choice)
      end

      assert_raise ArgumentError, ~s(creation.json: unknown stats ["LUCK"] for elf), fn ->
        creation(["race_choices", "elf"], %{choice | "from" => ["INT", "LUCK"]})
      end

      assert_raise ArgumentError, ~s(creation.json: unknown stats ["LUCK"] for elf), fn ->
        creation(["race_choices", "elf"], %{choice | "replaces" => %{"LUCK" => 1}})
      end

      # Duplicates are listed as often as they appear.
      assert_raise ArgumentError, ~s(creation.json: unknown stats ["LUCK", "LUCK"] for elf), fn ->
        creation(["race_choices", "elf"], %{choice | "from" => ["LUCK", "LUCK"]})
      end
    end

    test "occupation choices and class defaults must be known occupations" do
      choices = @creation["occupation"]["choices"]

      assert_raise ArgumentError, ~s(creation.json: unknown occupation "wizard_king"), fn ->
        creation(["occupation", "choices"], choices ++ ["wizard_king"])
      end

      assert_raise ArgumentError, ~s(creation.json: unknown occupation "wizard_king"), fn ->
        creation(["occupation", "class_defaults", "none"], "wizard_king")
      end
    end

    test "a class default must name a known class and an offered occupation" do
      assert_raise ArgumentError, "creation.json: bad class default bard => laborer", fn ->
        creation(["occupation", "class_defaults", "bard"], "laborer")
      end

      # "prospector" is a Tin Valley occupation, not in choices.
      assert_raise ArgumentError, "creation.json: bad class default none => prospector", fn ->
        CC.check_rules!(
          Defaults.rules("tin_valley"),
          put_in(@creation, ["occupation", "class_defaults", "none"], "prospector")
        )
      end
    end

    test "every label class needs a default occupation, also a pack's class" do
      defaults = Map.delete(@creation["occupation"]["class_defaults"], "druid")

      assert_raise ArgumentError, ~s(creation.json: no default occupation for ["druid"]), fn ->
        creation(["occupation", "class_defaults"], defaults)
      end

      labels =
        Defaults.extend_rules!(
          @labels,
          %{"classes" => %{"bard" => %{"skills" => [], "stats" => %{}}}},
          "p"
        )

      assert_raise ArgumentError, ~s(creation.json: no default occupation for ["bard"]), fn ->
        CC.check_rules!(labels, @creation)
      end
    end

    test "race skill bonuses must name a known race and known fixed skills" do
      assert_raise ArgumentError, ~s(creation.json: skill bonus for unknown race "orc"), fn ->
        creation(["skills", "race_bonuses", "orc"], %{"pool" => 5})
      end

      assert_raise ArgumentError, ~s(creation.json: unknown skills ["juggling"] for elf), fn ->
        creation(["skills", "race_bonuses", "elf"], %{"fixed" => %{"juggling" => 5}})
      end

      # Only "fixed" keys are checked.
      assert creation(["skills", "race_bonuses", "elf"], %{"pool" => 5, "other" => 1}) == :ok
    end
  end
end
