defmodule TalesForge.Board.ScheduleTest do
  @moduledoc "The scheduled runs: code jobs record ok or failed and start no bot."
  use TalesForge.DataCase, async: false

  alias TalesForge.Board.{Schedule, ScheduledRun}
  alias TalesForge.PrFeed.Reconcile
  alias TalesForge.Workflow.Repo

  doctest Schedule

  test "track/2 records an ok run" do
    Schedule.subscribe()
    assert {:ok, 2} = Schedule.track("sweep", fn -> {:ok, 2} end)
    assert %{"sweep" => %ScheduledRun{status: "ok", owner: "code"} = run} = Schedule.last_runs()
    assert run.finished_at
    assert_received {:schedule, :changed}
  end

  test "track/2 records a failed run for an error and for an exception" do
    assert {:error, :down} = Schedule.track("a", fn -> {:error, :down} end)
    assert %{"a" => %{status: "failed", detail: ":down"}} = Schedule.last_runs()

    assert_raise RuntimeError, fn -> Schedule.track("b", fn -> raise "boom" end) end
    assert %{"b" => %{status: "failed", detail: "boom"}} = Schedule.last_runs()
  end

  test "last_runs/0 gives the newest run of each job" do
    {:ok, old} = Schedule.start("j", "code", ~U[2026-10-14 06:00:00Z])
    Schedule.finish(old, "failed")
    {:ok, new} = Schedule.start("j", "code", ~U[2026-10-14 07:00:00Z])
    Schedule.finish(new, "ok")
    assert %{"j" => %{id: id, status: "ok"}} = Schedule.last_runs()
    assert id == new.id
  end

  test "the PR feed backup job records its run and inserts no bot wake" do
    assert :ok = perform_job(Reconcile, %{"job_id" => "pr_feed_backup"})
    assert %{"pr_feed_backup" => %{status: "ok"}} = Schedule.last_runs()
    assert Repo.aggregate(from(j in "oban_jobs", prefix: "workflow"), :count) == 0
  end

  test "the team config is the schedule source of the Workflow Oban instance" do
    {_, cron} =
      Enum.find(TalesForge.Workflow.Jobs.config()[:plugins], &match?({Oban.Plugins.Cron, _}, &1))

    workers = Enum.map(cron[:crontab], &elem(&1, 1))

    assert TalesForge.Board.Workers.StuckCards in workers
    assert TalesForge.Board.Workers.MentionSweep in workers
    assert Reconcile in workers
  end

  defp perform_job(worker, args), do: worker.perform(%Oban.Job{args: args})
end
