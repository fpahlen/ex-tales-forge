defmodule TalesForge.Workflow.Jobs do
  @moduledoc """
  The Oban instance of Workflow (`TalesForge.Workflow.Oban`).

  This instance uses `TalesForge.Workflow.Repo` and keeps its jobs in the
  Postgres schema `workflow`. A bot wake-up job and the board or chat change
  that makes it go into the same transaction. Use these functions, not the
  default `Oban` instance, for Workflow jobs.
  """

  alias Ecto.Multi

  @name TalesForge.Workflow.Oban

  @doc "The name of the Workflow Oban instance."
  @spec name() :: atom()
  def name, do: @name

  @doc """
  The start config of the Workflow Oban instance: the app config plus the
  cron plugin with the scheduled jobs of the team config
  (`Workflow.Team.crontab/2`, cron lines in UTC). A code job runs its own
  worker; a bot job runs the worker of config `:schedule_bot_worker`
  (`TalesForge.Board.Workers.ScheduledWake`), which wakes the bot. Each exclusive job gets its own queue with limit 1
  (`Workflow.Team.exclusive_queues/1`). The team config is the only schedule
  source.
  """
  @spec config() :: keyword()
  def config do
    config = Application.fetch_env!(:ex_tales_forge, @name)
    team = Workflow.Team.Source.team()

    cron =
      {Oban.Plugins.Cron,
       crontab:
         Workflow.Team.crontab(team, Application.get_env(:ex_tales_forge, :schedule_bot_worker))}

    config
    |> Keyword.update(:plugins, [cron], &(&1 ++ [cron]))
    |> Keyword.update(:queues, Workflow.Team.exclusive_queues(team), fn queues ->
      Keyword.merge(queues, Workflow.Team.exclusive_queues(team))
    end)
  end

  @doc "Inserts one job into the Workflow Oban instance."
  @spec insert(Oban.Job.changeset()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def insert(changeset), do: Oban.insert(@name, changeset)

  @doc "Adds a job insert to `multi`, in the transaction of the Workflow repo."
  @spec insert(Multi.t(), Multi.name(), Oban.Job.changeset() | (map() -> Oban.Job.changeset())) ::
          Multi.t()
  def insert(%Multi{} = multi, step, changeset_or_fun),
    do: Oban.insert(@name, multi, step, changeset_or_fun)
end
