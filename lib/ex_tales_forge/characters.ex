defmodule TalesForge.Characters do
  @moduledoc """
  One Character entity for player characters and NPCs (Character plan in
  ex-tales-forge, phases 1 and 1b).

  The player character's row is its only stored copy (refactor step 10b-2):
  `game_sessions.world_state` is saved without `"character"`
  (`TalesForge.Schemas.WorldState`). In memory the turn still plays on
  `world_state["character"]`, which `put_sheet/1` fills from the row when a
  session is loaded.

  The GM's characters are the session's cast (`cast/1`,
  `TalesForge.Game.Cast`; refactor step 10f PR 4): their wounds, vitality
  and gut reaction live on their rows only, and a minor foe is a row of its
  own. A pack NPC's row is its only store (step 10f PR 5): `TalesForge.NPC`
  writes its place, mood, stock, relationship, runtime and memories onto
  the row (`TalesForge.NPC.Rows`), in the transaction of its caller.

    * `seed_session/2` writes the player character's row when a session is
      created, after `TalesForge.NPC.seed_session/1` has written the NPCs'.
    * `write_multi/2` is the characters step of the turn Multi (and of the
      admin world-state edit): it writes the player character and the cast
      (wounds, reactions, minor foes) onto the rows, and each NPC's
      relationship to the player character, in the same transaction as the
      session.
    * `end_scene_multi/2` removes the rows that live for a scene
      (`lifetime: :scene`, a minor foe) when the turn ends their scene.
    * `backfill/0` does the same for every existing session. Idempotent and
      re-runnable.

  All three build the rows the same way: insert missing rows, update the
  mirrored fields of existing ones (of an NPC's, only its cast state). Levers
  (OCEAN, Maslow, concerns), controller, owner, origin and definition are set
  when a row is first written and are not overwritten by later syncs.
  """

  import Ecto.Query

  require Logger

  alias TalesForge.Characters.{Attrs, Levers}
  alias TalesForge.Game.{Cast, Pack}
  alias TalesForge.Game.WorldClock
  alias TalesForge.GameCharacter
  alias TalesForge.NPC
  alias TalesForge.NPC.Person
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, CharacterMemory, GameSession, PlaytestRun}

  # Columns copied from the game state on every sync. Everything else is set
  # once, when the row is first written.
  @mirrored ~w(name race role location_id stats skills inventory coins wounds wound_max
               vitality learning_points learning_failures class creation reflecting
               improved_since_rest mood relationships runtime)a

  @doc """
  Writes the session's characters at session create: the player character
  (from `world_state["character"]` plus the pack file's levers), and each
  NPC row's relationship to it. Re-running it updates the mirrored fields
  (`sync_session/2`).

  Options (atom or string keys):
    * `:controller` – `"player"` (default) or `"bot"` for the persona runner
    * `:controller_ref` – who controls the player character (a persona id, …)
    * `:owner_player_id` – the player the character belongs to (nil for now)
  """
  @spec seed_session(GameSession.t(), map()) :: :ok | {:error, term()}
  def seed_session(%GameSession{} = session, opts \\ %{}), do: sync_session(session, opts)

  @doc """
  Inserts or updates every character of the session from the game state, in one
  transaction. Options as for
  `seed_session/2`; they only matter for rows written for the first time.
  """
  @spec sync_session(GameSession.t(), map()) :: :ok | {:error, term()}
  def sync_session(%GameSession{} = session, opts \\ %{}) do
    {rows, npcs} = rows(session, cast(session.id), opts)

    case Repo.transaction(fn -> write_rows!(rows, npcs, session.id) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, {:characters, reason}}
    end
  end

  @doc """
  The characters write, as a step of a Multi after its `:session` step: the
  rows from the session that step saved, whose in-memory world still holds
  the player character (`TalesForge.Schemas.WorldState`), and from `cast`,
  the GM characters as the turn left them (`TalesForge.Game.Cast`). An
  NPC's row is read in the step, so the NPC updates before it (world sim,
  GM memories) stay; only its wounds, vitality, gut reaction and
  relationship key are written. The admin world-state edit runs it after
  the session, with the cast as stored.

  A row that doesn't validate (a broken sheet) skips the write with a
  warning, so it never fails the turn.
  """
  @spec write_multi(Ecto.Multi.t(), Cast.t()) :: Ecto.Multi.t()
  def write_multi(%Ecto.Multi{} = multi, cast) when is_map(cast) do
    Ecto.Multi.run(multi, :characters, fn _repo, %{session: session} ->
      {:ok, write_turn(session, cast)}
    end)
  end

  @doc """
  Removes the rows that live for a scene (`lifetime: :scene`, a minor foe)
  at `location_id`, the place of the scene that the turn ends (a
  `player.travel` away from it or a long rest there,
  `TalesForge.Characters.Memory.scene_end/1`), as a step of a Multi after
  its `:session` step. The only reader of `lifetime`. Nothing to do when no
  scene ends (nil).
  """
  @spec end_scene_multi(Ecto.Multi.t(), String.t() | nil) :: Ecto.Multi.t()
  def end_scene_multi(%Ecto.Multi{} = multi, nil), do: multi

  def end_scene_multi(%Ecto.Multi{} = multi, location_id) do
    Ecto.Multi.delete_all(multi, :scene_characters, fn %{session: session} ->
      where(
        Character,
        [c],
        c.game_session_id == ^session.id and c.lifetime == :scene and
          c.location_id == ^location_id
      )
    end)
  end

  @doc """
  The session's cast (`TalesForge.Game.Cast`): every GM character from its
  row (controller `gm`), a pack NPC as `TalesForge.NPC.cast_member/2` has
  it (name and role from its definition, mood `"neutral"` when unset, its
  current concern). A minor foe is a row of its own.
  """
  @spec cast(Ecto.UUID.t() | nil) :: Cast.t()
  def cast(nil), do: %{}

  def cast(session_id) do
    Character
    |> where([c], c.game_session_id == ^session_id and c.controller == "gm")
    |> Repo.all()
    |> Map.new(fn row -> {row.slug, cast_member(row)} end)
  end

  defp cast_member(%Character{origin: %{"source" => "pack"}} = row),
    do: row |> Person.from_row() |> NPC.cast_member(GameCharacter.from_schema(row))

  defp cast_member(%Character{} = row), do: GameCharacter.from_schema(row)

  @doc """
  Saves a session changeset and its characters in one transaction
  (`write_multi/1`): the save for a world whose `"character"` may have
  changed outside a turn, such as the admin world-state edit.
  """
  @spec save_session(Ecto.Changeset.t()) :: {:ok, GameSession.t()} | {:error, term()}
  def save_session(%Ecto.Changeset{data: %GameSession{}} = changeset) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, changeset)
    |> write_multi(cast(changeset.data.id))
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp write_turn(%GameSession{id: id} = session, cast) do
    {rows, npcs} = rows(session, cast, %{})

    case Enum.reject(
           rows,
           &Character.changeset(%Character{}, Map.put(&1, :game_session_id, id)).valid?
         ) do
      [] ->
        write_rows!(rows, npcs, id)

      invalid ->
        Logger.warning(
          "characters write skipped session=#{id} slugs=#{Enum.map_join(invalid, ",", & &1.slug)}"
        )

        :skipped
    end
  end

  # The player character and the other GM characters of the cast (the minor
  # foes) to upsert, and the pack NPCs, whose rows get their cast state and
  # their relationship keyed by the player character.
  defp rows(%GameSession{} = session, cast, opts) do
    tick = Map.get(session.world_state, "world_tick", WorldClock.default_start_tick())
    pc = player_character_attrs(session, opts, tick)
    npc_ids = session.id |> NPC.Rows.slugs() |> MapSet.new()

    others =
      for %GameCharacter{slug: slug} = member <- Cast.sorted(cast),
          not MapSet.member?(npc_ids, slug),
          do: from_cast_member(member, tick)

    {[pc | others], %{pc_slug: pc.slug, slugs: MapSet.to_list(npc_ids), cast: cast}}
  end

  # What only the cast holds of an NPC: its wounds, vitality and gut reaction.
  defp cast_state(row, nil, reaction), do: %{runtime: put_reaction(row.runtime, reaction)}

  defp cast_state(row, %GameCharacter{} = member, reaction) do
    %{
      wounds: member.wounds,
      wound_max: member.wound_max,
      vitality: member.vitality,
      runtime: put_reaction(row.runtime, reaction)
    }
  end

  defp put_reaction(runtime, reaction) when is_map(reaction),
    do: Map.put(runtime || %{}, "reaction", reaction)

  defp put_reaction(runtime, _reaction), do: Map.delete(runtime || %{}, "reaction")

  @doc """
  Character attrs for a GM character of the cast that is not a pack NPC,
  such as a minor foe (`TalesForge.Game.Combat.minor_foe/3`): its sheet
  becomes the row's `definition`, written once, and its wounds, place and
  lifetime are mirrored.
  """
  @spec from_cast_member(GameCharacter.t(), integer()) :: map()
  def from_cast_member(%GameCharacter{} = member, tick) do
    %{
      slug: member.slug,
      controller: "gm",
      controller_ref: nil,
      owner_player_id: nil,
      origin: %{"source" => "cast"},
      definition: GameCharacter.to_sheet(member),
      name: member.name || member.slug,
      race: member.race,
      role: member.role,
      location_id: member.location_id,
      stats: Character.Stats.from_sheet(member.stats),
      skills: Attrs.int_map(member.skills),
      ocean: member.ocean || %{},
      maslow_level: member.maslow_level || "safety",
      maslow_since_tick: tick,
      concerns: Attrs.concerns(member.concerns, tick),
      inventory: Attrs.inventory(member.inventory),
      coins: member.coins || %{},
      wounds: member.wounds,
      wound_max: member.wound_max,
      vitality: member.vitality,
      mood: member.mood,
      relationships: %{},
      runtime: Map.take(member.runtime, ["reaction"]),
      lifetime: member.lifetime
    }
  end

  defp write_rows!(rows, npcs, session_id) do
    Enum.each(rows, &upsert_or_rollback!(&1, session_id))
    Enum.each(npcs.slugs, &write_npc!(session_id, &1, npcs))
  end

  # An NPC row, read in the transaction: its cast state and its relationship
  # keyed by the player character (whose slug a re-seed can change).
  defp write_npc!(session_id, slug, %{pc_slug: pc_slug, cast: cast}) do
    %Character{} = row = get_by_slug(session_id, slug)

    attrs =
      row
      |> cast_state(cast[slug], Cast.reaction(cast, slug))
      |> Map.put(:relationships, %{pc_slug => Person.relationship_score(row.relationships)})

    case row |> Character.changeset(attrs) |> Repo.update() do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback({slug, changeset})
    end
  end

  @doc """
  Writes or refreshes the characters of every existing session. Sessions that
  ran under the persona runner get the player character as `bot` with the
  persona as `controller_ref`. The player character comes from
  `put_sheets/1`: a sheet still stored in `world_state` (a session not
  saved since 10b-2) is copied to the row, else the row is written again as
  it is. Idempotent and safe to re-run.

  Returns `%{sessions: n, inserted: n, characters: n, memories: n, failed: [{session_id, reason}]}`.
  """
  @spec backfill() :: map()
  def backfill do
    before = Repo.aggregate(Character, :count)
    personas = Map.new(Repo.all(from r in PlaytestRun, select: {r.game_session_id, r.persona}))

    failed =
      GameSession
      |> order_by([g], asc: g.inserted_at)
      |> Repo.all()
      |> put_sheets()
      |> Enum.flat_map(fn session ->
        case sync_session(session, backfill_opts(personas[session.id])) do
          :ok -> []
          {:error, reason} -> [{session.id, reason}]
        end
      end)

    total = Repo.aggregate(Character, :count)

    %{
      sessions: Repo.aggregate(GameSession, :count),
      inserted: total - before,
      characters: total,
      memories: Repo.aggregate(CharacterMemory, :count),
      failed: failed
    }
  end

  defp backfill_opts(nil), do: %{}
  defp backfill_opts(persona), do: %{controller: "bot", controller_ref: persona}

  defp upsert_or_rollback!(attrs, session_id) do
    changeset = Character.changeset(%Character{}, Map.put(attrs, :game_session_id, session_id))

    case Repo.insert(changeset,
           on_conflict: {:replace, @mirrored ++ [:updated_at]},
           conflict_target: [:game_session_id, :slug]
         ) do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback({attrs.slug, changeset})
    end
  end

  @doc """
  The session with its player character in `world_state["character"]`, the
  sheet the turn and every page read: `GameCharacter.to_sheet/1` of the
  character's row. A sheet still stored in the column (a session not saved
  since 10b-2) comes first, as it did before; the next turn writes it to
  the row and saves the session without it (`backfill/0` copies it for
  every session). A session with neither is returned as it is.
  """
  @spec put_sheet(GameSession.t()) :: GameSession.t()
  def put_sheet(%GameSession{} = session), do: hd(put_sheets([session]))

  @doc "`put_sheet/1` for a list of sessions, with one query for the rows."
  @spec put_sheets([GameSession.t()]) :: [GameSession.t()]
  def put_sheets(sessions) when is_list(sessions) do
    sheets = sessions |> Enum.map(& &1.id) |> player_sheets()

    Enum.map(sessions, fn %GameSession{} = session ->
      %{session | world_state: put_world_sheet(session.world_state, sheets[session.id])}
    end)
  end

  @doc """
  `world` with the player character `sheet` from its row, unless `world`
  still holds a stored sheet (see `put_sheet/1`) or there is no row (`nil`).
  """
  @spec put_world_sheet(map() | nil, map() | nil) :: map() | nil
  def put_world_sheet(world, nil), do: world
  def put_world_sheet(%{"character" => stored} = world, _sheet) when not is_nil(stored), do: world
  def put_world_sheet(world, sheet), do: Map.put(world || %{}, "character", sheet)

  @doc """
  The player character sheet of each session that has a row, by session id
  (`GameCharacter.to_sheet/1`).
  """
  @spec player_sheets([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => map()}
  def player_sheets(session_ids) do
    Character
    |> where([c], c.game_session_id in ^session_ids and c.controller in ~w(player bot))
    |> order_by([c], asc: c.slug)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc ->
      Map.put_new_lazy(acc, row.game_session_id, fn ->
        row |> GameCharacter.from_schema() |> GameCharacter.to_sheet()
      end)
    end)
  end

  @doc "The session's characters, ordered by slug."
  def list_for_session(session_id) do
    Character
    |> where([c], c.game_session_id == ^session_id)
    |> order_by([c], asc: c.slug)
    |> Repo.all()
  end

  @doc "One character by session and slug, or nil."
  def get_by_slug(session_id, slug),
    do: Repo.get_by(Character, game_session_id: session_id, slug: slug)

  @doc """
  Adds one memory row for a character: its own view (felt, salience, secret)
  of an event, optionally pointing at the shared `session_events` row.
  """
  def add_memory(%Character{id: id}, attrs) when is_map(attrs) do
    %CharacterMemory{}
    |> CharacterMemory.changeset(Map.put(attrs, :character_id, id))
    |> Repo.insert()
  end

  @doc "A character's memories, oldest first."
  def list_memories(%Character{id: id}) do
    CharacterMemory
    |> where([m], m.character_id == ^id)
    |> order_by([m], asc: m.tick, asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Character attrs for the player character: the sheet as stored in
  `world_state["character"]` plus the levers from the adventure's pack file,
  or from `opts[:character]` for a created character
  (`TalesForge.CharacterCreation.finalize/1`, origin `created`). Levers and
  origin are written only when the row is inserted, so the per-turn mirror,
  which passes no character, never replaces a created character's levers.
  """
  @spec player_character_attrs(GameSession.t(), map(), integer()) :: map()
  def player_character_attrs(%GameSession{world_state: world_state}, opts, tick) do
    adventure_id = Map.get(world_state, "adventure_id") || "crossroads_ledger"
    created = opt(opts, :character)
    file = created || player_character_file(adventure_id)
    sheet = Map.get(world_state, "character") || Pack.sheet(file)
    controller = opt(opts, :controller) || "player"

    %{
      slug: sheet["id"] || file["id"],
      controller: controller,
      controller_ref: opt(opts, :controller_ref),
      owner_player_id: opt(opts, :owner_player_id),
      origin: origin(created, adventure_id, file),
      definition: file,
      role: nil,
      ocean: Levers.ocean_source(file),
      maslow_level: file["maslow"] || "safety",
      maslow_since_tick: tick,
      concerns: Attrs.concerns(file["concerns"], tick),
      mood: nil,
      relationships: %{},
      runtime: %{}
    }
    |> Map.merge(sheet_attrs(sheet, world_state))
    |> put_sheet_runtime(sheet)
  end

  defp origin(nil, adventure_id, file),
    do: %{"source" => "pack", "adventure_id" => adventure_id, "definition_id" => file["id"]}

  defp origin(_created, adventure_id, _file),
    do: %{"source" => "created", "adventure_id" => adventure_id}

  # The columns that come from the sheet.
  defp sheet_attrs(sheet, world_state) do
    %{
      name: sheet["name"],
      race: sheet["race"],
      location_id: sheet["location_id"] || world_state["location_id"],
      stats: Character.Stats.from_sheet(sheet["stats"]),
      skills: number_map(sheet["skills"]),
      inventory: Attrs.inventory(sheet["inventory"]),
      coins: sheet["coins"] || %{},
      wounds: Attrs.int(sheet["wounds"], 0),
      wound_max: Attrs.int(sheet["wound_max"], 3),
      vitality: sheet["vitality"] || "ok",
      learning_points: sheet["learning_points"] || %{},
      learning_failures: sheet["learning_failures"] || %{},
      class: sheet["class"],
      creation: sheet["creation"],
      reflecting: sheet["reflecting"],
      improved_since_rest: sheet["improved_since_rest"]
    }
  end

  # What the columns can't round-trip of the sheet goes to runtime["sheet"],
  # so `GameCharacter.to_sheet/1` of the row is this sheet. Every sheet key
  # has a column now (10b-1.5), so this is empty and not written; it stays
  # only as a guard for a sheet the columns can't hold (an item without a
  # name, a non-number skill).
  defp put_sheet_runtime(attrs, sheet) do
    gc =
      %Character{}
      |> Character.changeset(attrs)
      |> Ecto.Changeset.apply_changes()
      |> GameCharacter.from_schema()

    case GameCharacter.sheet_runtime(gc, sheet) do
      %{"extra" => extra, "missing" => []} when extra == %{} -> attrs
      bridge -> %{attrs | runtime: %{"sheet" => bridge}}
    end
  end

  # A sheet's skills with their numbers as they are (a float stays a float).
  defp number_map(map) when is_map(map) do
    for {k, v} <- map, is_number(v), into: %{}, do: {to_string(k), v}
  end

  defp number_map(_), do: %{}

  defp player_character_file(adventure_id) do
    Pack.player_character!(adventure_id)
  rescue
    ArgumentError -> Pack.player_character!("crossroads_ledger")
  end

  defp opt(opts, key), do: Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
end
