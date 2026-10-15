defmodule TalesForge.Playtest.FocusGroup.Brief do
  @moduledoc """
  The interview brief for one persona (call type: function). It has two parts:

  1. The fixed product-gap list in `priv/playtest/focus_group/gaps.md`.
  2. A summary of the persona's last finished playtest run: module, turns,
     stop reason, the Jev session score and the last lines of the transcript.

  The brief has a hard token cap (`@max_tokens`). We estimate tokens as
  characters / 4. The gap list gets at most half of the cap. The session summary
  gets the rest. Text above the cap is cut.
  """

  import Ecto.Query

  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.{PlaytestRun, PlaytestScore}

  @max_tokens 1_200
  @chars_per_token 4
  @tail_lines 8
  @line_chars 240

  @doc "The hard token cap for one brief."
  @spec max_tokens() :: pos_integer()
  def max_tokens, do: @max_tokens

  @doc "Estimated tokens for a text (characters / 4, rounded up)."
  @spec tokens(String.t()) :: non_neg_integer()
  def tokens(text), do: div(String.length(text) + @chars_per_token - 1, @chars_per_token)

  @doc """
  The product gaps from `gaps.md`: `%{id, title, keywords, text}` in file order.
  """
  @spec gaps() :: [map()]
  def gaps do
    gaps_path()
    |> File.read!()
    |> String.split("\n")
    |> Enum.flat_map(&parse_gap/1)
  end

  defp gaps_path,
    do: Application.app_dir(:ex_tales_forge, "priv/playtest/focus_group/gaps.md")

  defp parse_gap("- " <> line) do
    case String.split(line, "|", parts: 4) |> Enum.map(&String.trim/1) do
      [id, title, keywords, text] ->
        [
          %{
            id: id,
            title: title,
            keywords: keywords |> String.split(",") |> Enum.map(&String.trim/1),
            text: text
          }
        ]

      _ ->
        []
    end
  end

  defp parse_gap(_line), do: []

  @doc """
  The brief for a persona, as one text under the token cap. `opts`:
  `:session_summary` replaces the summary from the database (tests and dry runs).
  """
  @spec build(map(), keyword()) :: String.t()
  def build(persona, opts \\ []) do
    half = div(@max_tokens, 2) * @chars_per_token
    gap_text = gaps() |> Enum.map_join("\n", &"- #{&1.title}: #{&1.text}") |> cap(half)

    rest = @max_tokens * @chars_per_token - String.length(gap_text)

    summary =
      opts
      |> Keyword.get_lazy(:session_summary, fn -> last_session_summary(persona.id) end)
      |> cap(rest - 200)

    """
    Known product gaps (from playtests and forum research):
    #{gap_text}

    Your last session:
    #{summary}
    """
    |> cap(@max_tokens * @chars_per_token)
  end

  @doc """
  A short summary of the persona's last finished run, or a fixed line when
  there is none. Built from the database only, with no AI call.
  """
  @spec last_session_summary(String.t()) :: String.t()
  def last_session_summary(persona_id) do
    run =
      PlaytestRun
      |> where([r], r.persona == ^persona_id and r.status == "finished")
      |> order_by([r], desc: r.finished_at, desc: r.inserted_at)
      |> limit(1)
      |> Repo.one()

    case run do
      nil -> "No finished playtest run was found for you. Answer from your persona notes."
      run -> summarize(run)
    end
  end

  defp summarize(run) do
    score =
      PlaytestScore
      |> where([s], s.playtest_run_id == ^run.id and s.kind == "session_affect")
      |> order_by([s], asc: s.inserted_at)
      |> limit(1)
      |> Repo.one()

    [
      "Module #{run.module}, #{run.turns_played} of #{run.turn_limit} turns, stopped by #{run.stop_reason || "the turn limit"}.",
      score && "Jev session score #{format_score(score.overall)} of 5.",
      score && score.rationale && "Score note: #{score.rationale}",
      "Last lines of the session:",
      tail(run.game_session_id)
    ]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join("\n")
  end

  defp format_score(nil), do: "?"
  defp format_score(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)

  defp tail(nil), do: ""

  defp tail(session_id) do
    session_id
    |> GameSessions.get_session!()
    |> Repo.preload([:turns, :scenes])
    |> GameSessions.transcript()
    |> Enum.take(-@tail_lines)
    |> Enum.map_join("\n", fn %{role: role, text: text} ->
      "[#{role}] #{text |> to_string() |> String.replace("\n", " ") |> cap(@line_chars)}"
    end)
  end

  @doc false
  @spec cap(String.t(), integer()) :: String.t()
  def cap(text, max) when max <= 0, do: String.slice(text, 0, 0)

  def cap(text, max) do
    if String.length(text) <= max,
      do: text,
      else: String.slice(text, 0, max - 1) <> "…"
  end
end
