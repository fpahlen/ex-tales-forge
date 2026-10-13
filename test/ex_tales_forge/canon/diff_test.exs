defmodule TalesForge.Canon.DiffTest do
  use ExUnit.Case, async: true

  alias TalesForge.Canon.{Diff, Seed, SessionSnapshot}

  @seed %Seed{
    adventure_id: "test_pack",
    places: %{
      "inn" => %{name: "The Inn", exits: ["square"]},
      "square" => %{name: "Square", exits: ["inn"]}
    },
    entities: %{
      "brenna" => %{kind: :npc, name: "Brenna", facts: ["brenna keeps the inn."]},
      "inn" => %{kind: :location, name: "The Inn", facts: []}
    }
  }

  defp session(attrs) do
    struct(
      %SessionSnapshot{
        session_id: "s1",
        places: %{
          "inn" => %{"name" => "The Inn", "exits" => ["square"]},
          "square" => %{"name" => "Square", "exits" => ["inn"]}
        },
        npc_ids: ["brenna"]
      },
      attrs
    )
  end

  test "a session that matches its seed has no differences" do
    assert Diff.diff(session(%{}), @seed) == []
  end

  test "a fact that the seed holds gives no difference, also with other case and spaces" do
    facts = %{"brenna" => [%{"kind" => "fact", "text" => "Brenna  keeps the INN."}]}
    assert Diff.diff(session(%{facts: facts}), @seed) == []
  end

  test "a new place and a changed place give one difference each" do
    places = %{
      "inn" => %{"name" => "The Old Inn", "exits" => ["square", "cellar"]},
      "square" => %{"name" => "Square", "exits" => ["inn"]},
      "cellar" => %{"name" => "Cellar", "exits" => ["inn"]}
    }

    [new, changed] = Diff.diff(session(%{places: places}), @seed)

    assert new.kind == :new_place
    assert new.entity_id == "cellar"
    assert new.session == %{"name" => "Cellar", "exits" => ["inn"]}

    assert changed.kind == :changed_place
    assert changed.entity_id == "inn"
    assert changed.seed == %{"name" => "The Inn", "exits" => ["square"]}
    assert changed.summary =~ "The Old Inn"
  end

  test "an NPC that the seed does not have is a new entity" do
    [d] = Diff.diff(session(%{npc_ids: ["brenna", "tom"], npc_names: %{"tom" => "Tom"}}), @seed)

    assert d.kind == :new_entity
    assert d.entity_id == "tom"
    assert d.session == %{"name" => "Tom"}
  end

  test "a typed fact on a known entity is a new fact, and an unknown entity gives free text" do
    facts = %{
      "inn" => [
        %{"kind" => "price", "text" => "Ale costs 2c.", "turn" => 3, "source" => "narration"}
      ],
      "ghost_ship" => [%{"kind" => "fact", "text" => "A ship sails over the hills."}]
    }

    [fact, free] = Diff.diff(session(%{facts: facts}), @seed)

    assert fact.kind == :new_fact
    assert fact.session == %{"kind" => "price", "text" => "Ale costs 2c.", "turn" => 3}
    assert free.kind == :free_text
    assert free.entity_id == "ghost_ship"
    assert free.label == nil
  end

  test "the same difference gets the same key on each run, and other data gets another key" do
    facts = %{"inn" => [%{"kind" => "fact", "text" => "The roof leaks."}]}
    [a] = Diff.diff(session(%{facts: facts}), @seed)
    [b] = Diff.diff(session(%{facts: facts}), @seed)
    other = %{"inn" => [%{"kind" => "fact", "text" => "The roof is new."}]}
    [c] = Diff.diff(session(%{facts: other}), @seed)

    assert a.key == b.key
    assert a.key != c.key
  end
end
