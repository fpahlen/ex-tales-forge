defmodule TalesForge.Board.History do
  @moduledoc """
  The History section of the full idea card: a compact activity list, one
  line per event (who + what + time on Stockholm time).

  The lines come from the card's transitions (moves and the notes the board
  writes) and its comments. History never shows comment text or note text:
  the Comments section shows the comments. Consecutive answers (or deferrals)
  by the same person become one line ("answered 2 questions").

  Pure: pass `now` to get a deterministic result.
  """

  alias TalesForge.Board.Transitions

  @typedoc "One History line. `actor` is the raw actor (an email, `bot:case`, `board`); `link` is `{label, url}` or nil."
  @type entry :: %{
          kind: atom(),
          actor: String.t() | nil,
          text: String.t(),
          link: {String.t(), String.t() | nil} | nil,
          tail: String.t() | nil,
          at: DateTime.t(),
          count: pos_integer()
        }

  @doc "The History lines of `idea`, oldest first."
  @spec entries(map()) :: [entry()]
  def entries(idea) do
    transitions = Enum.map(list(idea, :transitions), &transition(&1, idea))

    comments =
      Enum.map(
        list(idea, :comments),
        &%{
          kind: :comment,
          actor: &1.author,
          text: "commented",
          link: nil,
          tail: nil,
          at: &1.inserted_at
        }
      )

    (transitions ++ comments)
    |> Enum.map(&Map.put(&1, :count, 1))
    |> Enum.sort_by(& &1.at, DateTime)
    |> group()
  end

  defp list(idea, key) do
    case Map.get(idea, key) do
      l when is_list(l) -> l
      _ -> []
    end
  end

  # Consecutive answers (or deferrals) by the same person are one line.
  defp group(entries) do
    entries
    |> Enum.chunk_while(
      nil,
      fn
        e, nil ->
          {:cont, e}

        %{kind: k, actor: a} = e, %{kind: k, actor: a} = acc when k in [:answered, :deferred] ->
          {:cont, %{acc | count: acc.count + 1, at: e.at}}

        e, acc ->
          {:cont, acc, e}
      end,
      fn
        nil -> {:cont, nil}
        acc -> {:cont, acc, nil}
      end
    )
    |> Enum.map(&grouped_text/1)
  end

  defp grouped_text(%{kind: :answered, count: n} = e) when n > 1,
    do: %{e | text: "answered #{n} questions"}

  defp grouped_text(%{kind: :deferred, count: n} = e) when n > 1,
    do: %{e | text: "deferred #{n} questions"}

  defp grouped_text(e), do: e

  defp transition(t, idea) do
    {kind, text, link, tail} =
      case describe(t, idea) do
        {kind, text, link} -> {kind, text, link, nil}
        four -> four
      end

    %{kind: kind, actor: t.actor, text: text, link: link, tail: tail, at: t.inserted_at}
  end

  # A new card.
  defp describe(%{from: nil, actor: "import"}, _idea),
    do: {:added, "added this card from the decision queue", nil}

  defp describe(%{from: nil, actor: "bot:bobby", to: "building"}, _idea),
    do: {:added, "made this card for a PR", nil}

  defp describe(%{from: nil, to: to}, _idea),
    do: {:added, "added this card to #{label(to)}", nil}

  # A founder answers the PR (the column can stay or change).
  defp describe(%{note: "Approved PR #" <> rest}, idea),
    do: pr(:pr_approved, "approved", rest, idea)

  defp describe(%{note: "Changes requested on PR #" <> rest}, idea),
    do: pr(:pr_changes_requested, "asked for changes on", rest, idea)

  # A move to another column.
  defp describe(%{from: "refining", to: "check", actor: "bot:case"}, _idea),
    do: {:refined, "wrote the refinement and moved Refining → Founder check", nil}

  defp describe(%{to: "done", actor: "bot:board", note: note} = t, _idea) when is_binary(note) do
    case Regex.run(~r/prod release (\S+?)(?: \(([^)]+)\))?\./, note) do
      [_, _sha, image] -> {:auto_done, "moved to Done (release #{image})", nil}
      [_, sha] -> {:auto_done, "moved to Done (release #{sha})", nil}
      _ -> {:moved, moved(t), nil}
    end
  end

  defp describe(%{from: from, to: to} = t, _idea) when from != to, do: {:moved, moved(t), nil}

  # Notes in the same column.
  defp describe(%{note: "Answered: " <> _}, _idea), do: {:answered, "answered a question", nil}
  defp describe(%{note: "Deferred: " <> _}, _idea), do: {:deferred, "deferred a question", nil}

  defp describe(%{note: "Open again (not deferred): " <> _}, _idea),
    do: {:reopened, "opened a question again", nil}

  defp describe(%{note: "Decision log entry written: " <> _}, idea),
    do: {:decision, "Decision logged", decision_link(idea)}

  defp describe(%{note: "New commit " <> rest}, idea) do
    if String.contains?(rest, "after approval") do
      number = Map.get(idea, :pr_number)

      {:new_commit_after_approval, "added a new commit to", number && pr_link(number, idea),
       "after approval. The approval stays."}
    else
      case Regex.run(~r/on PR #(\d+)/, rest) do
        [_, n] -> {:new_commit, "added a new commit to", pr_link(String.to_integer(n), idea)}
        _ -> {:new_commit, "added a new commit", nil}
      end
    end
  end

  defp describe(%{note: "PR #" <> rest, actor: actor}, idea) do
    with [_, n] <- Regex.run(~r/^(\d+)/, rest) do
      link = pr_link(String.to_integer(n), idea)

      cond do
        String.contains?(rest, "linked again") -> {:pr_relinked, "linked", link, "again"}
        actor in ["bot:board", "board"] -> {:pr_waiting, "asked for a founder's OK on", link}
        true -> {:pr_linked, "linked", link}
      end
    else
      _ -> {:other, "updated the card", nil}
    end
  end

  defp describe(_t, _idea), do: {:other, "updated the card", nil}

  defp moved(%{from: from, to: to}), do: "moved #{label(from)} → #{label(to)}"

  # The column name without the bot in brackets: "Refining", not "Refining (Case)".
  defp label(column), do: column |> Transitions.label() |> String.replace(~r/ \(.*\)$/, "")

  defp pr(kind, verb, rest, idea) do
    case Regex.run(~r/^(\d+)/, rest) do
      [_, n] -> {kind, verb, pr_link(String.to_integer(n), idea)}
      _ -> {kind, verb <> " the PR", nil}
    end
  end

  defp pr_link(number, idea) do
    label = "PR ##{number}"

    url =
      Enum.find_value(list(idea, :links), fn l ->
        l.kind == "pr" and l.label == label and l.url
      end) ||
        (Map.get(idea, :pr_number) == number && Map.get(idea, :pr_url)) || nil

    {label, url}
  end

  defp decision_link(idea) do
    case Enum.find(list(idea, :links), &(&1.kind == "decision")) do
      nil -> nil
      l -> {"(commit)", l.url}
    end
  end

  @doc """
  The time of a History line on Stockholm time: `HH:MM` today, with the date
  on other days.

      iex> now = ~U[2026-10-11 12:00:00Z]
      iex> TalesForge.Board.History.time(~U[2026-10-11 11:02:00Z], now)
      "13:02"
      iex> TalesForge.Board.History.time(~U[2026-10-09 11:02:00Z], now)
      "9 Oct 13:02"
  """
  @spec time(DateTime.t(), DateTime.t()) :: String.t()
  def time(%DateTime{} = at, %DateTime{} = now \\ DateTime.utc_now()) do
    day = &TalesForgeWeb.TimeAgo.stockholm(&1, "%Y-%m-%d")

    if day.(at) == day.(now),
      do: TalesForgeWeb.TimeAgo.stockholm(at, "%H:%M"),
      else: TalesForgeWeb.TimeAgo.stockholm(at, "%-d %b %H:%M")
  end
end
