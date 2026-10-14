defmodule TalesForge.Board.ScheduledWakeTest do
  @moduledoc "Bot jobs: the card-less schedule.run wake, the finish report and no report."
  use TalesForgeWeb.ConnCase, async: false

  alias TalesForge.Board.{Schedule, ScheduledRun}
  alias TalesForge.Board.Workers.{NoReport, Notify}
  alias TalesForge.Workflow.Repo

  @team Workflow.Team.from_map(%{
          "product_name" => "P",
          "repo_url" => "https://example.com/o/p",
          "docs_repo" => "o/p-docs",
          "founders" => [%{"name" => "Ada"}],
          "bots" => [
            %{"id" => "case", "name" => "Case", "role" => "refiner"},
            %{"id" => "bobby", "name" => "Bobby", "role" => "builder"},
            %{"id" => "gentry", "name" => "Gentry", "role" => "checker"}
          ],
          "column_labels" =>
            Map.new(~w(ideas refining check building done parked archived), &{&1, &1}),
          "jobs" => [
            %{
              "id" => "playtest",
              "name" => "Playtest run",
              "cron" => "0 7 * * 1-5",
              "owner" => "gentry",
              "limit_min" => 30
            }
          ]
        })

  @job Workflow.Team.job(@team, "playtest")
  @now ~U[2026-10-15 07:00:00.000000Z]

  setup do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:wake, Plug.Conn.get_req_header(conn, "x-board-event"), Jason.decode!(body)}
      )

      Req.Test.json(conn, %{"ok" => true})
    end)

    Application.put_env(:ex_tales_forge, :board_req_options, plug: {Req.Test, __MODULE__})
    old = Application.get_env(:ex_tales_forge, :board_bots)

    Application.put_env(:ex_tales_forge, :board_bots,
      gentry: [webhook_url: "https://gentry.example/hook", webhook_key: "k", api_token: "tok-g"],
      bobby: [api_token: "tok-b"]
    )

    on_exit(fn ->
      Application.delete_env(:ex_tales_forge, :board_req_options)

      if old,
        do: Application.put_env(:ex_tales_forge, :board_bots, old),
        else: Application.delete_env(:ex_tales_forge, :board_bots)
    end)

    :ok
  end

  test "a bot job wakes the bot with a card-less schedule.run event and opens the run" do
    {:ok, run} = Schedule.start_bot_run(@team, @job, @now)

    assert %ScheduledRun{status: "open", owner: "gentry", job_id: "playtest"} = run
    assert run.deadline_at == DateTime.add(@now, 30 * 60)

    assert_received {:wake, ["schedule.run"], body}
    refute Map.has_key?(body, "idea")
    assert body["job"] == %{"id" => "playtest", "name" => "Playtest run", "limit_min" => 30}
    assert body["run"]["id"] == run.id
    assert body["finish"]["path"] == "/internal/board/runs/#{run.id}/finish"
  end

  test "the run stays open before the deadline and gets no report after it" do
    {:ok, run} = Schedule.start_bot_run(@team, @job, @now)

    assert {:wait, 60} = Schedule.close_if_no_report(run.id, DateTime.add(@now, 29 * 60))
    assert Repo.get!(ScheduledRun, run.id).status == "open"

    assert :no_report = Schedule.close_if_no_report(run.id, DateTime.add(@now, 30 * 60))

    assert %{status: "no_report", detail: "No report in 30 min."} =
             Repo.get!(ScheduledRun, run.id)

    assert :closed = Schedule.close_if_no_report(run.id, DateTime.add(@now, 31 * 60))
  end

  test "the limit job snoozes until the deadline" do
    {:ok, run} = Schedule.start_bot_run(@team, @job, DateTime.utc_now())
    assert {:snooze, s} = NoReport.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert s in 1..1800
  end

  test "POST /internal/board/runs/:id/finish: the owner reports, others cannot", %{conn: conn} do
    {:ok, run} = Schedule.start_bot_run(@team, @job, @now)
    path = "/internal/board/runs/#{run.id}/finish"

    assert %{"error" => _} =
             conn |> auth("tok-b") |> post(path, %{"status" => "ok"}) |> json_response(403)

    assert %{"error" => _} =
             conn |> auth("tok-g") |> post(path, %{"status" => "maybe"}) |> json_response(422)

    assert %{"status" => "ok", "job_id" => "playtest"} =
             conn
             |> auth("tok-g")
             |> post(path, %{"status" => "ok", "detail" => "12 turns"})
             |> json_response(200)

    assert %{status: "ok", detail: "12 turns"} = Repo.get!(ScheduledRun, run.id)

    assert conn |> auth("tok-g") |> post(path, %{"status" => "ok"}) |> json_response(422)

    assert conn
           |> auth("tok-g")
           |> post("/internal/board/runs/#{Ecto.UUID.generate()}/finish", %{"status" => "ok"})
           |> json_response(404)
  end

  test "a late report replaces no report" do
    {:ok, run} = Schedule.start_bot_run(@team, @job, @now)
    :no_report = Schedule.close_if_no_report(run.id, DateTime.add(@now, 3600))

    assert {:ok, %{status: "failed"}} =
             Schedule.finish_by_bot(run.id, :gentry, %{"status" => "failed"})
  end

  test "the cron table wakes the bot jobs through ScheduledWake" do
    assert {"0 7 * * 1-5", TalesForge.Board.Workers.ScheduledWake,
            [args: %{"job_id" => "playtest"}]} in Workflow.Team.crontab(
             @team,
             TalesForge.Board.Workers.ScheduledWake
           )
  end

  test "run_job has no card" do
    {:ok, run} = Schedule.start_bot_run(@team, @job, @now)
    changeset = Notify.run_job(:gentry, @job, run)
    assert changeset.changes.args["event"] == "schedule.run"
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)
end
