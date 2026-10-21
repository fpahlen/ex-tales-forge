defmodule TalesForge.Canon.Diff do
  @moduledoc """
  The pure diff of one session against its seed.

  `diff/2` compares places, entity ids and typed `world_fact` rows. It reads
  no files and no database, and it calls no model. Facts on an entity that
  neither side knows become `:free_text` differences, and
  `TalesForge.Canon.Classifier` labels them later.
  """

  alias TalesForge.Canon.{Difference, Seed, SessionSnapshot}

  @doc "Returns the differences, sorted by kind and then by entity id."
  @spec diff(SessionSnapshot.t(), Seed.t()) :: [Difference.t()]
  def diff(%SessionSnapshot{} = session, %Seed{} = seed) do
    (places(session, seed) ++ entities(session, seed) ++ facts(session, seed))
    |> Enum.sort_by(&{kind_rank(&1.kind), &1.entity_id, &1.key})
  end

  defp places(session, seed) do
    session.places
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {id, loc} ->
      now = Seed.place(loc)

      case Map.fetch(seed.places, id) do
        :error ->
          [
            Difference.new(%Difference{
              kind: :new_place,
              entity_id: id,
              summary: "New place: #{now.name || id}",
              session: place_map(now)
            })
          ]

        {:ok, ^now} ->
          []

        {:ok, before} ->
          [
            Difference.new(%Difference{
              kind: :changed_place,
              entity_id: id,
              summary: changed_summary(id, before, now),
              seed: place_map(before),
              session: place_map(now)
            })
          ]
      end
    end)
  end

  defp changed_summary(id, before, now) do
    parts =
      [
        before.name != now.name && "name #{before.name} → #{now.name}",
        before.exits != now.exits &&
          "exits #{Enum.join(before.exits, ", ")} → #{Enum.join(now.exits, ", ")}"
      ]
      |> Enum.filter(& &1)

    "Changed place #{now.name || id}: #{Enum.join(parts, "; ")}"
  end

  defp place_map(place), do: %{"name" => place.name, "exits" => place.exits}

  defp entities(session, seed) do
    session.npc_ids
    |> Enum.reject(&Map.has_key?(seed.entities, &1))
    |> Enum.map(fn id ->
      name = Map.get(session.npc_names, id, id)

      Difference.new(%Difference{
        kind: :new_entity,
        entity_id: id,
        summary: "New NPC: #{name}",
        session: %{"name" => name}
      })
    end)
  end

  defp facts(session, seed) do
    session.facts
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {entity_id, facts} ->
      known = known?(entity_id, session, seed)
      seed_facts = get_in(seed.entities, [entity_id, :facts]) || []

      facts
      |> Enum.uniq_by(&Seed.normalize(&1["text"]))
      |> Enum.reject(&(Seed.normalize(&1["text"]) in seed_facts))
      |> Enum.map(&fact_difference(&1, entity_id, known))
    end)
  end

  defp known?(id, session, seed) do
    Map.has_key?(seed.entities, id) or Map.has_key?(seed.places, id) or
      Map.has_key?(session.places, id) or id in session.npc_ids
  end

  defp fact_difference(fact, entity_id, known) do
    kind = if known, do: :new_fact, else: :free_text
    typed = Map.take(fact, ~w(kind text turn))
    prefix = if known, do: "New #{typed["kind"] || "fact"} on #{entity_id}", else: entity_id

    Difference.new(%Difference{
      kind: kind,
      entity_id: entity_id,
      summary: "#{prefix}: #{typed["text"]}",
      session: typed
    })
  end

  defp kind_rank(kind), do: Enum.find_index(Difference.kinds(), &(&1 == kind))
end
