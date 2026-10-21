defmodule TalesForge.Game.NpcReactions do
  @moduledoc """
  Prototype (`NPC_REACTIONS=on`, default off): an NPC's gut reaction (System 1)
  read by TypeSafe Jev **before** the GM call, so the GM's lines for that NPC
  follow a typed reaction instead of repeating the same brush-off.

  For each NPC present (at most #{4}), one Jev call, all concurrently
  (`Task.async_stream`, short timeout). Input, player-visible only:

  - the NPC's name, role, personality text and OCEAN scores (0–10);
  - her mood before this moment (the previous reaction, or neutral);
  - the narration the player last heard (latest turn or scene);
  - the player character's words/action this turn, and how the attempt came
    across (the server's outcome, e.g. a failed persuasion). Outcomes of
    checks the NPC cannot see (insight, history, arcana, tracking, survival,
    tactics) are left out, so a failed read never makes her warier.

  Never the GM's raw reply, secrets, hidden events or memories marked secret.

  Output per NPC, a typed reaction: `emotion` (fixed labels), `intensity`
  0.0–1.0, `stance` (hostile, cool, neutral, warm, friendly) and `confidence`
  (the lower of Jev's emotion and stance confidences). A timeout or error
  means no reaction for that NPC; the turn goes on.

  The reactions go to the GM as one short line per NPC in the per-turn section
  (`prompt_section/1`); the mood carries over on the NPC's character
  (`runtime["reaction"]`, `TalesForge.Game.Cast.reactions/1`), applied by
  the turn as `{:feel, mood}` Intentions (`intentions/1`). Each call is an `ai_calls` row with
  call_type `jev`, purpose `npc_reaction`.
  """

  require Logger

  import Ecto.Query
  alias TalesForge.GameCharacter.Rows

  alias TalesForge.AICalls
  alias TalesForge.Config
  alias TalesForge.Game.Cast
  alias TalesForge.Intention
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Scene, Turn}

  defmodule Moment do
    @moduledoc """
    The moment the NPCs react to (`TalesForge.Game.NpcReactions.react/1`):
    the session, the world, the session's cast (`TalesForge.Game.Cast`),
    the turn number, the player's words, the mechanical outcome and the
    premise findings. `react/1` adds the moods
    before it, the scene the NPCs saw and heard, and the call timeout.
    """

    @enforce_keys [:session_id, :world, :turn_number, :raw_action, :mechanical]
    defstruct @enforce_keys ++ [cast: %{}, findings: [], moods: %{}, scene: nil, timeout: nil]

    @type t :: %__MODULE__{
            session_id: String.t(),
            world: map(),
            cast: TalesForge.Game.Cast.t(),
            turn_number: integer(),
            raw_action: String.t(),
            mechanical: struct() | nil,
            findings: [map()] | nil,
            moods: map(),
            scene: map() | nil,
            timeout: non_neg_integer() | nil
          }
  end

  @model "jev-1.13.0"
  @purpose "npc_reaction"
  @max_npcs 4
  @narration_chars 1_200
  @action_chars 600

  @emotions %{
    calm: "Even, unbothered, business as usual",
    curious: "Interested, wants to know more",
    amused: "Finds it funny or charming",
    sympathetic: "Moved, feels for the player character",
    wary: "Guarded, cautious, keeps her distance",
    suspicious: "Doubts their story or motives",
    irritated: "Annoyed, impatient, put out",
    afraid: "Scared or alarmed"
  }

  @intensity ["none", "slight", "moderate", "strong", "intense"]
  @stances ["hostile", "cool", "neutral", "warm", "friendly"]

  @typedoc """
  One NPC's reaction: `"npc_id"`, `"name"`, `"emotion"`, `"intensity"` (0..1),
  `"stance"`, `"stance_score"` (0..1), `"confidence"` and `"turn_number"`.
  """
  @type reaction :: %{optional(String.t()) => term()}

  @doc "The `ai_calls` purpose of a reaction call."
  @spec purpose() :: String.t()
  def purpose, do: @purpose

  @doc "The emotions a reaction can have, sorted."
  @spec emotions() :: [String.t()]
  def emotions, do: @emotions |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort()

  @doc "The stances, from hostile to friendly."
  @spec stances() :: [String.t()]
  def stances, do: @stances

  @doc """
  On when `NPC_REACTIONS` (or `WORLD_AGENTS`, where this is a Person agent's
  System 1 reaction) is on and a TypeSafe key is configured.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: (Config.npc_reactions?() or Config.world_agents?()) and configured?()

  @doc """
  True when a TypeSafe (Jev) API key is configured in `config :jev, :api_key`
  (`config/runtime.exs` sets it from `TYPESAFE_API_KEY` outside test). The OS
  environment is not read here, so tests decide the key with `Application.put_env/3`.
  """
  @spec configured?() :: boolean()
  def configured? do
    case Application.get_env(:jev, :api_key) do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  @doc """
  Reactions of the NPCs present in the world of `moment` this turn; `[]`
  when off, nobody is present, or every call failed. Writes nothing: the
  turn applies the moods as Intentions (`intentions/1`).
  """
  @spec react(Moment.t()) :: [reaction()]
  def react(%Moment{} = moment) do
    case reacting(moment) do
      [] -> []
      npcs -> run_all(npcs, seen(moment))
    end
  end

  @doc """
  Each reaction as a `{:feel, mood}` Intention of its NPC: the mood that
  carries over on the NPC's character (`runtime["reaction"]`).

      iex> [i] = TalesForge.Game.NpcReactions.intentions([%{"npc_id" => "innkeep", "emotion" => "wary", "intensity" => 0.5, "stance" => "cool", "confidence" => 0.7, "turn_number" => 3, "name" => "Brenna"}])
      iex> {i.character_id, i.by, i.action}
      {"innkeep", :system, {:feel, %{"emotion" => "wary", "intensity" => 0.5, "stance" => "cool", "confidence" => 0.7, "turn_number" => 3}}}
  """
  @spec intentions([reaction()]) :: [Intention.t()]
  def intentions(reactions) do
    for r <- reactions do
      mood = Map.take(r, ~w(emotion intensity stance confidence turn_number))
      Intention.system(r["npc_id"], {:feel, mood}, nil)
    end
  end

  # The NPCs that react: present and alive, at most #{@max_npcs};
  # none when off.
  defp reacting(%Moment{session_id: session_id, world: world, cast: cast}) do
    # A dead person does not react (QA 2026-10-15, session 99817343).
    present =
      world["present_npcs"]
      |> List.wrap()
      |> Enum.reject(&Cast.dead?(cast, &1))

    if enabled?() and present != [] do
      session_id
      |> Rows.list()
      |> Enum.filter(&(&1.npc_id in present))
      |> Enum.take(@max_npcs)
    else
      []
    end
  end

  # `moment` with the moods before it, the scene the NPCs saw and heard,
  # and the call timeout.
  defp seen(%Moment{session_id: session_id, world: world} = moment) do
    %{
      moment
      | moods: Cast.reactions(moment.cast),
        scene:
          session_id
          |> situation(moment.raw_action, visible_outcome(moment.mechanical, world))
          |> Map.put(:findings, findings_text(moment.findings)),
        timeout: Config.npc_reactions_timeout_ms()
    }
  end

  defp run_all(npcs, %Moment{session_id: session_id, turn_number: turn_number} = moment) do
    timeout = moment.timeout

    npcs
    |> Task.async_stream(
      &call_one(&1, moment),
      max_concurrency: length(npcs),
      timeout: timeout + 500,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(npcs)
    |> Enum.flat_map(fn
      {{:ok, {:ok, r}}, _inst} ->
        Logger.info(
          "npc reaction session=#{session_id} turn=#{turn_number} npc=#{r["npc_id"]} " <>
            "emotion=#{r["emotion"]} intensity=#{r["intensity"]} stance=#{r["stance"]} " <>
            "stance_score=#{r["stance_score"]} confidence=#{r["confidence"]}"
        )

        [r]

      {{:ok, {:error, reason}}, inst} ->
        Logger.warning("npc reaction failed npc=#{inst.npc_id} reason=#{inspect(reason)}")
        []

      {{:exit, reason}, inst} ->
        Logger.warning("npc reaction timed out npc=#{inst.npc_id} reason=#{inspect(reason)}")
        record({session_id, turn_number}, {"error", timeout + 500}, %{})
        []
    end)
  end

  defp call_one(inst, %Moment{session_id: session_id, turn_number: turn_number} = moment) do
    started = System.monotonic_time(:millisecond)

    result =
      Jev.HTTP.post(
        state(inst, Map.get(moment.moods, inst.npc_id), moment.scene),
        questions(inst),
        model: @model,
        max_retries: 0,
        receive_timeout: moment.timeout
      )

    elapsed = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, reply} ->
        record({session_id, turn_number}, {"ok", elapsed}, reply)
        {:ok, reaction(inst, reply, turn_number)}

      {:error, reason} ->
        record({session_id, turn_number}, {"error", elapsed}, %{})
        {:error, reason}
    end
  rescue
    e -> {:error, {:crashed, Exception.message(e)}}
  end

  # --- input --------------------------------------------------------------------

  @doc false
  @spec situation(String.t(), String.t(), struct() | nil) :: %{
          narration: String.t() | nil,
          action: String.t(),
          outcome: String.t() | nil
        }
  def situation(session_id, raw_action, mechanical) do
    %{
      narration: last_narration(session_id),
      action: raw_action |> to_string() |> String.trim() |> String.slice(0, @action_chars),
      outcome: outcome_text(mechanical)
    }
  end

  @doc false
  @spec state(struct(), map() | nil, map()) :: String.t()
  def state(inst, mood, scene) do
    definition = inst.personality
    traits = get_in(definition, ["motivations", "personality_traits"]) || %{}

    ocean =
      ~w(openness conscientiousness extraversion agreeableness neuroticism)
      |> Enum.map_join(", ", &"#{&1} #{Map.get(traits, &1, "?")}")

    [
      "NPC: #{name(inst)} (#{definition["role"] || inst.npc_id}).",
      definition["personality"] && "Personality: #{definition["personality"]}",
      "OCEAN (0-10): #{ocean}.",
      "Mood before this moment: #{mood_text(mood)}.",
      scene.narration && "What #{name(inst)} last saw and heard (narration):\n#{scene.narration}",
      "What the player character says or does now:\n#{scene.action}",
      scene.outcome && "How it comes across: #{scene.outcome}.",
      Map.get(scene, :findings) &&
        "What the server checked (premise findings; these claims are not true):\n" <>
          scene.findings
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  # NPC_DIALOGUE_MEMORY=on: the NPCs get the premise findings (design §2,
  # stage 4). nil when there are none.
  defp findings_text([]), do: nil
  defp findings_text(nil), do: nil

  defp findings_text(findings),
    do: Enum.map_join(findings, "\n", &("- " <> &1.correction))

  @doc false
  @spec questions(struct()) :: list()
  def questions(inst) do
    n = name(inst)

    [
      emotion:
        {"Which feeling does #{n} most likely have right now, in reaction to what the player character just said or did?",
         @emotions},
      intensity: {"How strong is that feeling in #{n}?", @intensity},
      stance: {"After this moment, what is #{n}'s stance toward the player character?", @stances}
    ]
  end

  @doc """
  The tail of the session's latest GM narration (the last turn's, or the
  opening scene's when it is newer), at most #{@narration_chars} characters, or
  nil before any. Also read by the Jev intent call (`TalesForge.IntentJev`),
  so "him" and "the miner" resolve.
  """
  @spec last_narration(String.t()) :: String.t() | nil
  def last_narration(session_id) do
    turn =
      Repo.one(
        from t in Turn,
          where: t.game_session_id == ^session_id,
          order_by: [desc: t.turn_number],
          limit: 1,
          select: {t.inserted_at, t.narrative}
      )

    scene =
      Repo.one(
        from s in Scene,
          where: s.game_session_id == ^session_id,
          order_by: [desc: s.inserted_at],
          limit: 1,
          select: {s.inserted_at, s.narrative}
      )

    [turn, scene]
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(fn {at, _} -> at end, DateTime, fn -> {nil, nil} end)
    |> elem(1)
    |> case do
      nil -> nil
      text -> String.slice(text, -@narration_chars, @narration_chars)
    end
  end

  # A failed read, search or recall happens in the player character's head:
  # the NPC never sees it, so it must not make her warier (decision
  # 2026-10-07).
  @unseen_skills ~w(insight history arcana tracking survival tactics)

  @doc false
  @spec visible_outcome(struct() | nil, map()) :: struct() | nil
  def visible_outcome(%{skill: skill}, _world) when skill in @unseen_skills, do: nil

  def visible_outcome(mechanical, _world), do: mechanical

  defp outcome_text(%{outcome: outcome} = mechanical) when outcome not in [nil, "none"] do
    case mechanical.skill do
      nil -> to_string(outcome)
      skill -> "#{outcome} (#{skill} attempt)"
    end
  end

  defp outcome_text(_mechanical), do: nil

  defp mood_text(%{"emotion" => emotion} = mood) when is_binary(emotion),
    do: "#{emotion} (#{mood["intensity"]}), stance #{mood["stance"]}"

  defp mood_text(_mood), do: "neutral"

  # --- output -------------------------------------------------------------------

  @doc false
  @spec reaction(struct(), map(), integer()) :: reaction()
  def reaction(inst, reply, turn_number) do
    confidence = Map.get(reply, :confidence) || %{}

    %{
      "npc_id" => inst.npc_id,
      "name" => name(inst),
      "emotion" => label(reply[:emotion]),
      "intensity" => scale(reply[:intensity], length(@intensity)),
      "stance" => level(reply[:stance], @stances),
      "stance_score" => scale(reply[:stance], length(@stances)),
      "confidence" => min_confidence([confidence[:emotion], confidence[:stance]]),
      "turn_number" => turn_number
    }
  end

  # The Jev call of turn `{session_id, turn_number}` as an AI call row, with
  # its `{status, latency_ms}`.
  defp record({session_id, turn_number}, {status, latency_ms}, reply) do
    usage = Map.get(reply, :usage) || %{}
    input = usage[:input_tokens] || 0

    # Jev bills input tokens only (~$0.042 per 1M input tokens).
    cost_micro =
      case usage[:cost] do
        c when is_number(c) -> round(c * 1_000_000)
        _ -> round(input * 0.042)
      end

    AICalls.record(%{
      purpose: @purpose,
      call_type: "jev",
      model: Map.get(reply, :model) || @model,
      status: status,
      latency_ms: latency_ms,
      game_session_id: session_id,
      turn_number: turn_number,
      usage: %{input_tokens: input, output_tokens: 0, cost_ticks: cost_micro * 10_000}
    })
  end

  defp name(inst), do: get_in(inst.personality, ["name"]) || inst.npc_id

  defp label(nil), do: nil
  defp label(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp label(other), do: to_string(other)

  # Jev Score is a 0-indexed fractional level.
  defp scale(x, levels) when is_number(x),
    do: Float.round(min(max(x, 0), levels - 1) / (levels - 1), 2)

  defp scale(_x, _levels), do: nil

  defp level(x, labels) when is_number(x),
    do: Enum.at(labels, x |> round() |> max(0) |> min(length(labels) - 1))

  defp level(_x, _labels), do: nil

  defp min_confidence(values) do
    case Enum.filter(values, &is_number/1) do
      [] -> nil
      nums -> nums |> Enum.min() |> Float.round(2)
    end
  end
end
