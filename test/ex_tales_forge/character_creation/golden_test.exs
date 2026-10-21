defmodule TalesForge.CharacterCreation.GoldenTest do
  @moduledoc """
  Characterization tests built from current outputs: `options/1` against a
  captured fixture, and a `FromText` reading of a messy reply field by field.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.CharacterCreation.FromText
  alias TalesForge.CharacterTextStub, as: Stub

  @fixture "test/support/fixtures/cc_options_tin_valley.exs"

  test "options/1 matches the captured output, field by field" do
    {expected, _} = Code.eval_file(@fixture)
    opts = CC.options("tin_valley")

    for key <-
          ~w(races classes occupations point_buy stat_roll skills skill_list name_max_length)a do
      assert Map.fetch!(opts, key) == Map.fetch!(expected, key), "options.#{key} changed"
    end

    for {race, i} <- Enum.with_index(expected.races) do
      got = Enum.at(opts.races, i)

      for key <- ~w(id description stats choice skill_bonus)a,
          do: assert(Map.fetch!(got, key) == Map.fetch!(race, key))
    end

    for {class, i} <- Enum.with_index(expected.classes) do
      got = Enum.at(opts.classes, i)

      for key <- ~w(id description stats skills occupation)a,
          do: assert(Map.fetch!(got, key) == Map.fetch!(class, key))
    end

    for {occ, i} <- Enum.with_index(expected.occupations) do
      got = Enum.at(opts.occupations, i)

      for key <- ~w(id description skills)a,
          do: assert(Map.fetch!(got, key) == Map.fetch!(occ, key))
    end
  end

  defp read(reply, answers \\ []) do
    Stub.put(reply)
    {:ok, reading} = FromText.read("tin_valley", "Someone.", answers)
    reading
  end

  defp label(reading, field), do: {reading.labels[field].value, reading.labels[field].confidence}

  test "a messy reply: trimmed, downcased, unknown and junk dropped, confidence clamped" do
    reply = %{
      "name" => %{"value" => "  Mira VALE ", "confidence" => 3},
      "race" => %{"value" => " ELF ", "confidence" => 0.7},
      "class" => %{"value" => "bard", "confidence" => 1.0},
      "occupation" => %{"value" => "", "confidence" => 0.9},
      "stats" => [
        %{"stat" => "DEX", "value" => 16},
        %{"stat" => "LUCK", "value" => 12},
        %{"stat" => "STR", "value" => "10"},
        "junk"
      ],
      "stats_confidence" => -1,
      "skills" => [
        %{"skill" => "stealth", "level" => 20},
        %{"skill" => "juggling", "level" => 10},
        %{"skill" => "survival", "level" => 0}
      ],
      "skills_confidence" => "high",
      "questions" => [" Who? ", "", 7, "Why?", "Where?"]
    }

    r = read(reply)

    assert Map.keys(r.labels) |> Enum.sort() ==
             ~w(class name occupation race skills stats)

    assert label(r, "name") == {"Mira VALE", 1.0}
    assert label(r, "race") == {"elf", 0.7}
    assert label(r, "class") == {"bard", 0.0}
    assert label(r, "occupation") == {"", 0.0}
    assert label(r, "stats") == {%{"DEX" => 16}, 0.0}
    assert label(r, "skills") == {%{"stealth" => 20}, 0.0}
    assert r.questions == ["Who?", "Why?"]
  end

  test "a reply without fields gives empty labels; answers mean no questions" do
    r = read(%{"questions" => ["Who?"]}, [{"Who?", "Mira"}])

    for f <- ~w(name race class occupation), do: assert(label(r, f) == {"", 0.0})
    assert label(r, "stats") == {%{}, 0.0}
    assert label(r, "skills") == {%{}, 0.0}
    assert r.questions == []
  end
end
