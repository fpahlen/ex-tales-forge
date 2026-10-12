defmodule TalesForge.WorkLog.Report do
  @moduledoc """
  The work log rows for the /team log page and the CSV export.

  A row is an auto session (`TalesForge.WorkLog.Sessions`) or a manual entry
  (`TalesForge.WorkLog.Entry`). Days run on Europe/Stockholm time. An auto
  session belongs to the day of its first action.

  The CSV export has one row for each founder and day, for the Slicing Pie
  spreadsheet. The app log is the source of truth for hours after go-live.
  """

  alias TalesForge.WorkLog
  alias TalesForge.WorkLog.Entry

  @zone "Europe/Stockholm"

  @typedoc "One log row."
  @type row :: %{
          source: :auto | :manual,
          founder: String.t(),
          date: Date.t(),
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          minutes: non_neg_integer(),
          note: String.t()
        }

  @doc "The log rows of the days `from` to `to` (both inclusive), newest first."
  @spec rows(Date.t(), Date.t()) :: [row()]
  def rows(%Date{} = from, %Date{} = to) do
    auto =
      from
      |> day_start()
      |> WorkLog.sessions(day_start(Date.add(to, 1)))
      |> Enum.map(&auto_row/1)

    manual = from |> WorkLog.entries(to) |> Enum.map(&manual_row/1)

    Enum.sort_by(auto ++ manual, &{&1.date, &1.started_at || ~U[1970-01-01 00:00:00Z]}, &desc/2)
  end

  defp desc({d1, t1}, {d2, t2}) do
    case Date.compare(d1, d2) do
      :eq -> DateTime.compare(t1, t2) != :lt
      order -> order == :gt
    end
  end

  defp auto_row(s) do
    %{
      source: :auto,
      founder: s.founder,
      date: stockholm_date(s.started_at),
      started_at: s.started_at,
      ended_at: s.ended_at,
      minutes: div(s.seconds, 60),
      note: auto_note(s)
    }
  end

  defp manual_row(%Entry{} = e) do
    %{
      source: :manual,
      founder: e.founder,
      date: e.date,
      started_at: nil,
      ended_at: nil,
      minutes: e.minutes,
      note: e.reason
    }
  end

  @doc """
  The work note of an auto session: the count of actions and their types.

      iex> TalesForge.WorkLog.Report.auto_note(%{actions: 3, kinds: ["chat", "turn"]})
      "3 actions: team chat, game turn"
      iex> TalesForge.WorkLog.Report.auto_note(%{actions: 1, kinds: ["move"]})
      "1 action: card move"
  """
  @spec auto_note(map()) :: String.t()
  def auto_note(%{actions: n, kinds: kinds}) do
    word = if n == 1, do: "action", else: "actions"
    "#{n} #{word}: " <> Enum.map_join(kinds, ", ", &WorkLog.kind_label/1)
  end

  @doc "The total minutes of each founder in `rows`."
  @spec totals([row()]) :: [{String.t(), non_neg_integer()}]
  def totals(rows) do
    rows
    |> Enum.group_by(& &1.founder, & &1.minutes)
    |> Enum.map(fn {f, ms} -> {f, Enum.sum(ms)} end)
    |> Enum.sort()
  end

  @doc """
  The CSV text: one row for each founder and day, oldest first. Columns:
  date, founder, auto_hours, manual_hours, total_hours, notes.
  """
  @spec to_csv([row()]) :: String.t()
  def to_csv(rows) do
    lines =
      rows
      |> Enum.group_by(&{&1.date, &1.founder})
      |> Enum.sort_by(fn {{d, f}, _} -> {Date.to_iso8601(d), f} end)
      |> Enum.map(fn {{date, founder}, list} ->
        auto = minutes(list, :auto)
        manual = minutes(list, :manual)

        [
          Date.to_iso8601(date),
          founder,
          hours(auto),
          hours(manual),
          hours(auto + manual),
          list |> Enum.map(& &1.note) |> Enum.uniq() |> Enum.join("; ")
        ]
      end)

    [~w(date founder auto_hours manual_hours total_hours notes) | lines]
    |> Enum.map_join("", &(Enum.map_join(&1, ",", fn v -> escape(v) end) <> "\r\n"))
  end

  defp minutes(list, source),
    do: list |> Enum.filter(&(&1.source == source)) |> Enum.map(& &1.minutes) |> Enum.sum()

  @doc """
  Minutes as hours with two decimals.

      iex> TalesForge.WorkLog.Report.hours(90)
      "1.50"
  """
  @spec hours(non_neg_integer()) :: String.t()
  def hours(minutes), do: :erlang.float_to_binary(minutes / 60, decimals: 2)

  defp escape(value) do
    # A leading =, +, - or @ starts a formula in a spreadsheet. A quote stops that.
    v = value |> to_string() |> guard_formula()

    if String.contains?(v, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(v, "\"", "\"\"") <> "\"",
      else: v
  end

  defp guard_formula(v), do: if(String.starts_with?(v, ~w(= + - @)), do: "'" <> v, else: v)

  @doc "The Europe/Stockholm date of `at`."
  @spec stockholm_date(DateTime.t()) :: Date.t()
  def stockholm_date(%DateTime{} = at),
    do: at |> DateTime.shift_zone!(@zone, TimeZoneInfo.TimeZoneDatabase) |> DateTime.to_date()

  @doc "The start of the Europe/Stockholm day `date`, in UTC."
  @spec day_start(Date.t()) :: DateTime.t()
  def day_start(%Date{} = date) do
    case DateTime.new(date, ~T[00:00:00], @zone, TimeZoneInfo.TimeZoneDatabase) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC", TimeZoneInfo.TimeZoneDatabase)
      {:gap, _, dt} -> DateTime.shift_zone!(dt, "Etc/UTC", TimeZoneInfo.TimeZoneDatabase)
      {:ambiguous, dt, _} -> DateTime.shift_zone!(dt, "Etc/UTC", TimeZoneInfo.TimeZoneDatabase)
    end
  end

  @doc "Today on Europe/Stockholm time."
  @spec today() :: Date.t()
  def today, do: stockholm_date(DateTime.utc_now())
end
