defmodule TalesForge.GameCharacter.Roster do
  @moduledoc """
  The session's pack NPCs in play: who is present, their memories and
  relationship, their goods as traders, and how the GM prompt, the notice
  and the combat rules see them. Seeding is `TalesForge.GameCharacter.Seeding`;
  the world-sim tick and speaking up about a concern are
  `TalesForge.GameCharacter.Agency`.

  An NPC's live state is its `characters` row (refactor step 10f PR 5),
  read and written as a `TalesForge.GameCharacter.Person` through
  `TalesForge.GameCharacter.Rows`. Every write runs in the caller's
  transaction, so the turn's NPC updates commit with the turn.
  """

  alias TalesForge.Game.FirstMeeting
  alias TalesForge.GameCharacter
  alias TalesForge.GameCharacter.{Memories, Person, Rows}
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  defmodule Note do
    @moduledoc """
    A memory for `TalesForge.GameCharacter.Roster.record_memory/1`: the session, the NPC, the
    summary and the world tick.
    """
    defstruct [:session_id, :npc_id, :summary, :tick]

    @typedoc "A memory to record for one NPC."
    @type t :: %__MODULE__{
            session_id: String.t(),
            npc_id: String.t(),
            summary: String.t(),
            tick: integer() | nil
          }
  end

  @memory_context_limit 5

  @doc """
  Puts the NPCs at the session's place into its `world_state`
  (`"present_npcs"`, `sync_present_npcs/2`) and saves the session.
  """
  @spec refresh_session_world_state(GameSession.t()) ::
          {:ok, GameSession.t()} | {:error, Ecto.Changeset.t()}
  def refresh_session_world_state(%GameSession{} = session) do
    location_id = Map.get(session.world_state, "location_id", "weary_pilgrim")

    world_state =
      Map.put(session.world_state, "present_npcs", sync_present_npcs(session.id, location_id))

    session
    |> GameSession.changeset(%{world_state: world_state})
    |> Repo.update()
  end

  @doc """
  The present NPCs as the GM prompt sees them (name, personality traits,
  concern focus, mood), for `TalesForge.Game.Notice.details/3`.
  """
  @spec notice_profiles(String.t(), [String.t()]) :: [map()]
  def notice_profiles(session_id, present_npc_ids) do
    session_id
    |> Rows.list()
    |> Enum.filter(&(&1.npc_id in present_npc_ids))
    |> Enum.map(&prompt_npc_context/1)
  end

  @doc """
  The combat fighter of one NPC (`TalesForge.Game.Combat`): the stats,
  OCEAN, Maslow level and concerns of its definition (with the
  `Characters.Defaults` already applied), the skills of its row and its
  current concern. Returns nil when the session has no NPC with that id.
  """
  @spec combat_profile(String.t(), String.t()) :: map() | nil
  def combat_profile(session_id, npc_id) do
    case Rows.get(session_id, npc_id) do
      %Person{} = inst ->
        definition = inst.personality
        runtime = inst.runtime_state

        %{
          "id" => inst.npc_id,
          "name" => Map.get(definition, "name", inst.npc_id),
          "stats" => Map.get(definition, "stats", %{}),
          "skills" => Map.get(definition, "skills", %{}),
          "ocean" =>
            Map.get(definition, "ocean") ||
              get_in(definition, ["motivations", "personality_traits"]) || %{},
          "maslow" => Map.get(definition, "maslow"),
          "concerns" => List.wrap(Map.get(definition, "concerns")),
          "current_concern" => runtime["current_concern"]
        }

      nil ->
        nil
    end
  end

  @doc """
  Adds the memory `note` to its NPC's row (and a memory row for it), unless
  the summary is blank or the session has no such NPC.
  """
  @spec record_memory(Note.t()) :: :ok
  def record_memory(%Note{
        session_id: session_id,
        npc_id: npc_id,
        summary: summary,
        tick: world_tick
      })
      when is_binary(session_id) and is_binary(npc_id) and is_binary(summary) do
    trimmed = String.trim(summary)

    if trimmed == "" do
      :ok
    else
      case Rows.get(session_id, npc_id) do
        %Person{} = inst -> persist_memory(inst, trimmed, world_tick)
        nil -> :ok
      end
    end
  end

  @doc """
  Moves the NPC's relationship score to the player character by `delta`
  and returns the new score (0.0 when the session has no such NPC).
  """
  @spec bump_relationship(Ecto.UUID.t(), String.t(), number()) :: {:ok, number()}
  def bump_relationship(session_id, npc_id, delta) when is_number(delta) do
    case Rows.get(session_id, npc_id) do
      %Person{} = inst ->
        score = Map.get(inst.runtime_state, "relationship_score", 0.0) + delta
        runtime = Map.put(inst.runtime_state, "relationship_score", score)
        Rows.update!(inst, runtime)
        {:ok, score}

      nil ->
        {:ok, 0.0}
    end
  end

  @doc "Records the GM's NPC memory updates (`record_memory/1`) at `world_tick`."
  @spec apply_gm_updates(Ecto.UUID.t(), map(), integer() | nil) :: :ok
  def apply_gm_updates(session_id, gm_result, world_tick) do
    gm_result.npc_memory_updates
    |> List.wrap()
    |> Enum.each(fn update ->
      append_memory(session_id, update, world_tick)
    end)

    :ok
  end

  @doc "The ids of the session's NPCs at `location_id`, sorted."
  @spec sync_present_npcs(Ecto.UUID.t(), String.t()) :: [String.t()]
  def sync_present_npcs(session_id, location_id) do
    session_id
    |> Rows.list()
    |> Enum.filter(fn inst ->
      Map.get(inst.runtime_state, "location_id") == location_id
    end)
    |> Enum.map(& &1.npc_id)
    |> Enum.sort()
  end

  @doc """
  The NPCs `npc_ids` of the session as traders (refactor plan step 10d):
  GameCharacters whose inventory is their stock, every item with a
  `price_copper`, and whose coins are their purse. A definition's `"buys"`,
  `"lends"` and `"serves"` say how the trader trades
  (`TalesForge.Game.Trade`). An id that is not an NPC of the session is
  left out.
  """
  @spec traders(Ecto.UUID.t(), [String.t()]) :: %{String.t() => GameCharacter.t()}
  def traders(session_id, npc_ids) when is_list(npc_ids) do
    Enum.reduce(npc_ids, %{}, fn npc_id, acc ->
      case Rows.get(session_id, npc_id) do
        %Person{} = inst -> Map.put(acc, npc_id, trader(inst))
        nil -> acc
      end
    end)
  end

  defp trader(%Person{npc_id: npc_id, personality: definition} = inst) do
    %GameCharacter{
      slug: npc_id,
      name: definition["name"] || npc_id,
      coins: Map.get(inst.runtime_state, "coins") || %{},
      inventory:
        inst.runtime_state
        |> Map.get("stock", definition_stock(inst))
        |> TalesForge.Game.Inventory.normalize_stock(),
      runtime: Map.take(definition, ["buys", "lends", "serves"])
    }
  end

  @doc """
  Saves the inventory and the coins of each trader (`traders/2`) as its
  NPC's stock and coins (the `inventory` and `coins` of its row).
  """
  @spec put_inventories(Ecto.UUID.t(), [GameCharacter.t()]) :: :ok
  def put_inventories(session_id, traders) when is_list(traders) do
    Enum.each(traders, fn %GameCharacter{slug: npc_id} = trader ->
      case Rows.get(session_id, npc_id) do
        %Person{} = inst -> Rows.put_goods!(inst, trader)
        nil -> :ok
      end
    end)
  end

  @doc """
  The NPC `inst` as a member of the session's cast
  (`TalesForge.Game.Cast`, `TalesForge.Characters.cast/1`): `row` (its
  character row as a `GameCharacter`) with the name, role and portrait of
  its definition, its place and mood (`"neutral"` when unset) and its
  current concern.
  """
  @spec cast_member(Person.t(), GameCharacter.t() | nil) :: GameCharacter.t()
  def cast_member(%Person{} = inst, row) do
    definition = inst.personality
    runtime = inst.runtime_state
    member = row || %GameCharacter{}

    %GameCharacter{
      member
      | slug: inst.npc_id,
        name: Map.get(definition, "name", inst.npc_id),
        role: Map.get(definition, "role", "present"),
        location_id: Map.get(runtime, "location_id"),
        mood: Map.get(runtime, "mood", "neutral"),
        runtime:
          member.runtime
          |> Map.take(["reaction"])
          |> Map.merge(Map.take(runtime, ["current_concern"])),
        extra: portrait(definition["portrait_url"])
    }
  end

  defp portrait(nil), do: %{}
  defp portrait(url), do: %{"portrait_url" => url}

  @doc """
  The GM prompt sections for the present NPCs. With the option
  `first_meeting: true` (flag NPC_FIRST_MEETING), each NPC gets `"meeting"`
  (`TalesForge.Game.FirstMeeting`) and the GM gets the first-meeting rule;
  then `:dialogue_memory` (`world_state["npc_memory"]`) and `:character`
  (the character's name) are read.
  """
  @spec format_gm_sections(Ecto.UUID.t(), [String.t()], keyword()) :: String.t()
  def format_gm_sections(session_id, present_npc_ids, opts \\ []) do
    present =
      session_id
      |> Rows.list()
      |> Enum.filter(&(&1.npc_id in present_npc_ids))

    meeting =
      present
      |> Enum.map(&{&1.npc_id, &1.runtime_state})
      |> FirstMeeting.mark(opts[:dialogue_memory] || %{}, opts[:character])

    contexts =
      Enum.map(present, fn inst ->
        context = prompt_npc_context(inst)

        if opts[:first_meeting],
          do: Map.put(context, "meeting", to_string(meeting[inst.npc_id])),
          else: context
      end)

    """
    ## Present NPCs (merged definition + runtime)
    #{Jason.encode!(contexts, pretty: true)}

    ## NPC Memories (recent)
    #{memory_block(present)}
    """ <> meeting_rule(opts[:first_meeting], contexts, meeting)
  end

  defp memory_block(present) do
    case Enum.flat_map(present, &memory_lines/1) do
      [] -> "(none)"
      lines -> Enum.join(lines, "\n")
    end
  end

  defp memory_lines(%Person{npc_id: npc_id} = inst) do
    inst.runtime_state["memories"]
    |> visible_memories()
    |> Enum.map(&"- #{npc_id}: #{Map.get(&1, "what") || Map.get(&1, "summary", "")}")
  end

  # The GM's first-meeting rule (flag NPC_FIRST_MEETING), as its own block.
  defp meeting_rule(first_meeting, _contexts, _meeting) when first_meeting in [nil, false],
    do: ""

  defp meeting_rule(_first_meeting, contexts, meeting) do
    contexts
    |> Enum.map(&{&1["name"], meeting[&1["id"]], Map.has_key?(&1, "hooks")})
    |> FirstMeeting.rule()
    |> case do
      nil -> ""
      rule -> "\n" <> rule <> "\n"
    end
  end

  defp append_memory(session_id, update, world_tick) when is_map(update) do
    npc_id = Map.get(update, "npc_id") || Map.get(update, :npc_id)
    summary = Map.get(update, "summary") || Map.get(update, :summary)

    record_memory(%Note{
      session_id: session_id,
      npc_id: npc_id,
      summary: summary || "",
      tick: world_tick
    })
  end

  defp append_memory(_session_id, _update, _world_tick), do: :ok

  defp persist_memory(%Person{} = inst, summary, world_tick) do
    entry = %{
      "summary" => String.trim(summary),
      "tick" => world_tick,
      "at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    memories =
      inst.runtime_state
      |> Map.get("memories", [])
      |> Kernel.++([entry])
      |> Enum.take(-Memories.limit())

    %Person{row: row} = Rows.update!(inst, Map.put(inst.runtime_state, "memories", memories))
    Memories.add!(row, entry)
  end

  defp prompt_npc_context(%Person{} = inst) do
    definition = inst.personality
    runtime = inst.runtime_state
    concern = runtime["current_concern"] || %{}
    motivations = definition["motivations"] || %{}

    %{
      "id" => inst.npc_id,
      "name" => Map.get(definition, "name", inst.npc_id),
      "role" => Map.get(definition, "role"),
      "appearance" => Map.get(definition, "appearance"),
      "personality" => Map.get(definition, "personality"),
      "personality_traits" => motivations["personality_traits"],
      "mood" => runtime["mood"],
      "relationship_score" => Map.get(runtime, "relationship_score", 0.0),
      "stock" => visible_stock(runtime["stock"] || definition["stock"]),
      "concern_focus" => concern["focus"],
      "memories" => visible_memories(runtime["memories"])
    }
    |> put_hooks(definition["hooks"])
  end

  # Ready-made leads the NPC offers a player (pack data, e.g. Brenna's). Only
  # NPCs that have them get the key, so other NPCs' prompt text is unchanged.
  defp put_hooks(context, [_ | _] = hooks), do: Map.put(context, "hooks", hooks)
  defp put_hooks(context, _hooks), do: context

  defp visible_stock(stock) do
    stock
    |> List.wrap()
    |> Enum.map(&Map.take(&1, ["id", "name", "price_copper", "quantity"]))
  end

  defp visible_memories(memories) do
    memories
    |> List.wrap()
    |> Enum.reject(&(&1["secret"] == true))
    |> Enum.take(-@memory_context_limit)
    |> Enum.map(&Map.take(&1, ["who", "tick", "what", "felt", "summary"]))
  end

  defp definition_stock(%Person{} = inst) do
    inst.personality
    |> Map.get("stock", [])
    |> TalesForge.Game.Inventory.normalize_stock()
  end
end
