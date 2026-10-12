defmodule TalesForge.WorkLog.ReportTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.WorkLog
  alias TalesForge.WorkLog.Report

  doctest Report

  @ada "ada@example.com"

  defp event!(at, kind \\ "chat") do
    WorkLog.put_peer_events(
      [%{"founder" => @ada, "kind" => kind, "ref" => Ecto.UUID.generate(), "at" => at}],
      "playtest"
    )
  end

  test "rows join the auto sessions and the manual entries with their notes" do
    event!("2026-10-12T08:00:00Z", "turn")
    event!("2026-10-12T08:30:00Z", "chat")
    event!("2026-10-12T08:40:00Z", "comment")

    {:ok, _} =
      WorkLog.add_entry(@ada, %{
        "date" => "2026-10-11",
        "hours" => "2.5",
        "reason" => "Imported from spreadsheet"
      })

    rows = Report.rows(~D[2026-10-11], ~D[2026-10-12])

    assert [
             %{source: :auto, minutes: 10, note: "2 actions: team chat, card comment"},
             %{source: :auto, minutes: 0, note: "1 action: game turn"},
             %{
               source: :manual,
               date: ~D[2026-10-11],
               minutes: 150,
               note: "Imported from spreadsheet"
             }
           ] = rows

    assert Report.totals(rows) == [{@ada, 160}]
  end

  test "a session belongs to the Stockholm day of its first action" do
    # 23:30 UTC on 11 October is 01:30 on 12 October in Stockholm.
    event!("2026-10-11T23:30:00Z")
    assert [%{date: ~D[2026-10-12]}] = Report.rows(~D[2026-10-12], ~D[2026-10-12])
    assert Report.rows(~D[2026-10-11], ~D[2026-10-11]) == []
  end

  test "the CSV has one row for each founder and day" do
    event!("2026-10-12T08:00:00Z")
    event!("2026-10-12T08:12:00Z")

    {:ok, _} =
      WorkLog.add_entry(@ada, %{"date" => "2026-10-12", "hours" => 1, "reason" => "Plan, review"})

    {:ok, _} =
      WorkLog.add_entry("bo@example.com", %{
        "date" => "2026-10-12",
        "hours" => 0.5,
        "reason" => "=SUM(A1)"
      })

    csv = ~D[2026-10-12] |> Report.rows(~D[2026-10-12]) |> Report.to_csv()

    assert String.split(csv, "\r\n", trim: true) == [
             "date,founder,auto_hours,manual_hours,total_hours,notes",
             ~s(2026-10-12,ada@example.com,0.20,1.00,1.20,"2 actions: team chat; Plan, review"),
             "2026-10-12,bo@example.com,0.00,0.50,0.50,'=SUM(A1)"
           ]
  end

  test "add_entry/2 checks the hours and the reason" do
    assert {:error, cs} =
             WorkLog.add_entry(@ada, %{"date" => "2026-10-12", "hours" => "0", "reason" => ""})

    assert %{hours: [_], reason: [_]} = errors_on(cs)

    assert {:error, _} =
             WorkLog.add_entry(@ada, %{
               "date" => "2026-10-12",
               "hours" => "25",
               "reason" => "Too long"
             })
  end
end
