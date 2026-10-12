defmodule TalesForgeWeb.WorkLogExportController do
  @moduledoc """
  `GET /team/work-log.csv?from=<date>&to=<date>`: the work log as CSV, one
  row for each founder and day (`TalesForge.WorkLog.Report.to_csv/1`), for
  the Slicing Pie spreadsheet. Behind the team sign-in like every page. The
  default range is the last 30 days (Europe/Stockholm).
  """

  use TalesForgeWeb, :controller

  alias TalesForge.WorkLog.Report

  @doc "Sends the CSV file of the range."
  @spec csv(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def csv(conn, params) do
    to = date(params["to"]) || Report.today()
    from = date(params["from"]) || Date.add(to, -29)

    if Date.compare(from, to) == :gt do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "Give a start date on or before the end date.")
    else
      send_download(conn, {:binary, from |> Report.rows(to) |> Report.to_csv()},
        filename: "work-log-#{from}-#{to}.csv",
        content_type: "text/csv"
      )
    end
  end

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp date(_), do: nil
end
