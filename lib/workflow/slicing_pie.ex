defmodule Workflow.SlicingPie do
  @moduledoc """
  The Slicing Pie of the team, from the hours in the work log. Pure: the
  caller reads the rows (`TalesForge.WorkLog.Report.rows/2`) and the team
  config (`Workflow.Team.Source`).

  This version counts hours only. Each contributor gets one slice. A slice
  has the total minutes, the hours and the percentage of all minutes. The
  percentages are whole numbers, and their sum is 100.

  The pie shows the logged hours. It is not the final equity split.
  """

  alias Workflow.Team

  @typedoc "One slice of the pie."
  @type slice :: %{
          contributor: String.t(),
          label: String.t(),
          minutes: non_neg_integer(),
          hours: String.t(),
          percent: non_neg_integer(),
          color: String.t(),
          path: String.t()
        }

  # Colours for the slices, in slice order. The list repeats after the end.
  @colors ~w(#b45309 #1d4ed8 #047857 #9d174d #6d28d9 #0f766e #a16207 #374151)

  # The SVG view box is 0 0 100 100. The pie has its centre at 50 50.
  @r 48

  @doc """
  The slices for `rows` (each row has `founder` and `minutes`). The largest
  slice comes first. A contributor with 0 minutes gets no slice.

      iex> team = Workflow.Team.example()
      iex> rows = [%{founder: "ada@x.se", minutes: 90}, %{founder: "lin@x.se", minutes: 30}]
      iex> Workflow.SlicingPie.slices(team, rows) |> Enum.map(&{&1.label, &1.hours, &1.percent})
      [{"Ada", "1.50", 75}, {"Lin", "0.50", 25}]
  """
  @spec slices(Team.t(), [%{founder: String.t(), minutes: non_neg_integer()}]) :: [slice()]
  def slices(%Team{} = team, rows) do
    totals =
      rows
      |> Enum.group_by(& &1.founder, & &1.minutes)
      |> Enum.map(fn {f, ms} -> {f, Enum.sum(ms)} end)
      |> Enum.filter(fn {_f, m} -> m > 0 end)
      |> Enum.sort_by(fn {f, m} -> {-m, f} end)

    sum = totals |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    percents = percents(Enum.map(totals, &elem(&1, 1)))

    totals
    |> Enum.zip(percents)
    |> Enum.with_index()
    |> Enum.map_reduce(0, fn {{{f, m}, pct}, i}, before ->
      slice = %{
        contributor: f,
        label: label(team, f),
        minutes: m,
        hours: hours(m),
        percent: pct,
        color: Enum.at(@colors, rem(i, length(@colors))),
        path: path(before, before + m, sum)
      }

      {slice, before + m}
    end)
    |> elem(0)
  end

  @doc """
  Whole percentages of `minutes` with the sum 100 (largest remainder). An
  empty list or a zero sum gives 0 for each item.

      iex> Workflow.SlicingPie.percents([1, 1, 1])
      [34, 33, 33]
      iex> Workflow.SlicingPie.percents([])
      []
  """
  @spec percents([non_neg_integer()]) :: [non_neg_integer()]
  def percents(minutes) do
    case Enum.sum(minutes) do
      0 -> Enum.map(minutes, fn _ -> 0 end)
      sum -> largest_remainder(minutes, sum)
    end
  end

  defp largest_remainder(minutes, sum) do
    base = Enum.map(minutes, &div(&1 * 100, sum))

    extra =
      minutes
      |> Enum.with_index()
      |> Enum.sort_by(fn {m, i} -> {-rem(m * 100, sum), i} end)
      |> Enum.take(100 - Enum.sum(base))
      |> MapSet.new(&elem(&1, 1))

    base
    |> Enum.with_index()
    |> Enum.map(fn {b, i} -> b + if(MapSet.member?(extra, i), do: 1, else: 0) end)
  end

  @doc """
  The name of the founder for a log email. The local part of the email must
  match the founder handle or the GitHub login. Other emails stay as they are.

      iex> team = Workflow.Team.example()
      iex> {Workflow.SlicingPie.label(team, "Ada-GH@x.se"), Workflow.SlicingPie.label(team, "z@x.se")}
      {"Ada", "z@x.se"}
  """
  @spec label(Team.t(), String.t()) :: String.t()
  def label(%Team{founders: founders}, email) do
    local = email |> String.split("@") |> hd() |> String.downcase()

    Enum.find_value(founders, email, fn f ->
      if local in [f.handle, f.github && String.downcase(f.github)], do: f.name
    end)
  end

  defp hours(minutes), do: :erlang.float_to_binary(minutes / 60, decimals: 2)

  # The SVG path of the slice from `a` to `b` minutes of `sum`. A slice with
  # all the minutes is a full circle.
  defp path(a, b, sum) when b - a == sum,
    do: "M 50 #{50 - @r} A #{@r} #{@r} 0 1 1 49.99 #{50 - @r} Z"

  defp path(a, b, sum) do
    {x1, y1} = point(a / sum)
    {x2, y2} = point(b / sum)
    large = if (b - a) / sum > 0.5, do: 1, else: 0
    "M 50 50 L #{x1} #{y1} A #{@r} #{@r} 0 #{large} 1 #{x2} #{y2} Z"
  end

  # The point on the circle at the share `t` (0 to 1), clockwise from the top.
  defp point(t) do
    angle = 2 * :math.pi() * t - :math.pi() / 2
    {fmt(50 + @r * :math.cos(angle)), fmt(50 + @r * :math.sin(angle))}
  end

  defp fmt(v), do: :erlang.float_to_binary(v * 1.0, decimals: 2)
end
