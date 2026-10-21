defmodule TalesForge.GameCharacter.Memories do
  @moduledoc """
  A pack NPC's memories as `character_memories` rows (kind `memory`, no
  event, not about anyone).

  Each memory recorded in the NPC's row is mirrored to one (`add!/2`). A
  row written before refactor step 10f PR 5, which has no memory list in
  its `runtime`, reads its newest `limit/0` from them (`old/1`).
  """

  import Ecto.Query

  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, CharacterMemory}

  @limit 20

  @doc "The number of memories an NPC keeps in its row."
  @spec limit() :: pos_integer()
  def limit, do: @limit

  @doc """
  Adds a memory row to `row` for `entry` (a memory of the NPC's runtime
  list) unless it already has one with that tick and text.
  """
  @spec add!(Character.t(), map()) :: :ok
  def add!(%Character{id: id}, %{"summary" => text} = entry) do
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

  @doc """
  The memories of the `rows` written before their runtime kept them, by row
  id, oldest first; rows that keep their own are left out.
  """
  @spec old([Character.t()]) :: %{Ecto.UUID.t() => [map()]}
  def old(rows) do
    case for(%Character{runtime: runtime, id: id} <- rows, not kept?(runtime), do: id) do
      [] -> %{}
      ids -> mirrored(ids)
    end
  end

  defp where_tick(query, tick) when is_integer(tick), do: where(query, [m], m.tick == ^tick)
  defp where_tick(query, _tick), do: where(query, [m], is_nil(m.tick))

  defp kept?(runtime), do: is_map(runtime) and Map.has_key?(runtime, "memories")

  defp mirrored(ids) do
    CharacterMemory
    |> where([m], m.character_id in ^ids and m.kind == "memory" and is_nil(m.session_event_id))
    |> where([m], fragment("cardinality(?) = 0", m.about))
    |> order_by([m], desc: m.tick, desc: m.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.character_id)
    |> Map.new(fn {id, memories} ->
      {id, memories |> Enum.take(@limit) |> Enum.reverse() |> Enum.map(&entry/1)}
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
