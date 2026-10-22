defmodule TalesForge.Admin do
  @moduledoc """
  Admin context for sessions, their NPCs, turns, and NPC definition files.
  """

  import Ecto.Query

  require Logger

  alias TalesForge.GameCharacter.{Person, Roster, Rows, Seeding, Store}
  alias TalesForge.Repo
  alias TalesForge.Schemas
  alias TalesForge.Schemas.{GameSession, Scene, Turn}

  @doc "Row counts for the admin dashboard."
  @spec stats() :: %{atom() => non_neg_integer()}
  def stats do
    %{
      sessions: Repo.aggregate(GameSession, :count, :id),
      active_sessions:
        GameSession
        |> where([s], s.status == "active")
        |> Repo.aggregate(:count, :id),
      turns: Repo.aggregate(Turn, :count, :id),
      npcs:
        Schemas.GameCharacter
        |> where([c], c.controller == "gm" and fragment("?->>'source' = 'pack'", c.origin))
        |> Repo.aggregate(:count, :id),
      scenes: Repo.aggregate(Scene, :count, :id)
    }
  end

  @doc "Every session, newest first, with its turn count, location and character name."
  @spec list_sessions() :: [map()]
  def list_sessions do
    sessions =
      GameSession
      |> order_by([s], desc: s.inserted_at)
      |> Repo.all()
      |> Store.put_sheets()

    counts = turn_counts(Enum.map(sessions, & &1.id))

    Enum.map(sessions, fn session ->
      %{
        session: session,
        turn_count: Map.get(counts, session.id, 0),
        location_name: session_location(session),
        character_name: session_character_name(session)
      }
    end)
  end

  @doc """
  The session `id` with its character sheet and the `:preload` option's
  associations; raises when there is none.
  """
  @spec get_session!(Ecto.UUID.t(), keyword()) :: GameSession.t()
  def get_session!(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    GameSession
    |> Repo.get!(id)
    |> Store.put_sheet()
    |> Repo.preload(preloads)
  end

  @doc "A changeset for the admin session form (name, status, world state, clock)."
  @spec change_session(GameSession.t(), map()) :: Ecto.Changeset.t()
  def change_session(%GameSession{} = session, attrs \\ %{}) do
    GameSession.changeset(session, attrs)
  end

  @doc "Saves the admin session form's `attrs` onto the session."
  @spec update_session(GameSession.t(), map()) ::
          {:ok, GameSession.t()} | {:error, Ecto.Changeset.t()}
  def update_session(%GameSession{} = session, attrs) do
    session
    |> GameSession.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Saves an edited world state. Its `"character"` is the player character's
  sheet, so the session and the characters rows are written in one
  transaction (`TalesForge.GameCharacter.Store.save_session/1`). The row is the only
  copy of the sheet, so an edit without `"character"` keeps the current one.
  """
  @spec update_session_world_state(%{id: Ecto.UUID.t()}, String.t()) ::
          {:ok, GameSession.t()} | {:error, term()}
  def update_session_world_state(session, json_string)
      when is_binary(json_string) do
    with {:ok, world_state} <- decode_json_map(json_string) do
      current = get_session!(Map.get(session, :id))

      current
      |> GameSession.changeset(%{world_state: keep_character(world_state, current.world_state)})
      |> Store.save_session()
    end
  end

  defp keep_character(edited, %{"character" => %{} = sheet}),
    do: Map.put_new(edited, "character", sheet)

  defp keep_character(edited, _current), do: edited

  @doc """
  Deletes the session. The foreign keys cascade: turns, scenes, characters,
  session events, front instances and playtest runs go with it; AI call rows
  keep their data with `game_session_id` set to NULL.
  """
  @spec delete_session(map()) :: :ok
  def delete_session(session) do
    id = Map.get(session, :id)
    name = Map.get(session, :name, "unknown")
    Logger.info("admin deleting session id=#{id} name=#{name}")

    case Repo.get(GameSession, id) do
      nil -> :ok
      found -> Repo.delete!(found)
    end

    :ok
  end

  @doc """
  Deletes the session's pack NPCs (their character rows and memories) and
  seeds them again from the pack files. Each NPC's relationship to the
  player character is keyed again by the next turn.
  """
  @spec reset_session_npcs(map()) :: {:ok, GameSession.t()} | {:error, Ecto.Changeset.t()}
  def reset_session_npcs(session) do
    id = Map.get(session, :id)
    slugs = Rows.slugs(id)

    from(c in Schemas.GameCharacter, where: c.game_session_id == ^id and c.slug in ^slugs)
    |> Repo.delete_all()

    # For seed/refresh we need the Ecto struct or world_state; fetch fresh
    ecto_session = get_session!(id)
    :ok = Seeding.seed_session(ecto_session)

    case Roster.refresh_session_world_state(ecto_session) do
      {:ok, refreshed} -> {:ok, refreshed}
      error -> error
    end
  end

  @doc """
  Saves `json_string` (a JSON object) as the NPC's runtime state: its place,
  mood, stock and relationship go to their columns, the rest to `runtime`
  (`TalesForge.GameCharacter.Person.attrs/3`). `npc` is the copy the admin page
  edited: when its row changed after that copy was read (a turn played, a
  trade), nothing is saved and the result is `{:error, :stale}`.
  """
  @spec update_npc_runtime_state(Person.t(), String.t()) ::
          {:ok, Person.t()} | {:error, :stale | String.t()}
  def update_npc_runtime_state(%Person{} = npc, json_string) when is_binary(json_string) do
    with {:ok, runtime_state} <- decode_json_map(json_string) do
      npc
      |> Rows.edit_changeset(runtime_state)
      |> Repo.update(stale_error_field: :lock_version)
      |> saved_npc()
    end
  end

  defp saved_npc({:ok, row}), do: {:ok, Person.from_row(row)}

  defp saved_npc({:error, %Ecto.Changeset{errors: errors}}) do
    if Keyword.has_key?(errors, :lock_version),
      do: {:error, :stale},
      else: {:error, "Invalid runtime state: #{inspect(errors)}"}
  end

  @doc "The session's turns, newest first."
  @spec list_turns(Ecto.UUID.t()) :: [Turn.t()]
  def list_turns(session_id) do
    Turn
    |> where([t], t.game_session_id == ^session_id)
    |> order_by([t], desc: t.turn_number)
    |> Repo.all()
  end

  @doc "The turn `turn_id` of the session; raises when there is none."
  @spec get_turn!(Ecto.UUID.t(), Ecto.UUID.t()) :: Turn.t()
  def get_turn!(session_id, turn_id) do
    Turn
    |> where([t], t.game_session_id == ^session_id and t.id == ^turn_id)
    |> Repo.one!()
  end

  @doc "`data` as pretty JSON, for the admin JSON editors."
  @spec encode_json(term()) :: String.t()
  def encode_json(data) do
    Jason.encode!(data, pretty: true)
  end

  @doc "The JSON object in `json_string`, or a plain error for the admin page."
  @spec decode_json_map(String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_json_map(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, "JSON must be an object"}
      {:error, %Jason.DecodeError{position: at}} -> {:error, "Invalid JSON at position #{at + 1}"}
    end
  end

  defp turn_counts([]), do: %{}

  defp turn_counts(session_ids) do
    Turn
    |> where([t], t.game_session_id in ^session_ids)
    |> group_by([t], t.game_session_id)
    |> select([t], {t.game_session_id, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp session_location(session) do
    world_state = session.world_state || %{}
    Map.get(world_state, "location_name", Map.get(world_state, "location_id", "—"))
  end

  defp session_character_name(session) do
    world_state = session.world_state || %{}
    get_in(world_state, ["character", "name"]) || "—"
  end
end
