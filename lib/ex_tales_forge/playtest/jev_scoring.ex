defmodule TalesForge.Playtest.JevScoring do
  @moduledoc """
  What `TalesForge.Playtest.JevScorer` stores for one run: the playtest
  `run`, its `persona`, the scored `turns`, Jev's `reply`, the rubric
  `version` and the Jev `model` that scored it.
  """

  alias TalesForge.Repo
  alias TalesForge.Schemas.PlaytestScore

  defstruct run: nil, persona: nil, turns: [], reply: %{}, version: nil, model: nil

  @type t :: %__MODULE__{
          run: map() | nil,
          persona: map() | nil,
          turns: [map()],
          reply: map(),
          version: String.t() | nil,
          model: String.t() | nil
        }

  @doc """
  Inserts one `session_affect` row and one `turn_affect` row per turn in a
  transaction; returns `{:ok, session_row}` or `{:error, reason}`.
  """
  @spec persist(t()) :: {:ok, struct()} | {:error, term()}
  def persist(%__MODULE__{run: run, turns: turns} = scoring) do
    Repo.transaction(fn ->
      session = insert_affect!(run, session_attrs(scoring))
      for turn <- turns, do: insert_affect!(run, turn_attrs(scoring, turn))
      session
    end)
  end

  defp session_attrs(%__MODULE__{reply: reply} = scoring) do
    key = :persona_session_affect
    confidence = confidence(reply, key)

    scoring
    |> row(key, {"session_affect", nil})
    |> Map.put(:scores, %{
      "persona_session_affect" => %{"score" => scale(reply[key]), "confidence" => confidence}
    })
  end

  defp turn_attrs(%__MODULE__{reply: reply} = scoring, turn) do
    key = :"persona_turn_affect_#{turn.turn_number}"

    scoring
    |> row(key, {"turn_affect", turn.turn_number})
    |> Map.put(:scores, %{
      "persona_turn_affect" => %{
        "score" => scale(reply[key]),
        "confidence" => confidence(reply, key),
        "turn_number" => turn.turn_number
      }
    })
  end

  defp row(%__MODULE__{reply: reply, version: version, model: model}, key, {kind, turn_number}) do
    %{
      kind: kind,
      turn_number: turn_number,
      model: model,
      rubric_version: version,
      overall: scale(reply[key]),
      confidence: confidence(reply, key),
      probabilities: stringify_probs((Map.get(reply, :probabilities) || %{})[key])
    }
  end

  defp confidence(reply, key), do: (Map.get(reply, :confidence) || %{})[key]

  defp insert_affect!(run, attrs) do
    %PlaytestScore{}
    |> PlaytestScore.changeset(
      Map.merge(attrs, %{
        playtest_run_id: run.id,
        source: "jev",
        rationale: nil
      })
    )
    |> Repo.insert!()
  end

  # Jev Score is 0-indexed fractional; we store the 1–5 human scale.
  @doc false
  @spec scale(number() | nil) :: float() | nil
  def scale(nil), do: nil
  def scale(score) when is_number(score), do: Float.round(score + 1.0, 2)

  defp stringify_probs(nil), do: %{}

  defp stringify_probs(probs) when is_map(probs) do
    Map.new(probs, fn {k, v} -> {to_string(k), v} end)
  end
end
