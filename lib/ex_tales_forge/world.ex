defmodule TalesForge.World do
  @moduledoc """
  World agents prototype (`WORLD_AGENTS=on`, default off; design sketch in
  `docs/design-world-agents.md`).

  Persons, locations (nested: Valley Inn < Tin Valley village < Tin Valley)
  and items are `TalesForge.World.Agent` processes holding their own facts.
  Each turn:

  1. `collect/2` (step `turn.world_facts`, call_type function): start or find
     the agents relevant to this turn: the location chain of where the
     character is, the persons present, the items they hold; return their
     state in budget order (here, persons, parent locations).
  2. `prompt_section/1`: at most #{12} facts / #{1_200} characters, as typed
     lines in the per-turn section only (never the cached prefix).
  3. `TalesForge.World.Prices` (step `turn.prices`): prices the player's
     words mention are quoted, or charged, by the server, not the GM.
  4. After the turn, off the critical path, `TalesForge.World.Extract` (one
     small LLM call, purpose `fact_extract`, conv id `<session>:facts`) reads
     the finished narration for new facts and promises. `validate_facts/3`
     checks them, `store_facts/3` persists them as `world_fact` session
     events (player_aware false) and `commit/3` hands them to the running
     agents; a restarted agent rehydrates them from those events.

  Pack facts come from `priv/adventures/<id>/world_agents.json`; a pack
  without one gets agents with no pack facts (GM facts still accumulate).
  """

  require Logger

  defmodule Lookup do
    @moduledoc """
    What `TalesForge.World.collect/2` reads once per turn to build each
    agent's initial state: the session, the pack definitions, the stored GM
    facts, the moods, the person names and the world map.
    """

    @enforce_keys [:session_id, :defs, :stored, :moods, :names, :world]
    defstruct [:session_id, :defs, :stored, :moods, :names, :world]

    @type t :: %__MODULE__{
            session_id: String.t(),
            defs: map(),
            stored: map(),
            moods: map(),
            names: map(),
            world: map()
          }
  end

  alias TalesForge.GameCharacter.Rows

  alias TalesForge.Config
  alias TalesForge.Game.World, as: GameWorld
  alias TalesForge.Repo
  alias TalesForge.Schemas.SessionEvent
  alias TalesForge.World.{Agent, AgentSpec, Budget}

  import Ecto.Query

  @max_facts 12
  @max_chars 1_200
  @gm_facts_per_entity 4
  @kinds ~w(fact price promise)
  @fact_event "world_fact"

  @typedoc """
  A collected agent: the `TalesForge.World.Agent` state as a plain map plus
  its `:role` this turn (`:here`, `:present`, `:held` or `:around`).
  """
  @type agent :: %{
          required(:id) => String.t(),
          required(:kind) => :person | :location | :item,
          required(:name) => String.t(),
          required(:facts) => [fact()],
          required(:role) => :here | :present | :held | :around,
          optional(atom()) => term()
        }

  @typedoc ~s(A fact: `%{"kind" => "fact" | "price" | "promise", "text" => ..., "source" => "pack" | "narration", ...}`.)
  @type fact :: %{optional(String.t()) => term()}

  @typedoc "A validated new fact and the id of the entity that owns it."
  @type accepted :: {String.t(), fact()}

  @doc "True when `WORLD_AGENTS` is on."
  @spec enabled?() :: boolean()
  def enabled?, do: Config.world_agents?()

  @doc "The fact kinds an agent can hold."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Pack definitions for an adventure: `%{locations: %{id => def}, persons: ..., items: ...}`."
  @spec definitions(String.t() | nil) :: %{locations: map(), persons: map(), items: map()}
  def definitions(adventure_id) when is_binary(adventure_id) do
    key = {__MODULE__, :defs, adventure_id}

    case :persistent_term.get(key, nil) do
      nil ->
        defs = load_definitions(adventure_id)
        :persistent_term.put(key, defs)
        defs

      defs ->
        defs
    end
  end

  def definitions(_adventure_id), do: %{locations: %{}, persons: %{}, items: %{}}

  defp load_definitions(adventure_id) do
    path =
      Path.join([
        :code.priv_dir(:ex_tales_forge),
        "adventures",
        adventure_id,
        "world_agents.json"
      ])

    raw = if File.exists?(path), do: path |> File.read!() |> Jason.decode!(), else: %{}

    by_id = fn key -> raw |> Map.get(key, []) |> Map.new(&{&1["id"], &1}) end

    %{
      locations: with_parents(by_id.("locations"), pack_parents(adventure_id)),
      persons: by_id.("persons"),
      items: by_id.("items")
    }
  end

  # The place files are the one source of the tree (board card 7aba0394):
  # `parent` comes from the pack, the facts from world_agents.json.
  defp pack_parents(adventure_id) do
    TalesForge.Game.Pack.parents(adventure_id)
  rescue
    ArgumentError -> %{}
  end

  defp with_parents(locations, parents) do
    Enum.reduce(parents, locations, fn {id, parent}, acc ->
      Map.update(acc, id, %{"id" => id, "parent" => parent}, &Map.put(&1, "parent", parent))
    end)
  end

  # --- 1. collect ------------------------------------------------------------------

  @doc """
  The agents relevant to this turn, started lazily, as plain maps in budget
  order, each with a `:role` (`:here`, `:present`, `:held` or `:around`).
  """
  @spec collect(String.t(), map()) :: [agent()]
  def collect(session_id, world) do
    %Lookup{defs: defs} = lookup = lookup(session_id, world)
    defs |> specs(world) |> Enum.flat_map(&start(&1, lookup))
  end

  # The agents the turn needs, in budget order, each once (pure).
  defp specs(defs, world) do
    [here | parents] = location_chain(defs, get_in(world, ["character", "location_id"]))

    [
      {[here], :here, :location},
      {List.wrap(world["present_npcs"]), :present, :person},
      {held(defs, world), :held, :item},
      {parents, :around, :location}
    ]
    |> Enum.flat_map(fn {ids, role, kind} ->
      for id <- ids, id != nil, do: %AgentSpec{id: id, role: role, kind: kind}
    end)
    |> Enum.uniq_by(& &1.id)
  end

  defp held(defs, world) do
    world
    |> get_in(["character", "inventory"])
    |> List.wrap()
    |> Enum.map(&item_id/1)
    |> Enum.filter(&Map.has_key?(defs.items, &1))
  end

  # Starts or finds the agent (the process edge) and returns its state.
  defp start(%AgentSpec{} = spec, lookup) do
    case lookup |> initial_state(spec.id, spec.kind) |> ensure() do
      {:ok, pid} -> [pid |> Agent.state() |> Map.from_struct() |> Map.put(:role, spec.role)]
      :error -> []
    end
  end

  defp lookup(session_id, world) do
    %Lookup{
      session_id: session_id,
      defs: definitions(world["adventure_id"]),
      stored: stored_facts(session_id),
      moods: session_id |> TalesForge.Characters.cast() |> TalesForge.Game.Cast.reactions(),
      names: if(List.wrap(world["present_npcs"]) == [], do: %{}, else: person_names(session_id)),
      world: world
    }
  end

  defp location_chain(_defs, nil), do: [nil]

  defp location_chain(defs, id) do
    Stream.unfold(id, fn
      nil -> nil
      current -> {current, get_in(defs.locations, [current, "parent"])}
    end)
    |> Enum.take(5)
  end

  defp person_names(session_id) do
    session_id
    |> Rows.list()
    |> Map.new(&{&1.npc_id, get_in(&1.personality, ["name"]) || &1.npc_id})
  end

  defp item_id(%{"id" => id}), do: id
  defp item_id(id) when is_binary(id), do: id
  defp item_id(_), do: nil

  defp initial_state(%Lookup{} = lookup, id, kind) do
    definition = definition(lookup.defs, id, kind)
    pack_facts = Enum.map(definition["facts"] || [], &Map.put(&1, "source", "pack"))

    %Agent{
      session_id: lookup.session_id,
      id: id,
      kind: kind,
      name: definition["name"] || runtime_name(lookup, id, kind) || id,
      parent: definition["parent"],
      facts: pack_facts ++ Map.get(lookup.stored, id, []),
      mood: if(kind == :person, do: lookup.moods[id])
    }
  end

  defp definition(defs, id, :location), do: Map.get(defs.locations, id, %{})
  defp definition(defs, id, :person), do: Map.get(defs.persons, id, %{})
  defp definition(defs, id, :item), do: Map.get(defs.items, id, %{})

  defp runtime_name(lookup, id, :location),
    do: GameWorld.runtime_location(lookup.world, id)["name"]

  defp runtime_name(lookup, id, :person), do: lookup.names[id]
  defp runtime_name(_lookup, _id, :item), do: nil

  defp ensure(%Agent{} = initial) do
    case Agent.whereis(initial.session_id, initial.id) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        case DynamicSupervisor.start_child(TalesForge.World.Supervisor, {Agent, initial}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> log_error(initial, other)
        end
    end
  catch
    :exit, reason -> log_error(initial, reason)
  end

  defp log_error(initial, reason) do
    Logger.warning("world agent unavailable id=#{initial.id} reason=#{inspect(reason)}")
    :error
  end

  # --- 2. prompt -------------------------------------------------------------------

  @doc """
  The prompt lines for the collected agents, within the fact and character
  budget (`TalesForge.Prompt.Sections.WorldFacts`).
  """
  @spec prompt_lines([agent()]) :: [String.t()]
  def prompt_lines(agents) when is_list(agents) do
    agents |> Enum.reduce(%Budget{}, &add_agent(&2, &1)) |> Map.fetch!(:lines) |> Enum.reverse()
  end

  # Adds the agent's line when its facts fit the budget left.
  defp add_agent(%Budget{} = budget, agent) do
    texts = agent |> budget_facts(@max_facts - budget.count) |> Enum.map(&fact_text/1)
    size = texts |> Enum.map(&String.length/1) |> Enum.sum()

    if texts == [] or budget.chars + size > @max_chars,
      do: budget,
      else: %Budget{
        lines: [line(agent, texts) | budget.lines],
        count: budget.count + length(texts),
        chars: budget.chars + size
      }
  end

  defp budget_facts(_agent, left) when left <= 0, do: []

  defp budget_facts(agent, left) do
    {pack, gm} = Enum.split_with(agent.facts, &(&1["source"] == "pack"))
    Enum.take(pack ++ Enum.take(gm, -@gm_facts_per_entity), left)
  end

  defp fact_text(%{"kind" => "promise", "text" => text} = f),
    do: "promised: #{text}#{turn_suffix(f)}"

  defp fact_text(%{"source" => "narration", "text" => text} = f), do: text <> turn_suffix(f)
  defp fact_text(%{"text" => text}), do: text

  defp turn_suffix(%{"turn" => turn}) when is_integer(turn), do: " (turn #{turn})"
  defp turn_suffix(_), do: ""

  defp line(agent, texts) do
    role =
      case agent.role do
        :here -> "here"
        :present -> "present"
        :held -> "carried"
        :around -> "around"
      end

    "- #{agent.name} [#{agent.id}] (#{role}): " <> Enum.join(texts, "; ")
  end

  # --- 3. new facts ---------------------------------------------------------------

  @doc """
  Validates new facts (`%{"about", "kind", "text"}`, from the extraction call)
  against this turn's agents. Returns `{accepted, rejected}`; accepted is
  `[{entity_id, fact}]`, rejected is `[{new_fact, reason}]`.
  """
  @spec validate_facts([agent()], [map()], integer()) :: {[accepted()], [{map(), atom()}]}
  def validate_facts(_agents, [], _turn_number), do: {[], []}

  def validate_facts(agents, new_facts, turn_number) do
    {accepted_rev, rejected_rev, _seen} =
      Enum.reduce(new_facts, {[], [], MapSet.new()}, &sort_fact(&1, &2, {agents, turn_number}))

    {Enum.reverse(accepted_rev), Enum.reverse(rejected_rev)}
  end

  # Adds one proposed fact to the accepted or the rejected list.
  defp sort_fact(nf, {acc, rej, seen}, {agents, turn_number}) do
    case validate(nf, agents, seen) do
      {:ok, id, fact} ->
        fact = Map.put(fact, "turn", turn_number)

        {[{id, fact} | acc], rej, MapSet.put(seen, {id, normalize(fact["text"])})}

      {:error, reason} ->
        {acc, [{nf, reason} | rej], seen}
    end
  end

  @doc "Persists accepted facts as `world_fact` session events (never shown to the player)."
  @spec store_facts(String.t(), [accepted()], integer() | nil) :: :ok
  def store_facts(_session_id, [], _tick), do: :ok

  def store_facts(session_id, accepted, tick) do
    Enum.each(accepted, fn {id, fact} ->
      %SessionEvent{}
      |> SessionEvent.changeset(%{
        game_session_id: session_id,
        kind: @fact_event,
        actor: "world",
        player_aware: false,
        tick: tick || 0,
        payload: %{"entity_id" => id, "fact" => fact}
      })
      |> Repo.insert!()
    end)
  end

  @doc "The session's stored facts by entity id, oldest first."
  @spec stored_facts(String.t()) :: %{String.t() => [fact()]}
  def stored_facts(session_id) do
    Repo.all(
      from e in SessionEvent,
        where: e.game_session_id == ^session_id and e.kind == ^@fact_event,
        order_by: [asc: e.inserted_at],
        select: e.payload
    )
    |> Enum.group_by(& &1["entity_id"], & &1["fact"])
  end

  defp validate(nf, agents, seen) do
    text = nf["text"] |> to_string() |> String.trim()
    kind = if nf["kind"] in @kinds, do: nf["kind"], else: "fact"

    with {:ok, agent} <- resolve(nf["about"], agents),
         :ok <- check(text != "", :empty),
         :ok <- check(kind != "promise" or agent.kind == :person, :promise_not_person),
         :ok <- check(not duplicate?(agent, text, seen), :duplicate),
         :ok <- check(kind != "price" or not price_conflict?(agents, text), :price_conflict) do
      {:ok, agent.id, %{"kind" => kind, "text" => text, "source" => "narration"}}
    end
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp resolve(about, agents) do
    # The prompt shows ids as "[valley_inn]"; the GM sometimes copies the brackets.
    key =
      about
      |> to_string()
      |> String.trim()
      |> String.trim("[")
      |> String.trim("]")
      |> String.downcase()

    found =
      if key == "here",
        do: Enum.find(agents, &(&1.role == :here)),
        else:
          Enum.find(agents, &(String.downcase(&1.id) == key)) ||
            Enum.find(agents, &(String.downcase(to_string(&1.name)) == key))

    if found, do: {:ok, found}, else: {:error, :unknown_entity}
  end

  defp duplicate?(agent, text, seen) do
    norm = normalize(text)

    MapSet.member?(seen, {agent.id, norm}) or
      Enum.any?(agent.facts, &(normalize(&1["text"]) == norm))
  end

  # A price for something that already has one, on any of this turn's agents,
  # is rejected: the pack (or the first stored price) wins. "Private room:
  # 3 silver" vs "Room for the night: 2 silver"; the inn's stew vs "Stew" on Brenna.
  defp price_conflict?(agents, text) do
    new_key = price_key(text)

    agents
    |> Enum.flat_map(& &1.facts)
    |> Enum.filter(&(&1["kind"] == "price"))
    |> Enum.any?(&(not MapSet.disjoint?(price_key(&1["text"]), new_key)))
  end

  @stop ~w(a an the of for per and with night nights one bowl mug)
  defp price_key(text) do
    text
    |> to_string()
    |> String.split(":", parts: 2)
    |> hd()
    |> String.downcase()
    |> String.split(~r/[^a-z]+/, trim: true)
    |> Enum.reject(&(&1 in @stop or String.length(&1) < 3))
    |> Enum.map(&String.trim_trailing(&1, "s"))
    |> MapSet.new()
  end

  defp normalize(text),
    do:
      text
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, " ")
      |> String.trim()

  # --- 4. commit -------------------------------------------------------------------

  @doc "After the turn is persisted: accepted facts and new moods go to the running agents."
  @spec commit(String.t(), [accepted()], [map()]) :: :ok
  def commit(session_id, accepted, reactions) do
    accepted
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {id, facts} -> call(session_id, id, &Agent.add_facts(&1, facts)) end)

    Enum.each(reactions, fn r ->
      mood = Map.take(r, ~w(emotion intensity stance confidence turn_number))
      call(session_id, r["npc_id"], &Agent.put_mood(&1, mood))
    end)

    :ok
  end

  defp call(session_id, id, fun) do
    case Agent.whereis(session_id, id) do
      nil -> :ok
      pid -> fun.(pid)
    end
  catch
    :exit, _ -> :ok
  end
end
