defmodule TalesForge.Board.Workers.NoReport do
  @moduledoc """
  The time limit of a bot run (`TalesForge.Board.Schedule.start_bot_run/3`).
  It runs at `deadline_at`. A run that is still open gets "no_report"
  (`TalesForge.Board.Schedule.close_if_no_report/2`). When it runs before the
  deadline, it waits until the deadline.
  """
  use Oban.Worker, queue: :board, max_attempts: 5

  alias TalesForge.Board.{Schedule, ScheduledRun}

  @doc "The job for the time limit of `run`, at its `deadline_at`."
  @spec job(ScheduledRun.t()) :: Oban.Job.changeset()
  def job(%ScheduledRun{id: id, deadline_at: deadline}),
    do: new(%{"run_id" => id}, scheduled_at: deadline)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => id}}) do
    case Schedule.close_if_no_report(id) do
      {:wait, seconds} -> {:snooze, seconds}
      _ -> :ok
    end
  end
end
