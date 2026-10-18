defmodule TalesForge.NPC.Rows do
  @moduledoc """
  The store of the pack NPCs: their `characters` rows (controller `gm`,
  origin `pack`), read and written as `TalesForge.NPC.Person`s (refactor
  step 10f PR 5; before it, `npc_instances`).

  A row written before this step has no memory list in its `runtime`; its
  memories are read from the `character_memories` rows they were mirrored
  to (kind `memory`, no event, not about anyone), the newest
  20 by tick. The next write keeps them in the row.
  """

  import Ecto.Query

  alias TalesForge.GameCharacter
  alias TalesForge.NPC.Person
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, CharacterMemory}

  @memory_limit 20

  @doc "The number of memories an NPC keeps in its row."
  @spec memory_limit() :: pos_integer()
  def memory_limit, do: @memory_limit

  @doc "The session's pack NPCs, by slug."
  @spec list(Ecto.UUID.t()) :: [Person.t()]
  def list(session_id), do: session_id |> query() |> people()

  @doc "The pack NPCs of the sessions `session_ids`, by session and slug."
  @spec list_many([Ecto.UUID.t()]) :: [Person.t()]
  def list_many(session_ids) when is_list(session_ids) do
    Character
    |> where([c], c.game_session_id in ^session_ids)
    |> pack()
    |> order_by([c], asc: c.game_session_id)
    |> people()
  end

  defp people(query) do
    rows = query |> order_by([c], asc: c.slug) |> Repo.all()
    memories = old_memories(rows)
    Enum.map(rows, &Person.from_row(&1, Map.get(memories, &1.id, [])))
  end

  @doc "One pack NPC of the session, or nil."
  @spec get(Ecto.UUID.t(), String.t()) :: Person.t() | nil
  def get(session_id, npc_id) when is_binary(npc_id) do
    case session_id |> query() |> where([c], c.slug == ^npc_id) |> Repo.one() do
      nil -> nil
      row -> Person.from_row(row, Map.get(old_memories([row]), row.id, []))
    end
  end

  def get(_session_id, _npc_id), do: nil

  @doc "The slugs of the session's pack NPCs."
  @spec slugs(Ecto.UUID.t()) :: [String.t()]
  def slugs(session_id),
    do: session_id |> query() |> select([c], c.slug) |> order_by([c], asc: c.slug) |> Repo.all()

  @doc """
  Saves `runtime_state` as the NPC's state (`TalesForge.NPC.Person.attrs/3`).
  A row without a relationship yet gets it to the session's player character.
  """
  @spec update!(Person.t(), map()) :: Person.t()
  def update!(%Person{} = person, runtime_state), do: save!(person, runtime_state, %{})

  @doc """
  Saves the inventory and the coins of `trader` (the NPC after a trade,
  `TalesForge.NPC.traders/2`) as the NPC's stock and coins.
  """
  @spec put_goods!(Person.t(), GameCharacter.t()) :: Person.t()
  def put_goods!(%Person{} = person, %GameCharacter{inventory: inventory, coins: coins}),
    do: save!(person, Map.put(person.runtime_state, "stock", inventory), %{coins: coins})

  defp save!(%Person{row: row} = person, runtime_state, columns) do
    row =
      row
      |> Character.changeset(Map.merge(Person.attrs(row, runtime_state, pc_slug(row)), columns))
      |> Repo.update!()

    %Person{person | row: row, runtime_state: runtime_state}
  end

  @doc "The changeset of `update!/2`, for a Multi."
  @spec changeset(Person.t(), map()) :: Ecto.Changeset.t()
  def changeset(%Person{row: row}, runtime_state),
    do: Character.changeset(row, Person.attrs(row, runtime_state, pc_slug(row)))

  @doc """
  Adds a memory row for `entry` (a memory of the NPC's runtime list) unless
  the NPC already has one with that tick and text.
  """
  @spec add_memory!(Person.t(), map()) :: :ok
  def add_memory!(%Person{row: %Character{id: id}}, %{"summary" => text} = entry) do
    tick = entry["tick"]

    known? =
      CharacterMemory
      |> where([m], m.character_id == ^id and m.text == ^text)
      |> where_tick(tick)
      |> Repo.exists?()

    unless known? do
      %CharacterMemory{}
      |> CharacterMemory.changeset(%{character_id: id, kind: "memory", text: text, tick: tick})
      |> Repo.insert!()
    end

    :ok
  end

  defp where_tick(query, tick) when is_integer(tick), do: where(query, [m], m.tick == ^tick)
  defp where_tick(query, _tick), do: where(query, [m], is_nil(m.tick))

  defp query(session_id),
    do: Character |> where([c], c.game_session_id == ^session_id) |> pack()

  defp pack(query),
    do: where(query, [c], c.controller == "gm" and fragment("?->>'source' = 'pack'", c.origin))

  # The player character's slug, for a row that has no relationship yet.
  defp pc_slug(%Character{relationships: rel}) when is_map(rel) and map_size(rel) > 0, do: nil

  defp pc_slug(%Character{game_session_id: session_id}) do
    Character
    |> where([c], c.game_session_id == ^session_id and c.controller in ~w(player bot))
    |> select([c], c.slug)
    |> order_by([c], asc: c.slug)
    |> limit(1)
    |> Repo.one()
  end

  # The memories of rows written before their runtime kept them, by row id.
  defp old_memories(rows) do
    case for(%Character{runtime: runtime, id: id} <- rows, not has_memories?(runtime), do: id) do
      [] -> %{}
      ids -> mirrored_memories(ids)
    end
  end

  defp has_memories?(runtime), do: is_map(runtime) and Map.has_key?(runtime, "memories")

  defp mirrored_memories(ids) do
    CharacterMemory
    |> where([m], m.character_id in ^ids and m.kind == "memory" and is_nil(m.session_event_id))
    |> where([m], fragment("cardinality(?) = 0", m.about))
    |> order_by([m], desc: m.tick, desc: m.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.character_id)
    |> Map.new(fn {id, memories} ->
      {id, memories |> Enum.take(@memory_limit) |> Enum.reverse() |> Enum.map(&entry/1)}
    end)
  end

  defp entry(%CharacterMemory{} = memory) do
    %{"summary" => memory.text, "tick" => memory.tick}
    |> put_set("felt", memory.felt)
    |> put_set("secret", if(memory.secret, do: true))
  end

  defp put_set(map, _key, nil), do: map
  defp put_set(map, key, value), do: Map.put(map, key, value)
end
