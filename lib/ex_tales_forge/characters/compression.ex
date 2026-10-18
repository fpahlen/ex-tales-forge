defmodule TalesForge.Characters.Compression do
  @moduledoc """
  Character memory, PR 2 (board card 845b6b15): short-term to long-term.

  One typed Jev call per character that has new short-term rows. Jev reads
  the rows, the interests, OCEAN and mood, and answers per association (a
  person, place or item id): a weight, a feeling, a belief that can be wrong,
  and the row the character remembers best. Elixir writes the gist from that
  answer: about 20 words at most, with the core of a promise or deal first.
  Exact numbers stay in game data.

  Every kind of row is compressed (Fredrik's answer 5: a memory is always the
  character's interpretation). Rows of engine events (`turn.*`,
  `player.dawdled`) stay out of the call. Compressed short-term rows and faded
  long-term rows get the tier `faded`. Strong feelings fade slower.

  When it runs (option 4 of Q3, Fredrik's answer 1): on a long rest, or at the
  next scene end after dawn when a game day passed with no compression.

      iex> TalesForge.Characters.Compression.dawn_between?(90, 100)
      true
      iex> TalesForge.Characters.Compression.dawn_between?(10, 90)
      false
      iex> TalesForge.Characters.Compression.gist("warm", "Mags promised to help me find the lost ore cart near the old adit tomorrow at first light without fail ever")
      "warm: Mags promised to help me find the lost ore cart near the old adit tomorrow at first light…"
  """

  import Ecto.Query
  require Logger

  alias TalesForge.AICalls
  alias TalesForge.Characters
  alias TalesForge.Characters.Memory
  alias TalesForge.Game.WorldClock
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, CharacterMemory, SessionEvent}

  @model "jev-1.13.0"
  @dawn_slot 4
  @max_assoc 6
  @max_rows 10
  @gist_words 20
  @fade_below 0.25
  @strong ~w(grateful afraid angry resentful)a
  @engine_kind ~r/^(turn\.|player\.dawdled)/

  @weights [
    "Unimportant to this character",
    "A small thing",
    "Worth remembering",
    "Important to this character",
    "Changes how this character sees the world"
  ]
  @feelings %{
    warm: "Warm, fond",
    grateful: "Grateful",
    curious: "Curious",
    indifferent: "Indifferent",
    uneasy: "Uneasy",
    afraid: "Afraid",
    angry: "Angry",
    resentful: "Resentful"
  }
  @beliefs %{
    none: "No belief beyond what happened",
    ally: "`about` is on my side",
    threat: "`about` is a danger to me",
    dishonest: "`about` is not honest with me",
    owes_me: "`about` owes me",
    i_owe: "I owe `about`",
    valuable: "`about` is worth a lot to me",
    worthless: "`about` is not worth my time"
  }
  @belief_text %{
    ally: "is on my side",
    threat: "is a danger to me",
    dishonest: "is not honest with me",
    owes_me: "owes me",
    valuable: "is worth a lot to me",
    worthless: "is not worth my time"
  }
  @row_labels for i <- 0..(@max_rows - 1), do: :"r#{i}"
  @names (for i <- 0..(@max_assoc - 1) do
            {i,
             %{
               weight: :"a#{i}_weight",
               feeling: :"a#{i}_feeling",
               belief: :"a#{i}_belief",
               key: :"a#{i}_key"
             }}
          end)
         |> Map.new()

  defmodule Trigger do
    @moduledoc """
    What the turn brings for compression: a long rest, a scene end, and the
    world tick `now`.
    """
    defstruct long_rest: false, scene_end: false, now: nil

    @typedoc "A long rest and/or a scene end at tick `now`."
    @type t :: %__MODULE__{long_rest: boolean(), scene_end: boolean(), now: integer() | nil}
  end

  defmodule Outcome do
    @moduledoc false
    # One character's compression: the short-term `rows` it read, the `long`
    # rows it writes, at tick `now`.
    defstruct [:rows, :long, :now]
  end

  # -- timing ---------------------------------------------------------------

  @doc "True when a dawn (slot #{@dawn_slot}) lies in `(from, to]`."
  @spec dawn_between?(integer(), integer()) :: boolean()
  def dawn_between?(from, to) when to <= from, do: false

  def dawn_between?(from, to) do
    day = WorldClock.ticks_per_day()
    same_day = div(from, day) * day + @dawn_slot
    next_dawn = if same_day <= from, do: same_day + day, else: same_day
    next_dawn <= to
  end

  @doc """
  True when compression is due for a character: on a long rest, or at a scene
  end when a dawn and one game day lie between `since` and the trigger's `now`.
  """
  @spec due?(Trigger.t(), integer() | nil) :: boolean()
  def due?(%Trigger{long_rest: true}, _since), do: true
  def due?(%Trigger{scene_end: false}, _since), do: false
  def due?(%Trigger{}, nil), do: false

  def due?(%Trigger{now: now}, since),
    do: now - since >= WorldClock.ticks_per_day() and dawn_between?(since, now)

  @doc """
  After the turn commits: compresses every due character of the session in a
  task (inline when `:character_memory_compress` is `:sync`). Options: `:now`
  (the world tick; nil does nothing) and `:mode` (the CHARACTER_MEMORY mode;
  `:off` does nothing). Always `:ok`.
  """
  @spec after_turn(Ecto.UUID.t(), [map()], keyword()) :: :ok
  def after_turn(session_id, events, opts) do
    now = Keyword.get(opts, :now)

    if now != nil and Keyword.get(opts, :mode, :off) != :off,
      do: compress_due(session_id, events, now),
      else: :ok
  end

  defp compress_due(session_id, events, now) do
    trigger = %Trigger{
      long_rest: Memory.long_rest_in?(events),
      scene_end: Memory.scene_end(events) != nil,
      now: now
    }

    if trigger.long_rest or trigger.scene_end do
      fun = fn -> run(session_id, trigger) end

      case Application.get_env(:ex_tales_forge, :character_memory_compress, :async) do
        :sync -> fun.()
        _ -> Task.Supervisor.start_child(TalesForge.Playtest.Supervisor, fun)
      end
    end

    :ok
  rescue
    e ->
      Logger.warning("memory compression failed session=#{session_id} #{Exception.message(e)}")
      :ok
  end

  @doc false
  def run(session_id, %Trigger{} = trigger) do
    for c <- Characters.list_for_session(session_id),
        rows = eligible_rows(c),
        rows != [],
        due?(trigger, since(c, rows)) do
      compress(c, rows, trigger.now)
    end

    :ok
  end

  # Old rows count as short-term: before the first compression the clock
  # starts at the oldest short-term row.
  defp since(%Character{memory_compressed_tick: t}, _rows) when is_integer(t), do: t

  defp since(_c, rows),
    do: rows |> Enum.map(& &1.tick) |> Enum.reject(&is_nil/1) |> Enum.min(fn -> nil end)

  @doc "The short-term rows of a character, without rows of engine events."
  @spec eligible_rows(Character.t()) :: [CharacterMemory.t()]
  def eligible_rows(%Character{id: id}) do
    CharacterMemory
    |> where([m], m.character_id == ^id and m.tier == "short")
    |> join(:left, [m], e in SessionEvent, on: e.id == m.session_event_id)
    |> select([m, e], {m, e.kind})
    |> order_by([m], asc: m.tick, asc: m.inserted_at)
    |> Repo.all()
    |> Enum.reject(fn {m, kind} -> engine?(kind) or engine?(m.text) end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "True for the kind (or row text) of an engine event."
  @spec engine?(String.t() | nil) :: boolean()
  def engine?(text) when is_binary(text), do: Regex.match?(@engine_kind, text)
  def engine?(_), do: false

  # -- one character ---------------------------------------------------------

  @doc """
  Compresses one character's rows with one Jev call. Without a TypeSafe key
  nothing changes. Rows about no one else (no associations) make no call:
  there is nothing to ask, so they fade with no long-term row, which is what
  a call would give. Returns `:ok` or `{:error, reason}`.
  """
  @spec compress(Character.t(), [CharacterMemory.t()], integer()) :: :ok | {:error, term()}
  def compress(%Character{} = c, rows, now) do
    with true <- configured?() || {:error, :jev_not_configured},
         {:ok, long} <- long_term(c, associations(rows, c.slug), now) do
      write(c, %Outcome{rows: rows, long: long, now: now})
    end
  end

  # Jev requires at least one question, and with no associations there is none.
  defp long_term(_c, [], _now), do: {:ok, []}

  defp long_term(c, groups, now) do
    with {:ok, reply, timing} <- call_jev(state(c, groups), questions(groups)) do
      record_usage(c, reply, timing)
      {:ok, long_rows(groups, reply, now)}
    end
  end

  @doc """
  The associations of a set of rows: `[{about_id, [row]}]`, the heaviest
  first, at most #{@max_assoc}, at most #{@max_rows} rows each. The
  character's own slug is no association.
  """
  @spec associations([CharacterMemory.t()], String.t() | nil) :: [{String.t(), list()}]
  def associations(rows, own) do
    rows
    |> Enum.flat_map(fn r -> for a <- r.about || [], a != own, do: {a, r} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(&heaviest_first/1)
    |> Enum.take(@max_assoc)
    |> Enum.map(fn {a, rs} -> {a, Enum.take(Enum.reverse(rs), @max_rows)} end)
  end

  # The sort key of an association: its total row weight, heaviest first,
  # then its id.
  defp heaviest_first({about, rows}), do: {-Enum.sum_by(rows, &(&1.weight || 1.0)), about}

  @doc false
  def state(%Character{} = c, groups) do
    %{
      character: %{
        name: c.name,
        role: c.role,
        mood: c.mood,
        ocean: ocean(c.ocean),
        interests: Memory.interests(c)
      },
      associations:
        for {{about, rs}, i} <- Enum.with_index(groups) do
          %{
            index: i,
            about: about,
            rows:
              for {r, j} <- Enum.with_index(rs) do
                %{label: "r#{j}", text: r.text, felt: r.felt, kind: r.kind}
              end
          }
        end
    }
  end

  @doc false
  def questions(groups) do
    groups
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_about, rs}, i} ->
      n = @names[i]
      ref = "`associations[#{i}]`"

      [
        {n.weight,
         {"As `character`, with these interests and this personality: how much do the rows of #{ref} matter?",
          @weights}},
        {n.feeling,
         {"How does `character` feel about #{ref}.about after these rows?", @feelings}},
        {n.belief,
         {"What does `character` come to believe about #{ref}.about? The belief can be wrong; it follows the character's interests and mood.",
          @beliefs}},
        length(rs) > 1 &&
          {n.key,
           {"Which row of #{ref} does `character` remember best?",
            Map.new(Enum.take(@row_labels, length(rs)), &{&1, nil})}}
      ]
      |> Enum.filter(& &1)
    end)
  end

  @doc """
  The long-term rows from a Jev reply, as attrs: one per association that
  does not fade.
  """
  @spec long_rows([{String.t(), list()}], map(), integer()) :: [map()]
  def long_rows(groups, reply, now) do
    groups
    |> Enum.with_index()
    |> Enum.flat_map(fn {{about, rs}, i} ->
      n = @names[i]
      feeling = Map.get(reply, n.feeling) || :indifferent
      level = Map.get(reply, n.weight) || 0.0
      weight = level / (length(@weights) - 1) * if(feeling in @strong, do: 1.5, else: 1.0)
      key = key_row(rs, Map.get(reply, n.key))
      core = promise_row(rs) || key

      if weight < @fade_below do
        []
      else
        [
          %{
            kind: if(core.kind == "promise", do: "promise", else: "memory"),
            tier: "long",
            text: gist(to_string(feeling), core.text),
            felt: to_string(feeling),
            belief: belief(about, Map.get(reply, n.belief)),
            about: [about],
            weight: Float.round(weight, 3),
            tick: now
          }
        ]
      end
    end)
  end

  @doc "A gist of at most #{@gist_words} words: the feeling, then the text."
  @spec gist(String.t(), String.t()) :: String.t()
  def gist(feeling, text) do
    words = String.split(text || "")

    body =
      if length(words) > @gist_words - 1,
        do: Enum.join(Enum.take(words, @gist_words - 2), " ") <> "…",
        else: Enum.join(words, " ")

    "#{feeling}: #{body}"
  end

  defp key_row(rs, label) do
    index =
      case label && Atom.to_string(label) do
        "r" <> n -> String.to_integer(n)
        _ -> length(rs) - 1
      end

    Enum.at(rs, index) || List.last(rs)
  end

  # A promise or a deal keeps its core in the gist.
  defp promise_row(rs) do
    Enum.find(rs, fn r ->
      r.kind == "promise" or Regex.match?(~r/\b(promis\w*|deal|agree\w*|owe\w*)\b/i, r.text || "")
    end)
  end

  defp belief(_about, nil), do: nil
  defp belief(_about, :none), do: nil
  defp belief(about, :i_owe), do: "I owe #{about}"
  defp belief(about, label), do: "#{about} #{Map.fetch!(@belief_text, label)}"

  defp write(c, %Outcome{rows: rows, long: long, now: now}) do
    Repo.transaction(fn ->
      fade_long!(c)
      Enum.each(long, &({:ok, _} = Characters.add_memory(c, &1)))

      ids = Enum.map(rows, & &1.id)
      Repo.update_all(from(m in CharacterMemory, where: m.id in ^ids), set: [tier: "faded"])

      c |> Ecto.Changeset.change(memory_compressed_tick: now) |> Repo.update!()
    end)

    :ok
  end

  # Long-term rows lose weight at each compression; strong feelings slower.
  defp fade_long!(c) do
    CharacterMemory
    |> where([m], m.character_id == ^c.id and m.tier == "long")
    |> Repo.all()
    |> Enum.each(fn m ->
      factor = if m.felt in Enum.map(@strong, &to_string/1), do: 0.9, else: 0.7
      weight = Float.round(m.weight * factor, 3)
      tier = if weight < @fade_below, do: "faded", else: "long"
      m |> Ecto.Changeset.change(weight: weight, tier: tier) |> Repo.update!()
    end)
  end

  # -- Jev -------------------------------------------------------------------

  defp configured? do
    case Application.get_env(:jev, :api_key) do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  defp call_jev(state, questions) do
    started_at = DateTime.utc_now()
    t0 = System.monotonic_time(:millisecond)

    case Jev.HTTP.post(state, questions, model: @model) do
      {:ok, reply} ->
        {:ok, reply,
         %{started_at: started_at, latency_ms: System.monotonic_time(:millisecond) - t0}}

      {:error, reason} ->
        {:error, {:jev, reason}}
    end
  end

  defp record_usage(c, reply, timing) do
    usage = Map.get(reply, :usage) || %{}
    input = usage[:input_tokens] || 0

    cost_micro =
      case usage[:cost] do
        cost when is_number(cost) -> round(cost * 1_000_000)
        _ -> round(input * 0.042)
      end

    AICalls.record(%{
      purpose: "memory.compress",
      call_type: "jev",
      model: Map.get(reply, :model) || @model,
      status: "ok",
      latency_ms: timing.latency_ms,
      started_at: timing.started_at,
      game_session_id: c.game_session_id,
      usage: %{input_tokens: input, output_tokens: 0, cost_ticks: cost_micro * 10_000}
    })
  end

  defp ocean(nil), do: %{}
  defp ocean(%_{} = o), do: o |> Map.from_struct() |> Map.drop([:__meta__, :id])
  defp ocean(o) when is_map(o), do: o
end
