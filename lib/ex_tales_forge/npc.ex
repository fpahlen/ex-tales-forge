defmodule TalesForge.NPC do
  @moduledoc """
  Per-session NPC runtime: definitions, NpcInstance persistence, memories, presence.

  Core runtime module: Ecto (Schemas.NpcInstance + Repo) for live state;
  definitions come from the pack files in `priv/npcs` (or the pack's own NPCs).
  """

  import Ecto.Query

  alias TalesForge.Characters.{Defaults, Levers}
  alias TalesForge.Game.Features
  alias TalesForge.Game.FirstMeeting
  alias TalesForge.Game.Pack
  alias TalesForge.Game.WorldClock
  alias TalesForge.GameCharacter
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, NpcInstance}

  @memory_limit 20

  defmodule Note do
    @moduledoc """
    A memory for `TalesForge.NPC.record_memory/1`: the session, the NPC, the
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
    |> list_instances()
    |> Enum.filter(&(&1.npc_id in present_npc_ids))
    |> Enum.map(&prompt_npc_context/1)
  end

  @doc """
  Seeds the session's NPC instances from the pack (tin_valley) or the
  `priv/npcs` files. Definitions with a `derive` block get their defaults from
  `TalesForge.Characters.Defaults` (skills on the PC scale, stats, OCEAN), seeded
  per session and NPC; the authored keys stay as overrides.
  """
  def seed_session(%{id: session_id, world_state: world_state}) do
    adventure_id = Map.get(world_state, "adventure_id")
    world_tick = Map.get(world_state, "world_tick", WorldClock.default_start_tick())
    rules = Defaults.rules(adventure_id)

    definitions =
      case adventure_id do
        "tin_valley" ->
          Pack.load("tin_valley", Features.of(world_state)).npcs

        _ ->
          load_definitions_from_files(rules)
      end

    Enum.each(definitions, fn definition ->
      npc_id = Map.get(definition, "id") || Map.get(definition, :id)

      if npc_id do
        npc_id = to_string(npc_id)
        definition = Defaults.apply(definition, rules, Defaults.seed(session_id, npc_id))
        insert_instance!(%{session_id: session_id, world_tick: world_tick}, npc_id, definition)
      end
    end)

    :ok
  end

  defp load_definitions_from_files(rules) do
    npc_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(fn file ->
      source = "priv/npcs/#{file}"
      definition = load_definition_file(file)
      Levers.validate!(definition, source)
      validate_derive!(definition, rules, source)
      definition
    end)
  end

  defp validate_derive!(%{"derive" => inputs}, rules, source),
    do: Defaults.validate_inputs!(inputs, rules, source)

  defp validate_derive!(_definition, _rules, _source), do: :ok

  def list_instances(session_id) do
    NpcInstance
    |> where([n], n.game_session_id == ^session_id)
    |> Repo.all()
  end

  @doc """
  The combat fighter of one NPC instance (`TalesForge.Game.Combat`): the
  stats, skills, OCEAN, Maslow level and concerns of its definition (with
  the `Characters.Defaults` already applied) and its current concern.
  Returns nil when the session has no instance with that id.
  """
  @spec combat_profile(String.t(), String.t()) :: map() | nil
  def combat_profile(session_id, npc_id) do
    case get_instance(session_id, npc_id) do
      %NpcInstance{} = inst ->
        definition = inst.personality || %{}
        runtime = inst.runtime_state || %{}

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

  def get_instance(session_id, npc_id) do
    Repo.get_by(NpcInstance, game_session_id: session_id, npc_id: npc_id)
  end

  def sim_people(session_id) when is_binary(session_id) do
    Enum.map(list_instances(session_id), &to_sim/1)
  end

  def persist_tick_multi(multi, session_id, sim) when is_map(sim) do
    Enum.reduce(Map.get(sim, :people, []), multi, fn person, acc ->
      inst = get_instance(session_id, npc_id(person))

      if inst do
        cs = NpcInstance.changeset(inst, %{runtime_state: runtime(person)})
        Ecto.Multi.update(acc, {:npc, inst.npc_id}, cs)
      else
        acc
      end
    end)
  end

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
      case get_instance(session_id, npc_id) do
        %NpcInstance{} = inst -> persist_memory(inst, trimmed, world_tick)
        nil -> :ok
      end
    end
  end

  def bump_relationship(session_id, npc_id, delta) when is_number(delta) do
    case get_instance(session_id, npc_id) do
      %NpcInstance{} = inst ->
        score = Map.get(inst.runtime_state, "relationship_score", 0.0) + delta
        runtime = Map.put(inst.runtime_state, "relationship_score", score)
        inst |> update_runtime!(runtime)
        {:ok, score}

      nil ->
        {:ok, 0.0}
    end
  end

  def adjust_concern(session_id, npc_id, delta_ticks) when is_integer(delta_ticks) do
    case get_instance(session_id, npc_id) do
      %NpcInstance{runtime_state: %{"current_concern" => %{} = concern}} = inst ->
        wait_on_concern(inst, concern, delta_ticks)

      _ ->
        :ok
    end
  end

  # The concern waits `delta_ticks` longer, and escalates when it has waited
  # long enough.
  defp wait_on_concern(%NpcInstance{runtime_state: runtime} = inst, concern, delta_ticks) do
    waited = Map.get(runtime, "concern_wait_ticks", 0) + delta_ticks
    old_priority = Map.get(concern, "priority", 0)
    initiative_ready? = waited >= 4 and old_priority >= 8 and not initiative_emitted?(inst)
    {waiting, concern} = maybe_escalate_concern(waited, concern)
    priority = Map.get(concern, "priority", 0)

    runtime =
      runtime
      |> Map.put("current_concern", concern)
      |> Map.put("concern_wait_ticks", waiting)
      |> maybe_reset_initiative_emitted(old_priority, priority)

    update_runtime!(inst, runtime)

    {:ok,
     %{
       concern_priority: priority,
       concern_wait_ticks: waiting,
       initiative_pending: initiative_ready?
     }}
  end

  def initiative_text(%NpcInstance{npc_id: "worried_merchant"} = inst) do
    focus =
      inst.runtime_state
      |> Map.get("current_concern", %{})
      |> Map.get("focus", "the stolen ledger")

    case focus do
      "stolen ledger" ->
        "Henrik Bale steps toward you, voice tight. \"Please — if you've heard who took that ledger, tell me before rumors spread.\""

      "ruined reputation" ->
        "Henrik glances at the crowd, then lowers his voice. \"I can't afford another whisper campaign against my name.\""

      _ ->
        "Henrik Bale wrings his hands. \"It's this business with #{focus} — I need answers.\""
    end
  end

  def initiative_text(%NpcInstance{npc_id: "marta_kellen"} = inst) do
    focus =
      inst.runtime_state
      |> Map.get("current_concern", %{})
      |> Map.get("focus", "the missing ledger")

    case focus do
      "missing ledger" ->
        "Marta wipes the bar and catches your eye. \"That ledger didn't walk off on its own. If you've heard anything, I need to know before sundown.\""

      "unwanted attention in her tavern" ->
        "Marta's voice stays low but firm. \"Too many strangers tonight. Keep your business quiet, or take it outside.\""

      _ ->
        "Marta hesitates, then speaks up. \"Something's been bothering me — #{focus}.\""
    end
  end

  def initiative_text(%NpcInstance{} = inst) do
    name = Map.get(inst.personality || %{}, "name", inst.npc_id)
    "#{name} speaks up, as if a worry has been pressing on them for some time."
  end

  def mark_initiative_emitted(%NpcInstance{} = inst, world_tick) do
    runtime =
      inst.runtime_state
      |> Map.put("initiative_emitted", true)
      |> Map.put("initiative_emitted_at_tick", world_tick)

    update_runtime!(inst, runtime)
    :ok
  end

  def concern_priority(%NpcInstance{} = inst) do
    case Map.get(inst.runtime_state, "current_concern") do
      %{} = concern -> Map.get(concern, "priority", 0)
      _ -> 0
    end
  end

  def concern_priority(nil), do: 0

  def apply_gm_updates(session_id, gm_result, world_tick) do
    gm_result.npc_memory_updates
    |> List.wrap()
    |> Enum.each(fn update ->
      append_memory(session_id, update, world_tick)
    end)

    :ok
  end

  def sync_present_npcs(session_id, location_id) do
    session_id
    |> list_instances()
    |> Enum.filter(fn inst ->
      Map.get(inst.runtime_state, "location_id") == location_id
    end)
    |> Enum.map(& &1.npc_id)
    |> Enum.sort()
  end

  @doc """
  The NPCs `npc_ids` of the session as traders (refactor plan step 10d):
  GameCharacters whose inventory is their stock, every item with a
  `price_copper`. An NPC without an instance is left out.
  """
  @spec traders(Ecto.UUID.t(), [String.t()]) :: %{String.t() => GameCharacter.t()}
  def traders(session_id, npc_ids) when is_list(npc_ids) do
    Enum.reduce(npc_ids, %{}, fn npc_id, acc ->
      case get_instance(session_id, npc_id) do
        %NpcInstance{} = inst -> Map.put(acc, npc_id, trader(inst))
        nil -> acc
      end
    end)
  end

  defp trader(%NpcInstance{npc_id: npc_id, personality: definition} = inst) do
    %GameCharacter{
      slug: npc_id,
      name: (definition || %{})["name"] || npc_id,
      inventory:
        inst.runtime_state
        |> Map.get("stock", definition_stock(inst))
        |> TalesForge.Game.Inventory.normalize_stock()
    }
  end

  @doc """
  Saves the inventory of each trader (`traders/2`) as its NPC's stock. The
  NPC instance is the NPC's store until refactor step 10f.
  """
  @spec put_inventories(Ecto.UUID.t(), [GameCharacter.t()]) :: :ok
  def put_inventories(session_id, traders) when is_list(traders) do
    Enum.each(traders, fn %GameCharacter{slug: npc_id, inventory: inventory} ->
      case get_instance(session_id, npc_id) do
        %NpcInstance{} = inst ->
          update_runtime!(inst, Map.put(inst.runtime_state, "stock", inventory))

        nil ->
          :ok
      end
    end)
  end

  @doc """
  The NPC of `inst` as a member of the session's cast
  (`TalesForge.Game.Cast`, `TalesForge.Characters.cast/1`): `row` (its
  character row, or nil before the first write) with the name, role, place,
  mood, current concern and portrait of the NPC instance, which stays the
  NPC's store for those until refactor step 10f PR 5.
  """
  @spec cast_member(NpcInstance.t(), GameCharacter.t() | nil) :: GameCharacter.t()
  def cast_member(%NpcInstance{} = inst, row) do
    definition = inst.personality || %{}
    runtime = inst.runtime_state || %{}
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
  def format_gm_sections(session_id, present_npc_ids, opts \\ []) do
    present =
      session_id
      |> list_instances()
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

  defp memory_lines(%NpcInstance{npc_id: npc_id} = inst) do
    inst
    |> recent_memories()
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

  defp to_sim(%NpcInstance{} = inst) do
    %{
      npc_id: inst.npc_id,
      definition: inst.personality || %{},
      runtime_state: inst.runtime_state || %{}
    }
  end

  defp npc_id(%{npc_id: id}), do: id
  defp npc_id(%{"npc_id" => id}), do: id

  defp runtime(%{runtime_state: state}), do: state
  defp runtime(%{"runtime_state" => state}), do: state

  # `seed` has the session id and the world tick the session starts at.
  defp insert_instance!(%{session_id: session_id, world_tick: world_tick}, npc_id, definition) do
    location_id = Map.get(definition, "default_location_id", "weary_pilgrim")

    runtime =
      %{
        "location_id" => location_id,
        "mood" => get_in(definition, ["motivations", "mood"]) || "neutral",
        "relationship_score" => 0.0,
        "memories" => [],
        "since_tick" => world_tick,
        "stock" => seed_stock(definition),
        "resources" => definition["resources"] || %{},
        "public_facts" => definition["public_facts"] || []
      }
      |> maybe_seed_concern_tick(definition, world_tick)

    %NpcInstance{}
    |> NpcInstance.changeset(%{
      game_session_id: session_id,
      npc_id: npc_id,
      personality: definition,
      runtime_state: runtime,
      disposition: 0.0
    })
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:game_session_id, :npc_id]
    )
  end

  defp maybe_seed_concern_tick(runtime, definition, world_tick) do
    case get_in(definition, ["motivations", "current_concern"]) do
      %{} = concern ->
        Map.put(runtime, "current_concern", Map.put(concern, "since_tick", world_tick))

      _ ->
        runtime
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

  defp persist_memory(%NpcInstance{} = inst, summary, world_tick) do
    entry = %{
      "summary" => String.trim(summary),
      "tick" => world_tick,
      "at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    memories =
      inst.runtime_state
      |> Map.get("memories", [])
      |> Kernel.++([entry])
      |> Enum.take(-@memory_limit)

    inst
    |> update_runtime!(Map.put(inst.runtime_state, "memories", memories))

    :ok
  end

  defp update_runtime!(%NpcInstance{} = inst, runtime_state) do
    inst
    |> NpcInstance.changeset(%{runtime_state: runtime_state})
    |> Repo.update!()
  end

  defp prompt_npc_context(%NpcInstance{} = inst) do
    definition = inst.personality || %{}
    runtime = inst.runtime_state || %{}
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

  defp recent_memories(%NpcInstance{} = inst) do
    visible_memories(Map.get(inst.runtime_state || %{}, "memories", []))
  end

  defp seed_stock(definition) do
    definition
    |> Map.get("stock", [])
    |> TalesForge.Game.Inventory.normalize_stock()
  end

  defp definition_stock(%NpcInstance{} = inst) do
    inst.personality
    |> Map.get("stock", [])
    |> TalesForge.Game.Inventory.normalize_stock()
  end

  defp load_definition_file(file) do
    npc_dir()
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
  end

  defp maybe_escalate_concern(waiting, concern) when waiting >= 4 do
    priority = min(10, Map.get(concern, "priority", 5) + 1)
    maybe_escalate_concern(waiting - 4, Map.put(concern, "priority", priority))
  end

  defp maybe_escalate_concern(waiting, concern), do: {waiting, concern}

  defp initiative_emitted?(%NpcInstance{} = inst),
    do: Map.get(inst.runtime_state, "initiative_emitted", false)

  defp maybe_reset_initiative_emitted(runtime, old_priority, new_priority)
       when new_priority > old_priority do
    runtime
    |> Map.put("initiative_emitted", false)
    |> Map.delete("initiative_emitted_at_tick")
  end

  defp maybe_reset_initiative_emitted(runtime, _old_priority, _new_priority), do: runtime

  # Resolved at runtime (not a module attribute): in a release priv is not at its build path.
  defp npc_dir, do: Path.join(:code.priv_dir(:ex_tales_forge), "npcs")
end
