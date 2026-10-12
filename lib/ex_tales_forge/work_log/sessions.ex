defmodule TalesForge.WorkLog.Sessions do
  @moduledoc """
  Work sessions from activity events. Pure functions, no database.

  A session starts at the first action of a founder. Each next action less
  than `idle_minutes` after the previous action extends the session. A
  longer gap closes the session at its last action. Thus the idle time does
  not count. A session with one action has a length of zero.
  """

  alias TalesForge.WorkLog.Event

  @idle_minutes 15

  @typedoc "One work session of one founder."
  @type session :: %{
          founder: String.t(),
          started_at: DateTime.t(),
          ended_at: DateTime.t(),
          seconds: non_neg_integer(),
          actions: pos_integer(),
          kinds: [String.t()]
        }

  @doc "The idle limit in minutes."
  @spec idle_minutes() :: pos_integer()
  def idle_minutes, do: @idle_minutes

  @doc """
  Returns the sessions of the events, for each founder, oldest first.

      iex> t = ~U[2026-10-12 10:00:00Z]
      iex> ev = fn min, kind -> %{founder: "a@x", kind: kind, at: DateTime.add(t, min * 60)} end
      iex> [s1, s2] = TalesForge.WorkLog.Sessions.build([ev.(0, "chat"), ev.(10, "comment"), ev.(40, "turn")])
      iex> {s1.seconds, s1.kinds, s2.seconds}
      {600, ["chat", "comment"], 0}
  """
  @spec build([Event.t() | map()], pos_integer()) :: [session()]
  def build(events, idle_minutes \\ @idle_minutes) do
    limit = idle_minutes * 60

    events
    |> Enum.group_by(& &1.founder)
    |> Enum.flat_map(fn {founder, list} ->
      list
      |> Enum.sort_by(& &1.at, DateTime)
      |> Enum.chunk_while(nil, &chunk(&1, &2, limit), &finish/1)
      |> Enum.map(&session(founder, &1))
    end)
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  defp chunk(event, nil, _limit), do: {:cont, [event]}

  defp chunk(event, [last | _] = acc, limit) do
    if DateTime.diff(event.at, last.at) < limit,
      do: {:cont, [event | acc]},
      else: {:cont, Enum.reverse(acc), [event]}
  end

  defp finish(nil), do: {:cont, nil}
  defp finish(acc), do: {:cont, Enum.reverse(acc), nil}

  defp session(founder, [first | _] = events) do
    last = List.last(events)

    %{
      founder: founder,
      started_at: first.at,
      ended_at: last.at,
      seconds: DateTime.diff(last.at, first.at),
      actions: length(events),
      kinds: events |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort()
    }
  end
end
