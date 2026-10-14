defmodule TalesForge.ProductApi.PersonaScores do
  @moduledoc """
  The persona scores that the product app gives to Workflow
  (`TalesForge.ProductApi`). The scores are the Jev turn scores
  (`playtest_scores` kind `"turn_affect"`) of the playtest runs that started
  on this app since 2026-10-07. Each persona gets the confidence-weighted
  score (`TalesForge.Playtest.JevHeadline`), the low-confidence share and the
  number of scored turns.

  `scores/0` returns nil when there is no scored turn or the database does
  not answer.
  """

  import Ecto.Query

  alias TalesForge.Playtest.JevHeadline
  alias TalesForge.Repo
  alias TalesForge.Schemas.{PlaytestRun, PlaytestScore}

  @since ~D[2026-10-07]

  @doc "The first day of the window (2026-10-07, the start of the persona playtests)."
  @spec since() :: Date.t()
  def since, do: @since

  @doc """
  The scores: `%{"since", "runs", "by_persona" => %{persona => %{"score",
  "low_confidence_pct", "turns"}}}`, or nil when there is no scored turn.
  """
  @spec scores() :: map() | nil
  def scores do
    from = DateTime.new!(@since, ~T[00:00:00], "Etc/UTC")

    rows =
      PlaytestScore
      |> join(:inner, [s], r in PlaytestRun, on: r.id == s.playtest_run_id)
      |> where([s, r], s.kind == "turn_affect" and r.started_at >= ^from)
      |> order_by([s], asc: s.turn_number, desc: s.inserted_at, desc: s.id)
      |> select([s, r], %{
        run: r.id,
        persona: r.persona,
        turn: s.turn_number,
        overall: s.overall,
        confidence: s.confidence
      })
      |> Repo.all()
      |> Enum.uniq_by(&{&1.run, &1.turn})
      |> Enum.reject(&is_nil(&1.overall))

    if rows == [], do: nil, else: summary(rows)
  rescue
    _db_error -> nil
  end

  defp summary(rows) do
    by_persona =
      rows
      |> Enum.group_by(& &1.persona)
      |> Map.new(fn {persona, turns} ->
        h =
          JevHeadline.summarize(
            Enum.map(turns, &%{overall: &1.overall, confidence: &1.confidence || 0.0})
          )

        {persona,
         %{"score" => h.score, "low_confidence_pct" => pct(h.unsure_share), "turns" => h.turns}}
      end)

    %{
      "since" => Date.to_iso8601(@since),
      "runs" => rows |> Enum.map(& &1.run) |> Enum.uniq() |> length(),
      "by_persona" => by_persona
    }
  end

  defp pct(nil), do: nil
  defp pct(share), do: round(share * 100)
end
