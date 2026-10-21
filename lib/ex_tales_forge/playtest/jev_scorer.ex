defmodule TalesForge.Playtest.JevScorer do
  @moduledoc """
  TypeSafe Jev persona-affect scoring for a finished playtest run.

  One Jev call asks `persona_session_affect` plus `persona_turn_affect_N` for
  each turn, with five persona-grounded levels from
  `TalesForge.Playtest.AffectLevels`. State is player-visible text only:
  opening scene and per-turn player action + GM narration — never the
  gm_reasoning event or other player_aware=false events.

  Primary auto-score when a TypeSafe key is configured (see `configured?/0`;
  `config/runtime.exs` maps `TYPESAFE_API_KEY` to `config :jev, :api_key`).
  Model pinned to `jev-1.13.0`. Usage is recorded in `ai_calls` as purpose
  `scorer`, call_type `jev`. Scale stored as 1–5 (`jev_fractional + 1`); Jev's native score is
  0-indexed.
  """

  require Logger

  alias TalesForge.AICalls
  alias TalesForge.Config
  alias TalesForge.Playtest.{AffectLevels, JevScoring, Personas, Reports}
  alias TalesForge.Scenes

  @model "jev-1.13.0"
  @scoreable ~w(finished stopped)
  @rubric "jev-affect-v1"

  @doc """
  True when a TypeSafe API key is configured in `config :jev, :api_key`.

  Only the Application env is read, never the OS environment, so tests decide
  the key with `Application.put_env/3`.
  """
  @spec configured?() :: boolean()
  def configured? do
    case Application.get_env(:jev, :api_key) do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  @doc """
  Scores a run with Jev. Inserts one `session_affect` row and one `turn_affect`
  row per turn. Returns `{:ok, session_score}` or `{:error, reason}`.
  """
  def score(run_id) do
    case do_score(run_id) do
      {:ok, score} ->
        {:ok, score}

      {:error, reason} = error ->
        Logger.warning("jev scoring failed run=#{run_id} reason=#{inspect(reason)}")
        error
    end
  end

  defp do_score(run_id) do
    with :ok <- ready(),
         {:ok, run} <- Reports.get_run(run_id),
         :ok <-
           if(run.status in @scoreable, do: :ok, else: {:error, {:not_scoreable, run.status}}),
         {:ok, persona} <- Personas.fetch(run.persona),
         state <- build_state(run),
         questions <- questions(persona, state.turns),
         {:ok, reply, timing} <- call_jev(state.text, questions),
         :ok <- record_usage(run, reply, timing) do
      persist(%JevScoring{run: run, persona: persona, turns: state.turns, reply: reply})
    end
  end

  defp ready do
    cond do
      not Config.playtest_runner?() -> {:error, :disabled}
      not configured?() -> {:error, :jev_not_configured}
      true -> :ok
    end
  end

  @doc """
  The rubric version stored on a persona's Jev scores: the rubric name plus a
  short hash of that persona's question and level text.
  """
  @spec rubric_version(String.t()) :: String.t()
  def rubric_version(persona_id), do: "#{@rubric}-#{AffectLevels.rubric_hash(persona_id)}"

  @doc false
  def build_state(run) do
    opening = Scenes.opening(run.game_session_id)
    turns = Reports.turn_records(run.game_session_id)

    opening_block =
      case opening do
        nil -> nil
        scene -> "Opening (GM):\n#{scene.narrative}"
      end

    turn_blocks =
      Enum.map(turns, fn turn ->
        [
          "Turn #{turn.turn_number}",
          "Player: #{turn.player_action}",
          "GM: #{turn.narrative}"
        ]
        |> Enum.join("\n")
      end)

    text =
      [opening_block | turn_blocks]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    %{text: text, turns: turns, opening: opening}
  end

  @doc false
  def questions(persona, turns) do
    levels = AffectLevels.levels(persona.id)
    session = {AffectLevels.session_question(persona.id, persona.name), levels}

    turn_qs =
      Map.new(turns, fn turn ->
        key = :"persona_turn_affect_#{turn.turn_number}"
        {key, {AffectLevels.turn_question(persona.id, persona.name, turn.turn_number), levels}}
      end)

    Map.put(turn_qs, :persona_session_affect, session)
  end

  defp call_jev(state, questions) do
    started_at = DateTime.utc_now()
    t0 = System.monotonic_time(:millisecond)

    case Jev.HTTP.post(state, questions, model: @model) do
      {:ok, reply} ->
        latency_ms = System.monotonic_time(:millisecond) - t0
        {:ok, reply, %{started_at: started_at, latency_ms: latency_ms}}

      {:error, reason} ->
        {:error, {:jev, reason}}
    end
  end

  defp record_usage(run, reply, timing) do
    usage = Map.get(reply, :usage) || %{}
    input = usage[:input_tokens] || usage["input_tokens"] || 0
    # Jev bills input only; published ~$0.042 / 1M input tokens.
    cost_micro =
      case usage[:cost] || usage["cost"] do
        c when is_number(c) -> round(c * 1_000_000)
        _ -> round(input / 1_000_000 * 0.042 * 1_000_000)
      end

    AICalls.record(%{
      purpose: "scorer",
      call_type: "jev",
      model: Map.get(reply, :model) || @model,
      status: "ok",
      latency_ms: timing.latency_ms,
      started_at: timing.started_at,
      game_session_id: run.game_session_id,
      usage: %{
        input_tokens: input,
        output_tokens: 0,
        cost_ticks: cost_micro * 10_000
      }
    })

    :ok
  end

  defp persist(%JevScoring{persona: persona, reply: reply} = scoring) do
    JevScoring.persist(%{
      scoring
      | version: rubric_version(persona.id),
        model: Map.get(reply, :model) || @model
    })
  end

  @doc false
  defdelegate scale(score), to: JevScoring
end
