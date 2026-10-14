defmodule TalesForge.Board.Workers.ScheduledWake do
  @moduledoc """
  The cron worker of the bot jobs in the team config (`Workflow.Team` `jobs`,
  owner: a bot id; `TalesForge.Workflow.Jobs.config/0`). Each run opens a
  run row and wakes the bot with a card-less `schedule.run` event
  (`TalesForge.Board.Schedule.start_bot_run/3`). Production only
  (`TalesForge.AppRole`), like the other board wakes.
  """
  use Oban.Worker, queue: :board, max_attempts: 3, unique: [period: 300, keys: [:job_id]]

  alias TalesForge.AppRole
  alias TalesForge.Board.Schedule

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    team = Workflow.Team.Source.team()

    case Workflow.Team.job(team, job_id) do
      nil ->
        {:cancel, "no job #{job_id} in the team config"}

      job ->
        if AppRole.role() == :production, do: run(team, job), else: :ok
    end
  end

  @doc "Opens the run of the bot job `job` and wakes the bot."
  @spec run(Workflow.Team.t(), Workflow.Team.job()) :: :ok | {:error, term()}
  def run(team, job) do
    case Schedule.start_bot_run(team, job) do
      {:ok, _run} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
