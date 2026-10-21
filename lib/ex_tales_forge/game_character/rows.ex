defmodule TalesForge.GameCharacter.Rows do
  @moduledoc """
  The store of the pack NPCs: their `characters` rows (controller `gm`,
  origin `pack`), read and written as `TalesForge.GameCharacter.Person`s (refactor
  step 10f PR 5).

  A row written before this step has no memory list in its `runtime`; its
  memories are read from their `character_memories` rows
  (`TalesForge.GameCharacter.Memories.old/1`). The next write keeps them in the row.
  """

  import Ecto.Query

  alias TalesForge.Characters.Attrs
  alias TalesForge.GameCharacter
  alias TalesForge.GameCharacter.{Memories, Person}
  alias TalesForge.Repo
  alias TalesForge.Schemas.Character

  @goods ~w(stock coins)

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
    memories = Memories.old(rows)
    Enum.map(rows, &Person.from_row(&1, Map.get(memories, &1.id, [])))
  end

  @doc "One pack NPC of the session, or nil."
  @spec get(Ecto.UUID.t(), String.t()) :: Person.t() | nil
  def get(session_id, npc_id) when is_binary(npc_id),
    do: session_id |> query() |> where([c], c.slug == ^npc_id) |> people() |> List.first()

  def get(_session_id, _npc_id), do: nil

  @doc "The slugs of the session's pack NPCs."
  @spec slugs(Ecto.UUID.t()) :: [String.t()]
  def slugs(session_id),
    do: session_id |> query() |> select([c], c.slug) |> order_by([c], asc: c.slug) |> Repo.all()

  @doc """
  Saves `runtime_state` as the NPC's state (`TalesForge.GameCharacter.Person.attrs/3`),
  except its goods: the stock and the coins stay as the row has them, since
  only a trade moves them (`put_goods!/2`). A row without a relationship yet
  gets it to the session's player character.
  """
  @spec update!(Person.t(), map()) :: Person.t()
  def update!(%Person{} = person, runtime_state) do
    row = person |> changeset(runtime_state) |> Repo.update!()
    %Person{person | row: row, runtime_state: keep_goods(runtime_state, person)}
  end

  @doc "The changeset of `update!/2` (the state without the goods), for a Multi."
  @spec changeset(Person.t(), map()) :: Ecto.Changeset.t()
  def changeset(%Person{row: row} = person, runtime_state) do
    attrs = Person.attrs(row, keep_goods(runtime_state, person), pc_slug(row))
    Character.changeset(row, Map.drop(attrs, [:inventory, :coins]))
  end

  @doc """
  Saves the inventory and the coins of `trader` (the NPC after a trade,
  `TalesForge.NPC.traders/2`) as the NPC's stock and purse, and nothing
  else: the one write of an NPC's goods in a turn.
  """
  @spec put_goods!(Person.t(), GameCharacter.t()) :: Person.t()
  def put_goods!(%Person{row: row} = person, %GameCharacter{inventory: inventory, coins: coins}) do
    row =
      row
      |> Character.changeset(%{inventory: Attrs.inventory(inventory), coins: coins})
      |> Repo.update!()

    goods = %{"stock" => inventory, "coins" => coins}
    %Person{person | row: row, runtime_state: Map.merge(person.runtime_state, goods)}
  end

  @doc """
  The changeset of an admin's edit of the NPC's whole state, goods
  included. The row's lock version is checked: `Repo.update/2` with
  `stale_error_field: :lock_version` returns an error, not a raise, when
  the row changed after `person` was read.
  """
  @spec edit_changeset(Person.t(), map()) :: Ecto.Changeset.t()
  def edit_changeset(%Person{row: row}, runtime_state),
    do: Character.changeset(row, Person.attrs(row, runtime_state, pc_slug(row)))

  defp keep_goods(runtime_state, %Person{runtime_state: read}),
    do: Map.merge(runtime_state, Map.take(read, @goods))

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
end
