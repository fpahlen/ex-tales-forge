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

  @doc "Inserts one job into the Workflow Oban instance."
  @spec insert(Oban.Job.changeset()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def insert(changeset), do: Oban.insert(@name, changeset)

  @doc "Adds a job insert to `multi`, in the transaction of the Workflow repo."
  @spec insert(Multi.t(), Multi.name(), Oban.Job.changeset() | (map() -> Oban.Job.changeset())) ::
          Multi.t()
  def insert(%Multi{} = multi, step, changeset_or_fun),
    do: Oban.insert(@name, multi, step, changeset_or_fun)
end
