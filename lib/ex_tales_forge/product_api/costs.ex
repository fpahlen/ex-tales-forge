defmodule TalesForge.ProductApi.Costs do
  @moduledoc """
  The costs that the product app gives to Workflow (`TalesForge.ProductApi`).
  Both read `ai_calls` of this app for the last 7 days.

  - `spend/1`: the AI spend for each Stockholm day, as on the costs page (no
    function rows). Today is partial.
  - `intent_latency/1`: the latency of the Jev intent call (purpose
    `"intent"`, status ok).

  Each function returns nil when there is no data or the database does not
  answer.
  """

  import Ecto.Query

  alias TalesForge.Repo
  alias TalesForge.Schemas.AICall

  @zone "Europe/Stockholm"

  @doc """
  The AI spend for each of the last 7 Stockholm days at `now`:
  `%{"days" => [%{"date", "usd"}], "total_usd" => usd}`. Each day is in the
  list, with 0 when nothing was spent. Nil when no priced call is in the window.
  """
  @spec spend(DateTime.t()) :: map() | nil
  def spend(now \\ DateTime.utc_now()) do
    days = last_days(now, 7)
    from = day_start(hd(days))

    rows =
      AICall
      |> where([c], c.inserted_at >= ^from and c.call_type != "function")
      |> where([c], not is_nil(c.cost_micro_usd))
      |> group_by(
        [c],
        fragment("(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date", c.inserted_at, @zone)
      )
      |> select(
        [c],
        {fragment("(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date", c.inserted_at, @zone),
         sum(c.cost_micro_usd)}
      )
      |> Repo.all()
      |> Map.new(fn {date, micro} -> {date, to_int(micro)} end)

    if rows == %{} do
      nil
    else
      %{
        "as_of" => Date.to_iso8601(local_date(now)),
        "days" => Enum.map(days, &%{"date" => Date.to_iso8601(&1), "usd" => usd(rows[&1] || 0)}),
        "total_usd" => usd(rows |> Map.values() |> Enum.sum())
      }
    end
  rescue
    _db_error -> nil
  end

  @doc """
  The Jev intent latency of the last 7 days at `now`: `%{"as_of", "reads",
  "p50_ms", "p95_ms", "max_ms"}`. Nil when there were no reads.
  """
  @spec intent_latency(DateTime.t()) :: map() | nil
  def intent_latency(now \\ DateTime.utc_now()) do
    from = DateTime.add(now, -7, :day)

    latencies =
      AICall
      |> where(
        [c],
        c.purpose == "intent" and c.status == "ok" and c.inserted_at >= ^from and
          not is_nil(c.latency_ms)
      )
      |> select([c], c.latency_ms)
      |> Repo.all()
      |> Enum.sort()

    case latencies do
      [] ->
        nil

      sorted ->
        %{
          "as_of" => Date.to_iso8601(local_date(now)),
          "reads" => length(sorted),
          "p50_ms" => percentile(sorted, 50),
          "p95_ms" => percentile(sorted, 95),
          "max_ms" => List.last(sorted)
        }
    end
  rescue
    _db_error -> nil
  end

  @doc """
  Nearest-rank percentile of a sorted list.

      iex> TalesForge.ProductApi.Costs.percentile([100, 200, 300, 400], 50)
      200
      iex> TalesForge.ProductApi.Costs.percentile([100, 200, 300, 400], 95)
      400
  """
  @spec percentile([number()], number()) :: number()
  def percentile(sorted, p) do
    rank = max(1, ceil(p / 100 * length(sorted)))
    Enum.at(sorted, rank - 1)
  end

  defp last_days(now, n) do
    today = local_date(now)
    for back <- (n - 1)..0//-1, do: Date.add(today, -back)
  end

  defp local_date(now),
    do: now |> DateTime.shift_zone!(@zone, TimeZoneInfo.TimeZoneDatabase) |> DateTime.to_date()

  defp day_start(date) do
    date
    |> DateTime.new!(~T[00:00:00], @zone, TimeZoneInfo.TimeZoneDatabase)
    |> DateTime.shift_zone!("Etc/UTC", TimeZoneInfo.TimeZoneDatabase)
  end

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n
  defp to_int(_other), do: 0

  defp usd(micro), do: Float.round(micro / 1_000_000 * 1.0, 2)
end
